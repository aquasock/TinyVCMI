#!/usr/bin/env python3
"""Drive the DDR3 write image on the board: write leveling, writes, read-back.

The image (fpga/ddr3_write, built by tools/build_ddr3_write.sh and loaded with
TinyTang's `tangload`) has four modes -- idle, write leveling, writes, reads --
chosen over the link.  This tool opens TinyTang's `fpgapipe` once and:

  status      prints the decoded status
  level       write leveling: steps every lane's WSTEP from --start to --stop
              and prints, per lane, how many PCLK cycles of 65535 the
              device's sampled CK read high; the 0 -> 1 transition is where
              the lane's strobe meets CK
  rw          sets each lane's WSTEP (--wstep, one value or four), writes the
              pattern across row 0 for --write-ms, reads it back and prints,
              per lane, the cycles of the read stream in which all eight DQ
              words were one rotation of the pattern (and its inverse on odd
              DQ), with the snapshot and the rotation found
  rwsweep     rw at every WSTEP from --start to --stop in --step steps, the
              same on every lane, one line per setting
  calibrate   align all 32 IDES8_MEM words with CALIB, sweep the complete
              signed read-delay range per lane, centre the observed passing
              window, and verify lane alignment across repeated read sessions
  memtest     write/read several patterns across selected banks and rows
  align       write a pattern, read it back and verify the read-data
              aligner's burst: each lane's trained rotation, the aligned
              snapshot against the pattern and against a host-side
              derotation of the raw snapshot, and the per-window counts
  alignsweep  align across several banks, rows and patterns
  phase       the in-core phase monitor while a pattern streams back
  burst       RBURST edges per lane in fixed 2^n-PCLK windows, saturating at
              255, at every RCLKSEL, re-entering read mode for each
  gate        the stream's word-frame move per read interruption at every
              read delay and DQS gate offset (command 0x25)
  prewrite    write the sixteen rd_check rows: bank 0..7, row {row & ~1, 0/1}
  random      closed-page single READs to those rows (mode 4): rd_check's
              latency histogram and per-READ check; --sweep-gate repeats it
              at every read delay and gate offset
  train       per-lane read training by the proven controller's rule (TOOL-036):
              step the READ gate from earliest to latest, at each sweep RCLKSEL
              0..7 on every lane not yet locked, pass a lane when its RVALID-
              high cycles and RBURST pulses each equal the READs issued, and
              lock it at the second passing RCLKSEL in a row (frame 0x31); then
              check the trained settings with the lag classifier and report,
              per lane, how many READs back its delivered burst most often is;
              --log FILE then keeps a READ log at the trained settings (0x32 to
              0x34) and saves it as JSON; --sweep then steps each trained
              lane's gate +/-3 memory clocks at every RCLKSEL, and then gives
              it 1 to 7 CALIB pulses at its trained setting, reporting at each
              point its RVALID and RBURST per READ, own share and beat map
  logreport   offline, from a saved READ log: per lane, the share of READs
              that returned their own burst by location, by burst bit, by
              position in the READ sequence, by refresh phase and by the
              READ before, and which READ a wrong word belongs to
  lag         closed-page single READs with each lane's own READ gate delay,
              gate offset and RCLKSEL (commands 0x2C, 0x2D, 0x2E); at each
              check offset in --lats, which READ's pattern every lane held --
              its own, that of one of the LAGS READs before, or none (frame
              0x2F) -- and the fraction of PCLK each lane's RBURST was high as
              a level

The aligner trains per read session, so every align case re-enters read mode
and the tool reports the raw rotation it observes beside the locked one.  A
pattern must have eight distinct rotations to be trainable; 0x00, 0xff, 0xaa
and 0x55 are refused up front.

Every mode is left back in idle.  It touches nothing but the link; the board
must already be running the image.

Usage:
    tools/ddr3_write_probe.py status
    tools/ddr3_write_probe.py level [--start 0 --stop 255 --step 4]
    tools/ddr3_write_probe.py rw --wstep 32 [--pattern 0x1d]
    tools/ddr3_write_probe.py rwsweep [--start 0 --stop 255 --step 8]
"""

import argparse
from collections import Counter
import json
import sys
import time

import serial

MODES = ["idle", "level", "write", "read", "random"]

#: rd_check.v's sixteen patterns, by {row bit, bank}
RC_PATTERNS = [0x0B, 0x0D, 0x13, 0x15, 0x17, 0x19, 0x1B, 0x1D,
               0x25, 0x27, 0x2B, 0x2D, 0x35, 0x37, 0x3B, 0x57]
#: rd_check's own pipeline: hist[j] means the burst reached dq_q j - 4
#: PCLK after the cycle its READ left the core.  It was 3 until rd_check
#: registered the deserializer words and RVALID first, so offsets recorded
#: before then are one lower for the same arrival.
RC_PIPE = 4
#: earlier READs rd_check's lag classifier names; it was 3 until 2026-10-25
LAGS = 8
PAYLOAD = 127
TOTAL = 4 + PAYLOAD


class Core:
    def __init__(self, port: str):
        self.ser = serial.Serial(port, 115200, timeout=0.2, write_timeout=10)
        self.ser.reset_input_buffer()
        self.ser.write(b"\r\nfpgapipe\r\n")
        time.sleep(0.6)
        self.ser.reset_input_buffer()

    def close(self):
        self.ser.close()

    def request(self, cmd: int, arg: int = 1, expect: int = 5) -> bytes:
        buf = b""
        for _ in range(4):
            self.ser.reset_input_buffer()
            self.ser.write(bytes([0xAA, 0x00, cmd, arg & 0xFF]))
            self.ser.flush()
            buf = b""
            deadline = time.time() + 1.0
            while time.time() < deadline and len(buf) < expect:
                buf += self.ser.read(expect - len(buf))
            if buf[:2] == b"\xaa\x00" and len(buf) == expect:
                return buf
            time.sleep(0.1)
        raise RuntimeError(f"no reply to command {cmd:#04x}: {buf.hex(' ')}")

    def status(self) -> dict:
        b = self.request(0x03, expect=TOTAL)[4:]
        s = {"ready": b[0] >> 7 & 1, "pll": b[0] >> 6 & 1, "lock": b[0] >> 5 & 1,
             "cke": b[0] >> 3 & 1, "reset_n": b[0] >> 2 & 1, "step": b[1],
             "mode": MODES[(b[2] >> 6) | (b[2] >> 3 & 4)], "state": b[2] & 15, "pattern": b[3],
             "sys": int.from_bytes(b[4:6], "little"), "pclk": int.from_bytes(b[6:8], "little"),
             "eligible": int.from_bytes(b[8:10], "little"), "rclksel": b[10] & 7,
             "read_run": b[11], "lanes": []}
        for n in range(4):
            o = 12 + 6 * n
            s["lanes"].append({"rv": b[o] >> 3 & 1, "rb": b[o] >> 2 & 1, "rp": b[o + 1] >> 3 & 7,
                               "wp": b[o + 1] & 7,
                               "count": int.from_bytes(b[o + 2:o + 4], "little"),
                               "wstep": b[o + 4],
                               "moves": int.from_bytes(b[o + 5:o + 6], "little", signed=True),
                               "words": b[36 + 8 * n:44 + 8 * n]})
        s["pat_ok"] = b[68] >> 6 & 1
        s["trained"] = b[68] & 15
        s["aligned_good"] = int.from_bytes(b[69:71], "little")
        locked = b[71] | (b[72] << 8)
        s["rot"] = [(locked >> (3 * n)) & 7 for n in range(4)]
        s["drift"] = b[73] & 15
        s["err"] = b[74] & 15
        s["aligned_seen"] = int.from_bytes(b[75:77], "little")
        s["aligned_words"] = b[78:110]
        s["chg_total"] = int.from_bytes(b[110:112], "little")
        s["chg_gap"] = int.from_bytes(b[112:114], "little")
        s["delta_last"] = int.from_bytes(b[114:116], "little")
        s["phase_step"] = [b[116] & 7, b[116] >> 3 & 7, b[117] & 7, b[117] >> 3 & 7]
        s["skew_changed"] = b[116] >> 7 & 1
        s["phase"] = [(b[118] | (b[119] << 8)) >> (3 * n) & 7 for n in range(4)]
        s["phase_ok"] = b[119] >> 4 & 15
        s["relocks"] = int.from_bytes(b[120:122], "little")
        s["burst_seen"] = b[122] & 15
        s["burst_window_open"] = b[122] >> 7
        s["burst_count"] = [b[123 + n] for n in range(4)]
        return s

    def pos(self) -> dict:
        """rd_check's burst-position frame, command 0x2B: 34 payload bytes.

        For every isolated READ, which of the two known capture offsets held
        its burst (3 both, 1 only 11, 2 only 19, 0 neither), the refresh
        phase range seen per class, and the last eight classes.
        """
        r = self.request(0x2B, expect=4 + 34)
        if r[2] != 0x00 or r[3] != 34:
            raise RuntimeError(
                f"burst-position frame is {r[2]:#04x}/{r[3]}, expected 0x00/34")
        b = r[4:]
        names = ["both", "only11", "only19", "other"]
        s = {"counts": {n: int.from_bytes(b[4 * i:4 * i + 4], "little")
                        for i, n in enumerate(names)}}
        s["phase"] = {n: (int.from_bytes(b[16 + 4 * i:18 + 4 * i], "little"),
                          int.from_bytes(b[18 + 4 * i:20 + 4 * i], "little"))
                      for i, n in enumerate(names)}
        seq = int.from_bytes(b[32:34], "little")
        s["classes"] = [(seq >> (2 * i)) & 3 for i in range(8)]
        return s

    def lag(self) -> dict:
        """Lag, RBURST level and RVALID frame, command 0x2F: 206 payload bytes.

        lag[lane][k] counts READs whose lane held the pattern of the READ k
        before, k = 0 its own, up to LAGS; lag[lane][LAGS + 1] none of them.
        """
        n = 4 + 16 * (LAGS + 2) + 42
        r = self.request(0x2F, expect=4 + n)
        if r[2] != 0x06 or r[3] != n:
            raise RuntimeError(f"lag frame is {r[2]:#04x}/{r[3]}, expected 0x06/{n}")
        b = r[4:]
        u32 = lambda o: int.from_bytes(b[o:o + 4], "little")
        o = 4 + 16 * (LAGS + 2)                 # the fields after the lag counts
        delay = int.from_bytes(b[o + 20:o + 22], "little")
        sel = int.from_bytes(b[o + 23:o + 25], "little")
        return {"eval": u32(0),
                "lag": [[u32(4 + 4 * (LAGS + 2) * lane + 4 * k) for k in range(LAGS + 2)]
                        for lane in range(4)],
                "rb": [u32(o + 4 * lane) for lane in range(4)],
                "cycles": u32(o + 16),
                "delay": [(delay >> (3 * n)) & 7 for n in range(4)],
                "gate": [(b[o + 22] >> (2 * n)) & 3 for n in range(4)],
                "rclksel": [(sel >> (3 * n)) & 7 for n in range(4)],
                "rv": [u32(o + 25 + 4 * lane) for lane in range(4)],
                "rv_held": b[o + 41] & 1}

    def train_counts(self) -> dict:
        """Read-training counters, command 0x31: 40 payload bytes."""
        r = self.request(0x31, expect=4 + 40)
        if r[2] != 0x07 or r[3] != 40:
            raise RuntimeError(f"training frame is {r[2]:#04x}/{r[3]}, expected 0x07/40")
        b = r[4:]
        u32 = lambda o: int.from_bytes(b[o:o + 4], "little")
        return {"reads": u32(0), "cycles": u32(4),
                "rv": [u32(8 + 4 * lane) for lane in range(4)],
                "rb": [u32(24 + 4 * lane) for lane in range(4)]}

    def log_page(self, page: int) -> dict:
        """Copy READ-log page `page` (0x33) and read it (0x34): 148 payload bytes."""
        self.request(0x33, page)
        time.sleep(0.002)                       # the copy takes 18 PCLK
        r = self.request(0x34, expect=4 + 148)
        if r[2] != 0x08 or r[3] != 148:
            raise RuntimeError(f"log frame is {r[2]:#04x}/{r[3]}, expected 0x08/148")
        b = r[4:]
        if b[2] != page:
            raise RuntimeError(f"log page {b[2]} copied, {page} asked for")
        entries = []
        for e in range(16):
            v = int.from_bytes(b[4 + 9 * e:13 + 9 * e], "little")
            entries.append({
                "loc": (v >> 48) & 15, "burst": (v >> 52) & 127, "refi": (v >> 59) & 1023,
                "lanes": [{"pat": (v >> (9 * l)) & 255, "pins": (v >> (9 * l + 8)) & 1,
                           "rot": (v >> (36 + 3 * l)) & 7} for l in range(4)]})
        return {"n": int.from_bytes(b[0:2], "little"), "skip": b[3], "entries": entries}

    def read_log(self, pages: int = 64) -> list:
        """The logged entries in READ order, at most `pages` pages of 16."""
        first = self.log_page(0)
        out = first["entries"]
        for page in range(1, min((first["n"] + 15) // 16, pages)):
            out += self.log_page(page)["entries"]
        return out[:min(first["n"], 16 * pages)]

    def set_lanes(self, delays, gates, rclksels):
        """Each lane's READ gate delay, gate offset and RCLKSEL."""
        for lane in range(4):
            self.request(0x2C, lane << 6 | (delays[lane] & 7))
            self.request(0x2D, lane << 6 | (gates[lane] & 3))
            self.request(0x2E, lane << 6 | (rclksels[lane] & 7))

    def check(self) -> dict:
        """rd_check's frame, command 0x27."""
        r = self.request(0x27, expect=TOTAL)
        if r[2] != 0x05:
            raise RuntimeError(f"checker status came back as frame type {r[2]:#04x}")
        b = r[4:]
        u32 = lambda o: int.from_bytes(b[o:o + 4], "little")
        u16 = lambda o: int.from_bytes(b[o:o + 2], "little")
        rots = lambda v: [(v >> (3 * n)) & 7 for n in range(4)]
        fa = u16(26)
        return {"locked": b[0] >> 7, "random": b[0] >> 6 & 1, "gate": b[0] >> 4 & 3,
                "step": b[0] & 7, "lat": b[1] & 31,
                "total": u32(2), "good": u32(6), "class_ok": u32(10), "moves": u32(14),
                "hist_n": u16(18), "expect": rots(u16(20)), "last_rot": rots(u16(22)),
                "fail": b[24] >> 7, "fail_lanes": b[24] & 15, "fail_pat": b[25],
                "fail_bank": fa >> 7 & 7, "fail_rowbit": fa >> 10 & 1, "fail_burst": fa & 127,
                "last_cls": b[28] & 15,
                "hist": [u16(29 + 2 * j) for j in range(32)],
                "fail_words": [b[93 + 8 * n:101 + 8 * n] for n in range(4)],
                "fail_rot": rots(u16(125))}

    def set_slips(self, slips: list[int]):
        if len(slips) != 4 or any(not 0 <= slip <= 7 for slip in slips):
            raise ValueError("four lane slips in the range 0..7 are required")
        for lane, slip in enumerate(slips):
            self.request(0x2A, 0x80 | lane << 3 | slip)

    def mode(self, m: int):
        self.request(0x0C, m)
        deadline = time.time() + 2
        while self.status()["mode"] != MODES[m]:
            if time.time() > deadline:
                raise RuntimeError(f"the core did not reach mode {MODES[m]}")
            time.sleep(0.01)

    def settle(self) -> dict:
        # two full 65535-cycle windows at 100 MHz, then a snapshot
        time.sleep(0.005)
        self.request(0x04)
        time.sleep(0.002)
        return self.status()

    def snapshot(self) -> dict:
        self.request(0x04)
        time.sleep(0.002)
        return self.status()

    def address(self, bank: int, row: int):
        self.request(0x0F, bank)
        self.request(0x20, row)
        self.request(0x21, row >> 8)

    def move(self, lane: int, up: bool, count: int = 1):
        """RMOVE pulses on one lane with RDIR = up.  RDIR = 1 lowers the read
        tap (TOOL-041), so "up" here moves toward tap 0, the end of the range
        where further steps are lost and which this tool calls the top."""
        for _ in range(count):
            self.request(0x07, (1 << (4 + lane)) | int(up))

    def hold(self, mask: int, code: int = 1):
        """HOLD on the lanes in `mask` for 4 x (code + 1) PCLK, or with code 15
        until the next call; mask 0 releases every lane (command 0x35)."""
        self.request(0x35, ((code & 15) << 4) | (mask & 15))

    def calib(self, bit: int):
        self.request(0x08, bit)


def rotation(words: bytes, pattern: int) -> str:
    rots = [((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)]
    return str(rots.index(words[0])) if words[0] in rots else "-"


def header(s: dict) -> str:
    return (f"ready {s['ready']} pll {s['pll']} lock {s['lock']} cke {s['cke']} "
            f"reset_n {s['reset_n']} mode {s['mode']} state {s['state']} STEP {s['step']:#04x} "
            f"pattern {s['pattern']:#04x} RCLKSEL {s['rclksel']} "
            f"READ-group {s['read_run']}")


def hist_window(c: dict) -> tuple[int, int]:
    """The first offset and length of hist's full run, or (-1, 0)."""
    n = c["hist_n"]
    if n == 0:
        return -1, 0
    full = [h >= n * 0.98 for h in c["hist"]]
    return longest_run(full)


def lag_line(lat: int, g: dict) -> str:
    """One check offset of frame 0x2F: per lane, % of READs at each lag."""
    n = g["eval"] or 1
    lanes = "  ".join(
        f"L{lane} " + " ".join(f"{100.0 * c / n:5.1f}" for c in g["lag"][lane])
        for lane in range(4))
    rb = " ".join(f"{100.0 * c / (g['cycles'] or 1):5.1f}" for c in g["rb"])
    rv = " ".join(f"{100.0 * c / (g['cycles'] or 1):5.1f}" for c in g["rv"])
    lags = " ".join(str(k) for k in range(LAGS + 1))
    return (f"lat {lat:2d}: {g['eval']} READs, % at lag {lags} none: {lanes}"
            f"   RBURST level % {rb}   RVALID % {rv}")


def rot8(w: int, r: int) -> int:
    return ((w << r) | (w >> (8 - r))) & 255


def beat_map(ents: list, lane: int):
    """Which beats a lane's word carries, from a READ log.

    For each location, the raw word the lane held most often; then, at each
    framing rotation R, for each bit of that word, the beat of the expected
    word rot(P, R) -- or a constant -- that equals it at every location seen.
    Returns (% of READs holding their location's most frequent word, R, the
    source of bits 0..7 as strings), R and sources None when no single map
    explains every location.  A lane that captures whole bursts maps every
    bit b to beat b.
    """
    raw, det = {}, 0
    for loc in range(16):
        c = Counter(rot8(e["lanes"][lane]["pat"], e["lanes"][lane]["rot"])
                    for e in ents if e["loc"] == loc)
        if c:
            raw[loc], cnt = c.most_common(1)[0]
            det += cnt
    fits = []
    for R in range(8):
        srcs = []
        for bit in range(8):
            hb = [(raw[l] >> bit) & 1 for l in sorted(raw)]
            beats = [b for b in range(8)
                     if hb == [(rot8(RC_PATTERNS[l], R) >> b) & 1 for l in sorted(raw)]]
            if beats:
                srcs.append(str(bit) if bit in beats else str(beats[0]))
            elif len(set(hb)) == 1:
                srcs.append(f"c{hb[0]}")
            else:
                srcs.append("?")
        if "?" not in srcs:
            fits.append((sum(srcs[b] == str(b) for b in range(8)), R, srcs))
    fits.sort(reverse=True)
    pct = 100.0 * det / max(len(ents), 1)
    return (pct, fits[0][1], fits[0][2]) if fits else (pct, None, None)


def slip_point(core: "Core", args, sets: list) -> tuple:
    """Random mode at `sets`; the training counters and 256 logged READs."""
    core.set_lanes([x[0] for x in sets], [x[1] for x in sets], [x[2] for x in sets])
    core.request(0x26, args.log_lat)
    core.request(0x32, args.log_skip)
    core.mode(4)
    reads = (args.log_skip + 1) * 1024
    time.sleep(max(0.05, 2 * reads * (max(args.gap, 8) + 5) * 10e-9 * 1.1))
    core.mode(0)
    return core.train_counts(), core.read_log(pages=16)


def slip_line(lane: int, c: dict, ents: list) -> str:
    n = c["reads"] or 1
    own = sum(e["lanes"][lane]["pins"] and e["lanes"][lane]["pat"] == RC_PATTERNS[e["loc"]]
              for e in ents)
    det, R, srcs = beat_map(ents, lane)
    whole = srcs is not None and all(srcs[b] == str(b) for b in range(8))
    m = f"R={R} bits 7..0 from " + " ".join(reversed(srcs)) if srcs else "no single map"
    return (f"rv {c['rv'][lane] / n:5.2f} rb {c['rb'][lane] / n:5.2f}  own "
            f"{100.0 * own / max(len(ents), 1):5.1f}%  det {det:5.1f}%  {m}"
            f"{'  WHOLE' if whole else ''}")


def lane_pass(c: dict, ents: list, lane: int, tol: int) -> tuple:
    """(vendor's state, whole bursts) for one lane from counters and a READ log."""
    n = c["reads"]
    state = n > 100 and abs(c["rv"][lane] - n) <= tol and abs(c["rb"][lane] - n) <= tol
    if not state or not ents:
        return state, False
    own = sum(e["lanes"][lane]["pins"] and e["lanes"][lane]["pat"] == RC_PATTERNS[e["loc"]]
              for e in ents) / len(ents)
    _, _, srcs = beat_map(ents, lane)
    return state, srcs is not None and all(srcs[b] == str(b) for b in range(8)) and own >= 0.99


def vendor_search(core: "Core", args) -> tuple:
    """The proven controller's read training (TOOL-036, TOOL-039).

    For each gate position from earliest, nine RCLKSEL sweeps 0..7; after
    every sweep that leaves a lane unlocked, one CALIB pulse on that lane's
    eight DQ.  A lane passes a setting with one RVALID cycle and one RBURST
    pulse per READ and, in this host version, with whole bursts in its READ
    log where the vendor compares a fixed read-back word; it locks at the
    second passing RCLKSEL in a row of one sweep.
    """
    core.request(0x26, args.log_lat)
    core.request(0x32, args.log_skip)
    locked = [None] * 4
    tried = 0
    for pos in range(args.max_pos + 1):
        d, k = divmod(pos, 4)
        for cal in range(9):
            prev = [False] * 4
            for rs in range(8):
                sets = [locked[n] or (d, k, rs) for n in range(4)]
                # the vendor changes an unconfigured lane's settings inside a
                # HOLD on it, between every two trials but before the first
                held = getattr(args, "hold", "none") == "vendor" and tried > 0
                if held:
                    core.hold(sum(1 << l for l in range(4) if locked[l] is None), 15)
                core.set_lanes([x[0] for x in sets], [x[1] for x in sets], [x[2] for x in sets])
                if held:
                    core.hold(0)
                core.mode(4)                    # arms the counters and the log
                time.sleep(args.seconds)
                core.mode(0)
                c = core.train_counts()
                tried += 1
                states = [lane_pass(c, [], l, args.tol)[0] for l in range(4)]
                ents = (core.read_log(pages=16)
                        if any(states[l] and locked[l] is None for l in range(4)) else [])
                for l in range(4):
                    if locked[l] is not None:
                        continue
                    state, whole = lane_pass(c, ents, l, args.tol)
                    if args.verbose and state:
                        print(f"gate {pos:2d} CALIB {cal} rclksel {rs}: lane {l} in the vendor's "
                              f"state, {'whole' if whole else 'not whole'}: " + slip_line(l, c, ents))
                    if whole and prev[l]:
                        locked[l] = (d, k, rs)
                        print(f"lane {l} locked at gate {pos} (delay {d} k {k}) rclksel {rs} "
                              f"after {cal} CALIB pulse(s) at this gate", flush=True)
                    prev[l] = whole
            if all(locked):
                return locked, tried
            for l in range(4):
                if locked[l] is None:
                    for pin in range(8):
                        core.request(0x08, 8 * l + pin)
    return locked, tried


def center_delay(core: "Core", args, sets: list, locked: list, reach: int = 64):
    """Centre each trained lane's read delay in its window of whole bursts.

    From the trained point the delay is stepped down one RMOVE at a time to
    the first setting that fails -- not the vendor's state, or not whole --
    and back, then up the same way to at most `reach` steps.  The upward run
    may end against the top of the delay's range, where RMOVE stops moving it
    (on the board an unanchored return of 64 steps has landed below the lower
    edge), so the lane is then stepped down again from wherever it is to the
    lower edge, which is a physical place, and set relative to it, at the
    middle of its window.  When no upper edge was found the window's top is
    the highest setting the delay reached: on the board the calibration has
    left lanes at the top of the delay's range, where up steps do not move it
    at all.  The down steps to the lower edge, against those commanded,
    measure that saturation.  The lane is checked where it is left.
    """
    core.request(0x26, args.log_lat)
    core.request(0x32, args.log_skip)

    def ok(lane):
        c, ents = slip_point(core, args, sets)
        return lane_pass(c, ents, lane, args.tol) == (True, True)

    def down_to_edge(lane, limit):
        steps = 0
        while steps < limit:
            core.move(lane, False)
            steps += 1
            if not ok(lane):
                return steps                # now one below the lowest whole setting
        return None

    for lane in range(4):
        if not locked[lane]:
            continue
        if not ok(lane):
            print(f"lane {lane}: not whole at its trained delay; not centred")
            continue
        d1 = down_to_edge(lane, reach)
        if d1 is None:
            print(f"lane {lane}: whole for {reach} steps down; left {reach} below its trained delay "
                  "and not centred")
            continue
        core.move(lane, True, d1)           # back to the trained point, the path just walked
        up = 0
        while up < reach:
            core.move(lane, True)
            if not ok(lane):
                break
            up += 1
        commanded = up + (1 if up < reach else 0)
        d2 = down_to_edge(lane, commanded + d1 + 8)
        if d2 is None:
            print(f"lane {lane}: lower edge not found again; left where it is")
            continue
        lost = commanded + d1 - d2          # up steps that did not move the delay
        above = up if up < reach else up - lost       # whole settings reached above the trained one
        width = d1 + above                  # whole settings from the lower edge to the top
        target = (width + 1) // 2           # up from the first failing setting
        core.move(lane, True, target)
        good = ok(lane)
        top = "upper edge" if up < reach else ("top of the delay's range" if lost else f"reach {reach}")
        print(f"lane {lane}: whole {d1 - 1} below its trained delay and {above} above, to the {top}; "
              f"{lost} up step(s) did not move the delay; centred {target - d1:+d}, "
              f"{'whole' if good else 'NOT whole'} there", flush=True)


def calib_fix(core: "Core", args, sets: list, locked: list, max_pulses: int = 16):
    """CALIB each trained lane until its log shows whole bursts in the vendor's state.

    The gate and RCLKSEL are left where training put them; a trained lane gets
    one CALIB pulse on all eight of its DQ at a time, and after each its READ
    log is fitted: the lane is done when its beat map is the identity, at
    least 99% of its logged READs hold their own pattern, and it has one
    RVALID cycle and one RBURST pulse per READ.  A majority-word identity map
    alone is not enough: a lane whose framing is right but whose eye corrupts
    a fifth of its words still fits it.
    """
    for lane in range(4):
        if not locked[lane]:
            continue
        for pulses in range(max_pulses + 1):
            c, ents = slip_point(core, args, sets)
            n = c["reads"] or 1
            _, _, srcs = beat_map(ents, lane)
            own = sum(e["lanes"][lane]["pins"] and e["lanes"][lane]["pat"] == RC_PATTERNS[e["loc"]]
                      for e in ents) / max(len(ents), 1)
            whole = srcs is not None and all(srcs[b] == str(b) for b in range(8)) and own >= 0.99
            state = abs(c["rv"][lane] - n) <= args.tol and abs(c["rb"][lane] - n) <= args.tol
            print(f"calib-fix lane {lane} + {pulses} CALIB: " + slip_line(lane, c, ents), flush=True)
            if whole and state:
                print(f"lane {lane}: whole bursts in the vendor's state after {pulses} CALIB pulse(s)")
                break
            for pin in range(8):
                core.request(0x08, 8 * lane + pin)
        else:
            print(f"lane {lane}: no whole bursts in the vendor's state within {max_pulses} CALIB pulses")


def slip_sweep(core: "Core", args, sets: list, locked: list):
    """Around each trained lane: gate +/-3 memory clocks x RCLKSEL, then CALIB."""
    for lane in range(4):
        if not locked[lane]:
            continue
        d0, k0, r0 = locked[lane]
        pos0 = 4 * d0 + k0
        print(f"sweep lane {lane} around gate {pos0} (delay {d0} k {k0}) rclksel {r0}")
        for pos in range(max(pos0 - 3, 0), min(pos0 + 3, args.max_pos) + 1):
            for rs in range(8):
                pt = list(sets)
                pt[lane] = (pos // 4, pos % 4, rs)
                c, ents = slip_point(core, args, pt)
                print(f"  gate {pos:2d} rclksel {rs}: " + slip_line(lane, c, ents), flush=True)
        for pulses in range(1, 8):
            for pin in range(8):
                core.request(0x08, 8 * lane + pin)
            c, ents = slip_point(core, args, sets)
            print(f"  trained + {pulses} CALIB: " + slip_line(lane, c, ents), flush=True)
        print(f"  lane {lane}'s word framing is left moved by 7 CALIB pulses; "
              "calibrate again before relying on it")


def log_report(log: dict):
    """Condition each lane's own-READ result in a saved READ log."""
    ents = log["entries"]
    n = len(ents)
    own = [[e["lanes"][l]["pins"] and e["lanes"][l]["pat"] == RC_PATTERNS[e["loc"]]
            for e in ents] for l in range(4)]
    print(f"{n} READs from READ {1024 * log['skip']} at offset {log['lat']}, "
          f"settings (delay, k, rclksel) {log['settings']}, trained {log['locked']}")
    print("own % per lane: " + " ".join(f"{100.0 * sum(o) / max(n, 1):5.1f}" for o in own))

    def share(lane, pick):
        sel = [own[lane][i] for i in range(n) if pick(i)]
        return (100.0 * sum(sel) / len(sel), len(sel)) if sel else (float("nan"), 0)

    def table(title, keys, pick):
        print(title)
        print("        " + " ".join(f"{str(k):>5s}" for k in keys))
        for lane in range(4):
            print(f"  L{lane}   " + " ".join(f"{share(lane, lambda i: pick(i, k))[0]:5.1f}" for k in keys))
        print("  READs " + " ".join(f"{share(0, lambda i: pick(i, k))[1]:5d}" for k in keys))

    table("own % by location {row bit, bank}:", list(range(16)), lambda i, k: ents[i]["loc"] == k)
    table("own % by burst bit set:", list(range(7)), lambda i, k: (ents[i]["burst"] >> k) & 1)
    table("own % by burst bit clear:", list(range(7)), lambda i, k: not (ents[i]["burst"] >> k) & 1)
    blk = max(n // 8, 1)
    table(f"own % by position in the log, eighths of {n} READs:", list(range(8)),
          lambda i, k: min(i // blk, 7) == k)
    table("own % by refresh phase at the check, PCLK in 128s:", list(range(6)),
          lambda i, k: min(ents[i]["refi"] // 128, 5) == k)
    table("own % by the READ before: same bank, same location, other bank:",
          ["sbank", "sloc", "obank"],
          lambda i, k: i > 0 and {"sbank": (ents[i]["loc"] & 7) == (ents[i - 1]["loc"] & 7),
                                  "sloc": ents[i]["loc"] == ents[i - 1]["loc"],
                                  "obank": (ents[i]["loc"] & 7) != (ents[i - 1]["loc"] & 7)}[k])
    table("own % by the READ before's location:", list(range(16)),
          lambda i, k: i > 0 and ents[i - 1]["loc"] == k)
    print("wrong words: per lane, not a pattern / pins disagree / a pattern whose most recent READ "
          "was k back (k: count, top six) / a pattern not read in the last 64; the first 64 "
          "entries, whose earlier READs were not logged, are left out of the last two")
    for lane in range(4):
        bad_pat = bad_pins = far = 0
        back = Counter()
        for i in range(n):
            if own[lane][i]:
                continue
            ln = ents[i]["lanes"][lane]
            if not ln["pins"]:
                bad_pins += 1
                continue
            if ln["pat"] not in RC_PATTERNS:
                bad_pat += 1
                continue
            if i < 64:
                continue
            loc = RC_PATTERNS.index(ln["pat"])
            k = next((k for k in range(1, 65) if ents[i - k]["loc"] == loc), None)
            if k is None:
                far += 1
            else:
                back[k] += 1
        print(f"  L{lane}: {bad_pat} / {bad_pins} / "
              + " ".join(f"{k}:{c}" for k, c in back.most_common(6)) + f" / {far}")
    print("beat map: per lane, the share of READs holding their location's most frequent word, "
          "and each held bit's source beat at the framing rotation that explains every location")
    for lane in range(4):
        det, R, srcs = beat_map(ents, lane)
        line = f"R={R} bits 7..0 from " + " ".join(reversed(srcs)) if srcs else "no single map"
        print(f"  L{lane}: {det:5.1f}% deterministic; {line}")
    pairs = [Counter() for _ in range(4)]
    for i in range(n):
        for lane in range(4):
            ln = ents[i]["lanes"][lane]
            if not own[lane][i] and ln["pins"] and ln["pat"] in RC_PATTERNS:
                pairs[lane][(ents[i]["loc"], RC_PATTERNS.index(ln["pat"]))] += 1
    print("wrong words by (READ's location -> location of the pattern held), top eight per lane")
    for lane in range(4):
        print(f"  L{lane}: " + " ".join(f"{a}->{b}:{c}" for (a, b), c in pairs[lane].most_common(8)))


def check_line(c: dict) -> str:
    start, width = hist_window(c)
    lat = f"latency {start - RC_PIPE} PCLK (hist {start}..{start + width - 1})" \
        if width else "no full hist offset"
    return (f"{lat}; checked at {c['lat']}: {c['good']}/{c['total']} good, "
            f"{c['class_ok']} right burst, {c['moves']} rotation moves, "
            f"locked {c['locked']} rot {c['last_rot']}")


def fail_lines(c: dict) -> list[str]:
    if not c["fail"]:
        return []
    out = [f"first failure: lanes {c['fail_lanes']:04b}, expected {c['fail_pat']:#04x} "
           f"at bank {c['fail_bank']} row bit {c['fail_rowbit']} burst {c['fail_burst']}, "
           f"rotation {c['fail_rot']} against expected {c['expect']}"]
    for n in range(4):
        out.append(f"    lane {n}: " + c["fail_words"][n].hex(" "))
    return out


def prewrite(core: Core, row: int, write_s: float):
    """Write each of the sixteen rd_check rows with its pattern."""
    for idx, pattern in enumerate(RC_PATTERNS):
        write_address(core, idx & 7, (row & ~1) | (idx >> 3), pattern, write_s)
    core.address(0, row & ~1)


def random_session(core: Core, seconds: float) -> dict:
    core.mode(0)
    core.mode(4)                        # entering random mode arms rd_check
    time.sleep(seconds)
    core.mode(0)
    return core.check()


def set_wstep(core: Core, values):
    for n, v in enumerate(values):
        core.request(0x10 + n, v)


def read_back(core: Core, write_s: float) -> dict:
    core.mode(2)
    time.sleep(write_s)
    core.mode(0)
    core.mode(3)
    s = core.settle()
    core.mode(0)
    return s


def write_address(core: Core, bank: int, row: int, pattern: int, write_s: float):
    core.mode(0)
    core.address(bank, row)
    core.request(0x0E, pattern)
    core.mode(2)
    time.sleep(write_s)
    core.mode(0)


def rotations(pattern: int) -> list[int]:
    return [((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)]


def trainable(pattern: int) -> bool:
    return len(set(rotations(pattern))) == 8


def burst_bytes(pattern: int) -> bytes:
    """The 32 bytes an aligned read burst must carry, beat 0 first."""
    return bytes(0x55 if (pattern >> bit) & 1 else 0xAA
                 for bit in range(8) for _ in range(4))


def aligned_from_raw(s: dict) -> bytes:
    """Derotate the raw snapshot with the reported locks and transpose it."""
    out = bytearray(32)
    for beat in range(8):
        for lane in range(4):
            # the pins as captured: even pins carry the pattern, odd pins its
            # inverse, so each word is derotated on its own
            word = [((w >> s["rot"][lane]) | (w << (8 - s["rot"][lane]))) & 0xFF
                    for w in s["lanes"][lane]["words"]]
            value = 0
            for pin in range(8):
                value |= ((word[pin] >> beat) & 1) << pin
            out[4 * beat + lane] = value
    return bytes(out)


def check_aligned(s: dict, pattern: int, ratio: float = 0.75) -> list[str]:
    """Every independent check of one aligned read window."""
    bad = []
    if not trainable(pattern):
        return [f"pattern {pattern:#04x} has fewer than eight distinct rotations"]
    if not s["pat_ok"]:
        bad.append("the core does not consider the pattern identifiable")
    if s["trained"] != 0b1111:
        bad.append(f"trained mask {s['trained']:04b}, not 1111")
    if s["err"]:
        bad.append(f"a lane's aligned byte did not match: err {s['err']:04b}")
    if s["drift"]:
        bad.append(f"a lane's rotation left its lock: drift {s['drift']:04b}")
    if s["aligned_seen"] == 0:
        bad.append("no aligned burst was presented")
    elif s["aligned_good"] < int(s["aligned_seen"] * ratio):
        bad.append(f"{s['aligned_good']} of {s['aligned_seen']} aligned bursts matched")
    want = burst_bytes(pattern)
    if s["aligned_words"] != want:
        for i, (got, exp) in enumerate(zip(s["aligned_words"], want)):
            if got != exp:
                bad.append(f"beat {i // 4} lane {i % 4} is {got:#04x}, expected {exp:#04x}")
                break
    recomputed = aligned_from_raw(s)
    if recomputed != s["aligned_words"]:
        for i, (got, exp) in enumerate(zip(s["aligned_words"], recomputed)):
            if got != exp:
                bad.append(f"beat {i // 4} lane {i % 4}: snapshot {got:#04x} but the "
                           f"raw words derotated by the reported locks give {exp:#04x}")
                break
    return bad


def settled_status(core: "Core", pattern: int, tries: int = 40) -> dict:
    """A status whose snapshot was taken in a settled window.

    The raw snapshot and the aligned snapshot are single-cycle samples, so
    one taken while the frame is moving shows the new phase against the old
    lock.  That is the slack between a slip and the relock, not bad data --
    the per-window counters judge the presented bursts.  Re-read until the
    sample agrees with the locks before using it for a byte comparison.
    """
    s = core.settle()
    for _ in range(tries):
        raw = [rotation(s["lanes"][n]["words"], pattern) for n in range(4)]
        # a sample taken while a slip is being followed pairs an old word with
        # the previous lock; require the reported burst to agree with an
        # independent derotation of the same sample before believing it
        if raw == [str(r) for r in s["rot"]] and \
                aligned_from_raw(s) == s["aligned_words"]:
            return s
        time.sleep(0.001)
        s = core.snapshot()
    return s


def aligned_line(s: dict, pattern: int) -> str:
    raw = [rotation(s["lanes"][n]["words"], pattern) for n in range(4)]
    return (f"trained {s['trained']:04b} rot {s['rot']} snapshot-rot {raw} "
            f"aligned {s['aligned_good']}/{s['aligned_seen']} err {s['err']:04b} "
            f"relocks {s['relocks']} "
            f"drift {s['drift']:04b}")


def normalized_words(lane: dict) -> list[int]:
    return [v if k % 2 == 0 else v ^ 0xFF for k, v in enumerate(lane["words"])]


def passing(s: dict, lane: int, ratio: float = 0.75) -> bool:
    return s["eligible"] > 0 and s["lanes"][lane]["count"] >= int(s["eligible"] * ratio)


def longest_run(values: list[bool]) -> tuple[int, int]:
    best_start = best_len = run_start = run_len = 0
    for i, value in enumerate(values):
        if value:
            if run_len == 0:
                run_start = i
            run_len += 1
            if run_len > best_len:
                best_start, best_len = run_start, run_len
        else:
            run_len = 0
    return best_start, best_len


def align_framing(core: Core, pattern: int, max_pulses: int = 16) -> list[int]:
    """Use CALIB to align each lane's bits to its current majority framing."""
    s = core.snapshot()
    chosen = []
    for lane in range(4):
        words = normalized_words(s["lanes"][lane])
        rotations = {((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)}
        candidates = [w for w in words if w in rotations]
        if not candidates:
            raise RuntimeError(f"lane {lane} has no word that is a rotation of {pattern:#04x}: {words}")
        target = Counter(candidates).most_common(1)[0][0]
        chosen.append(target)
        for k in range(8):
            bit = 8 * lane + k
            for pulse in range(max_pulses + 1):
                current = normalized_words(s["lanes"][lane])[k]
                if current == target:
                    break
                if pulse == max_pulses:
                    raise RuntimeError(
                        f"DQ{bit} did not reach lane {lane} target {target:#04x}; last {current:#04x}")
                core.calib(bit)
                time.sleep(0.0001)
                s = core.snapshot()
        print(f"lane {lane}: framing target {target:#04x}, words " +
              " ".join(f"{w:02x}" for w in normalized_words(s["lanes"][lane])))
    return chosen


def other_pattern(pattern: int) -> int:
    rotations = {((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)}
    for candidate in (0x6B, 0xC5, 0x1D, 0x96, 0x3C):
        candidate_rotations = {
            ((candidate << r) | (candidate >> (8 - r))) & 0xFF for r in range(8)
        }
        if rotations.isdisjoint(candidate_rotations):
            return candidate
    raise RuntimeError("could not choose a disjoint liveness pattern")


def sweep_and_center(core: Core, pattern: int, write_s: float,
                     ratio: float = 0.75) -> list:
    """Sweep signed delay positions with alternating data to reject stale words.

    A lane whose passing run reaches the sweep's last position has met the top
    of the delay's range, where RMOVE stops moving it (TOOL-040): the commanded
    middle of that run would sit at the top, at the edge of the eye.  Such a
    lane is walked down from the top, a step at a time, to its lower edge and
    placed in the middle of what it can reach, and is kept as an offset below
    the top, which RLOADN does not change: placed again by driving it up to the
    top and back down.
    """
    def stream_pass(index, lane):
        test_pattern = pattern if index % 2 == 0 else alternate
        write_address(core, 0, 0, test_pattern, write_s)
        core.mode(3)
        s = core.settle()
        core.mode(0)
        return passing(s, lane, ratio)

    def place(lane, where):
        kind, n = where
        if kind == "below top":
            core.move(lane, True, 255)
            core.move(lane, False, n)
        else:
            core.move(lane, n >= 0, abs(n))

    core.mode(0)
    alternate = other_pattern(pattern)
    centers = []
    for lane in range(4):
        core.request(0x0A)
        for previous, where in enumerate(centers):
            place(previous, where)
        core.move(lane, False, 128)
        results = []
        for index in range(256):
            results.append(stream_pass(index, lane))
            if index != 255:
                core.move(lane, True)
        start, width = longest_run(results)
        if width == 0:
            raise RuntimeError(f"lane {lane} has no passing read-delay position")
        fails = 256 - sum(results)
        if results[-1]:
            # at the top now: walk down to the lower edge
            core.move(lane, True, 255)
            down = 0
            while down < 255:
                core.move(lane, False)
                if not stream_pass(down + 1, lane):
                    break
                down += 1
            below = (down + 1) // 2
            centers.append(("below top", below))
            print(f"lane {lane}: passes to the top of the delay's range, {down} step(s) down to "
                  f"its lower edge; placed {below} below the top, failed positions {fails}")
        else:
            center = -128 + start + width // 2
            centers.append(("from default", center))
            print(f"lane {lane}: pass window start {start - 128:+d}, width {width}, "
                  f"center {center:+d}, failed positions {fails}")
    core.request(0x0A)
    for lane, where in enumerate(centers):
        place(lane, where)
    return centers


def verify_sessions(core: Core, pattern: int, sessions: int, ratio: float = 0.75):
    rotations = [((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)]
    for session in range(sessions):
        core.mode(0)
        core.mode(3)
        s = core.settle()
        align_framing(core, pattern)
        s = core.settle()
        got = [normalized_words(lane) for lane in s["lanes"]]
        lane_rotations = []
        for lane in range(4):
            if not passing(s, lane, ratio):
                raise RuntimeError(f"session {session}: lane {lane} failed data check")
            if len(set(got[lane])) != 1 or got[lane][0] not in rotations:
                raise RuntimeError(
                    f"session {session}: lane {lane} bits are not aligned: " +
                    " ".join(f"{word:02x}" for word in got[lane]))
            lane_rotations.append(rotations.index(got[lane][0]))
        print(f"session {session + 1}: per-bit aligned, rotations {lane_rotations}, "
              f"eligible {s['eligible']}, " +
              "  ".join(f"L{lane} {s['lanes'][lane]['count']}" for lane in range(4)))
    core.mode(0)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    lv = sub.add_parser("level")
    lv.add_argument("--start", type=int, default=0)
    lv.add_argument("--stop", type=int, default=255)
    lv.add_argument("--step", type=int, default=4)
    rw = sub.add_parser("rw")
    rw.add_argument("--wstep", type=int, nargs="+", default=[0])
    rw.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    rw.add_argument("--write-ms", type=float, default=20)
    rw.add_argument("--read-run", type=int, default=32)
    rw.add_argument("--read-gap", type=int, default=8)
    rw.add_argument("--read-delay", type=int, default=3)
    sw = sub.add_parser("rwsweep")
    sw.add_argument("--start", type=int, default=0)
    sw.add_argument("--stop", type=int, default=255)
    sw.add_argument("--step", type=int, default=8)
    sw.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    sw.add_argument("--write-ms", type=float, default=20)
    sw.add_argument("--read-run", type=int, default=32)
    sw.add_argument("--read-gap", type=int, default=8)
    sw.add_argument("--read-delay", type=int, default=3)
    ca = sub.add_parser("calibrate")
    ca.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    ca.add_argument("--wstep", type=int, nargs="+", default=[0])
    ca.add_argument("--read-run", type=int, default=32)
    ca.add_argument("--read-gap", type=int, default=8)
    ca.add_argument("--read-delay", type=int, default=3)
    ca.add_argument("--write-ms", type=float, default=20)
    ca.add_argument("--sessions", type=int, default=5)
    ca.add_argument("--pass-ratio", type=float, default=0.75)
    al = sub.add_parser("align")
    al.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    al.add_argument("--wstep", type=int, nargs="+", default=[0])
    al.add_argument("--bank", type=int, default=0)
    al.add_argument("--row", type=lambda x: int(x, 0), default=0)
    al.add_argument("--write-ms", type=float, default=20)
    al.add_argument("--read-run", type=int, default=32)
    al.add_argument("--read-gap", type=int, default=8)
    al.add_argument("--read-delay", type=int, default=3)
    al.add_argument("--sessions", type=int, default=5)
    al.add_argument("--pass-ratio", type=float, default=0.75)
    asw = sub.add_parser("alignsweep")
    asw.add_argument("--banks", type=lambda x: int(x, 0), nargs="+", default=list(range(8)))
    asw.add_argument("--rows", type=lambda x: int(x, 0), nargs="+",
                     default=[0, 1, 2, 0x155, 0x2AAA, 0x7FFF])
    asw.add_argument("--patterns", type=lambda x: int(x, 0), nargs="+",
                     default=[0x1D, 0x6B, 0xC5, 0x96, 0x3C])
    asw.add_argument("--wstep", type=int, nargs="+", default=[0])
    asw.add_argument("--write-ms", type=float, default=5)
    asw.add_argument("--read-run", type=int, default=32)
    asw.add_argument("--read-gap", type=int, default=8)
    asw.add_argument("--read-delay", type=int, default=3)
    asw.add_argument("--pass-ratio", type=float, default=0.75)
    ph = sub.add_parser("phase")
    ph.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    ph.add_argument("--wstep", type=int, nargs="+", default=[0])
    ph.add_argument("--read-run", type=int, default=255)
    ph.add_argument("--read-gap", type=int, default=255)
    ph.add_argument("--read-delay", type=int, default=3)
    ph.add_argument("--write-ms", type=float, default=20)
    ph.add_argument("--samples", type=int, default=8)
    ph.add_argument("--interval-ms", type=float, default=20.0)
    bu = sub.add_parser("burst")
    bu.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    bu.add_argument("--read-run", type=int, default=255)
    bu.add_argument("--read-gap", type=int, default=255)
    bu.add_argument("--read-delay", type=int, default=3)
    bu.add_argument("--windows", type=int, nargs="+", default=[6, 8, 12, 16],
                    help="window exponents n: 2^n PCLK each")
    ga = sub.add_parser("gate")
    ga.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    ga.add_argument("--read-run", type=int, default=32)
    ga.add_argument("--read-gap", type=int, default=8)
    ga.add_argument("--read-delay", type=int, default=3)
    ga.add_argument("--delays", type=int, nargs="+", default=list(range(8)))
    ga.add_argument("--offsets", type=int, nargs="+", default=[0, 1, 2, 3])
    ga.add_argument("--write-ms", type=float, default=20)
    ga.add_argument("--settle-ms", type=float, default=20)
    ps = sub.add_parser("pos", help="which capture offset held each isolated READ (0x2B)")
    ps.add_argument("--row", type=lambda x: int(x, 0), default=0)
    ps.add_argument("--prewrite", action="store_true")
    ps.add_argument("--seconds", type=float, default=0.3)
    ps.add_argument("--read-delay", type=int, default=1)
    ps.add_argument("--gate", type=int, default=2)
    ps.add_argument("--slips", type=int, nargs=4, default=[0, 0, 0, 4])
    lg = sub.add_parser("lag", help="which READ's pattern each lane held, per lane gate (0x2F)")
    lg.add_argument("--row", type=lambda x: int(x, 0), default=0)
    lg.add_argument("--prewrite", action="store_true")
    lg.add_argument("--seconds", type=float, default=0.2)
    lg.add_argument("--lats", type=int, nargs="+", default=[12, 20],
                    help="check offsets, in rd_check's hist units")
    lg.add_argument("--delay", type=int, nargs=4, default=[1, 1, 1, 1],
                    help="READ gate delay per lane, PCLK")
    lg.add_argument("--gate", type=int, nargs=4, default=[2, 2, 2, 2],
                    help="READ gate offset per lane, memory clocks")
    lg.add_argument("--rclksel", type=int, nargs=4, default=[0, 0, 0, 0])
    lg.add_argument("--gap", type=int, default=8, help="PCLK between READs, at least 8")
    lg.add_argument("--rvalid", action="store_true",
                    help="check each lane's word held from its last RVALID cycle (0x29)")
    lg.add_argument("--slips", type=int, nargs=4, default=[0, 0, 0, 4])
    tr = sub.add_parser("train", help="per-lane read training by the vendor's rule (0x31)")
    tr.add_argument("--row", type=lambda x: int(x, 0), default=0)
    tr.add_argument("--prewrite", action="store_true")
    tr.add_argument("--gap", type=int, default=40, help="PCLK between READs, at least 8")
    tr.add_argument("--seconds", type=float, default=0.03, help="random mode per setting")
    tr.add_argument("--tol", type=int, default=2,
                    help="counts may differ from the READs by this much (window edges)")
    tr.add_argument("--max-pos", type=int, default=31,
                    help="last gate position, 4 x delay + offset")
    tr.add_argument("--lats", type=int, nargs="+", default=list(range(14, 26)),
                    help="check offsets for the lag check of the trained settings")
    tr.add_argument("--lag-seconds", type=float, default=0.15,
                    help="random mode per check offset of the lag check; about 6%% of"
                         " READs are classified")
    tr.add_argument("--verbose", action="store_true", help="one line per setting tried")
    tr.add_argument("--log", metavar="FILE",
                    help="then keep a READ log at the trained settings and save it as JSON")
    tr.add_argument("--log-lat", type=int, default=20, help="the log's check offset")
    tr.add_argument("--log-skip", type=int, default=1,
                    help="READs passed over before the log, in 1024s")
    tr.add_argument("--vendor-delay", action="store_true",
                    help="before training, set every lane's read delay as the proven controller's "
                         "u_init_rmove_mod does: RLOADN loads the DLL STEP code, then STEP - 4 RMOVE "
                         "pulses with RDIR = 1 leave the tap at 4 (TOOL-041)")
    tr.add_argument("--hold", choices=["none", "vendor"], default="none",
                    help="with --vendor-search, hold every lane not yet locked while its gate and "
                         "RCLKSEL change between trials, as the proven controller does (TOOL-042, "
                         "command 0x35)")
    tr.add_argument("--vendor-search", action="store_true",
                    help="train as the proven controller does (TOOL-039): gate outer, CALIB 0..8, "
                         "RCLKSEL inner, a lane passing only with one RVALID and one RBURST per READ "
                         "and whole bursts in its READ log")
    tr.add_argument("--center", action="store_true",
                    help="after training, centre each trained lane's read delay in its window of "
                         "whole bursts in the vendor's state")
    tr.add_argument("--calib-fix", action="store_true",
                    help="after training, CALIB each trained lane, one pulse at a time, until its "
                         "READ log shows whole bursts in the vendor's state; then the lag check")
    tr.add_argument("--sweep", action="store_true",
                    help="then sweep each trained lane's gate, RCLKSEL and CALIB, logging each point")
    lr = sub.add_parser("logreport", help="offline: condition a saved READ log's results")
    lr.add_argument("file")
    pw = sub.add_parser("prewrite")
    pw.add_argument("--row", type=lambda x: int(x, 0), default=0)
    pw.add_argument("--write-ms", type=float, default=5)
    rn = sub.add_parser("random")
    rn.add_argument("--row", type=lambda x: int(x, 0), default=0)
    rn.add_argument("--prewrite", action="store_true",
                    help="write the sixteen rows first")
    rn.add_argument("--write-ms", type=float, default=5)
    rn.add_argument("--read-run", type=int, default=32)
    rn.add_argument("--read-gap", type=int, default=8, help="PCLK between READs, at least 8")
    rn.add_argument("--read-delay", type=int, default=3)
    rn.add_argument("--gate", type=int, default=0, help="DQS gate offset, memory clocks")
    rn.add_argument("--lat", type=int, default=-1,
                    help="check offset; -1 takes the hist window start + 1")
    rn.add_argument("--step", type=int, default=0, help="expected rotation move per READ")
    rn.add_argument("--seconds", type=float, default=0.5)
    rn.add_argument("--sessions", type=int, default=1)
    rn.add_argument("--sweep-gate", action="store_true")
    rn.add_argument("--slips", type=int, nargs=4, default=[0, 0, 0, 4],
                    help="two-word beat slip for lanes 0..3")
    mt = sub.add_parser("memtest")
    mt.add_argument("--banks", type=lambda x: int(x, 0), nargs="+", default=list(range(8)))
    mt.add_argument("--rows", type=lambda x: int(x, 0), nargs="+",
                    default=[0, 1, 2, 0x155, 0x2AAA, 0x7FFF])
    mt.add_argument("--patterns", type=lambda x: int(x, 0), nargs="+",
                    default=[0x00, 0xFF, 0xAA, 0x55, 0x1D, 0x6B, 0xC5])
    mt.add_argument("--wstep", type=int, nargs="+", default=[0])
    mt.add_argument("--read-run", type=int, default=32)
    mt.add_argument("--read-gap", type=int, default=8)
    mt.add_argument("--read-delay", type=int, default=3)
    mt.add_argument("--write-ms", type=float, default=5)
    mt.add_argument("--pass-ratio", type=float, default=0.75)
    args = ap.parse_args()
    if args.cmd == "logreport":
        log_report(json.load(open(args.file)))
        return 0

    core = Core(args.port)
    try:
        if core.request(0x01)[4] != 0x56:
            raise RuntimeError("the loaded core is not TinyVCMI's")
        deadline = time.time() + 10
        s = core.status()
        while s["state"] < 8 and time.time() < deadline:
            time.sleep(0.2)
            s = core.status()
        print(header(s))
        if args.cmd == "status":
            return 0
        if hasattr(args, "read_run"):
            if (not 1 <= args.read_run <= 255 or not 1 <= args.read_gap <= 255 or
                    not 0 <= args.read_delay <= 7):
                raise ValueError("--read-run/--read-gap must be 1..255 and --read-delay 0..7")
            core.request(0x0D, args.read_run)
            core.request(0x09, args.read_gap)
            core.request(0x22, args.read_delay)
        if args.cmd == "level":
            core.mode(1)
            for v in range(args.start, args.stop + 1, args.step):
                set_wstep(core, [v] * 4)
                s = core.settle()
                print(f"WSTEP {v:3d}: " + "  ".join(
                    f"L{n} {l['count']:5d}" for n, l in enumerate(s["lanes"])))
            core.mode(0)
        elif args.cmd == "rw":
            core.request(0x0E, args.pattern)
            values = args.wstep * 4 if len(args.wstep) == 1 else args.wstep
            set_wstep(core, values)
            s = read_back(core, args.write_ms / 1000)
            print(header(s))
            print(f"eligible read cycles {s['eligible']}")
            for n, l in enumerate(s["lanes"]):
                print(f"    lane {n}: WSTEP {l['wstep']:3d}  match {l['count']:5d}  "
                      f"rotation {rotation(l['words'], args.pattern)}  words {l['words'].hex(' ')}")
        elif args.cmd == "rwsweep":
            core.request(0x0E, args.pattern)
            for v in range(args.start, args.stop + 1, args.step):
                set_wstep(core, [v] * 4)
                s = read_back(core, args.write_ms / 1000)
                print(f"WSTEP {v:3d}: eligible {s['eligible']:5d}  " + "  ".join(
                    f"L{n} {l['count']:5d} r{rotation(l['words'], args.pattern)}"
                    for n, l in enumerate(s["lanes"])))
        elif args.cmd == "calibrate":
            values = args.wstep * 4 if len(args.wstep) == 1 else args.wstep
            if len(values) != 4:
                raise ValueError("--wstep needs one value or four lane values")
            set_wstep(core, values)
            write_address(core, 0, 0, args.pattern, args.write_ms / 1000)
            core.mode(3)
            core.settle()
            align_framing(core, args.pattern)
            centers = sweep_and_center(core, args.pattern, 0.001, args.pass_ratio)
            print("read-delay centers: " + " ".join(
                f"L{n}={v:+d}" if kind == "from default" else f"L{n}=top-{v}"
                for n, (kind, v) in enumerate(centers)))
            if args.sessions:
                write_address(core, 0, 0, args.pattern, args.write_ms / 1000)
                verify_sessions(core, args.pattern, args.sessions, args.pass_ratio)
        elif args.cmd == "burst":
            if not trainable(args.pattern):
                raise ValueError("a pattern needs eight distinct rotations")
            if not all(1 <= n <= 23 for n in args.windows):
                raise ValueError("--windows takes exponents 1..23")
            core.request(0x0E, args.pattern)
            write_address(core, 0, 0, args.pattern, 0.02)
            print("RCLKSEL  rvalid        " + "  ".join(f"2^{n:<2d} counts 0..3     " for n in args.windows))
            for sel in range(8):
                core.request(0x06, sel)
                core.mode(0)
                core.mode(3)                            # re-enter at this RCLKSEL
                time.sleep(0.02)
                cols = []
                for n in args.windows:
                    core.request(0x24, n)               # count for 2^n PCLK, then hold
                    deadline = time.time() + 2
                    b = core.status()
                    while b["burst_window_open"] and time.time() < deadline:
                        time.sleep(0.002)
                        b = core.status()
                    if b["burst_window_open"]:
                        raise RuntimeError("the RBURST window did not close")
                    cols.append(f"{str(b['burst_count']):22s}")
                print(f"{sel:7d}  {[l['rv'] for l in b['lanes']]}  " + "  ".join(cols))
            core.request(0x06, 0)
            core.request(0x24, 0)
            core.mode(0)
        elif args.cmd == "phase":
            if not trainable(args.pattern):
                raise ValueError("a pattern needs eight distinct rotations")
            values = args.wstep * 4 if len(args.wstep) == 1 else args.wstep
            set_wstep(core, values)
            core.request(0x0E, args.pattern)
            write_address(core, 0, 0, args.pattern, args.write_ms / 1000)
            core.mode(3)
            core.request(0x23)                      # clear the monitor
            core.settle()
            print(f"pattern {args.pattern:#04x} read-run {args.read_run} gap {args.read_gap}")
            print("   moves  at-gap  delta  step[0..3]  skew  phase[0..3]  ok")
            for i in range(args.samples):
                s = core.status()
                print(f"{s['chg_total']:8d} {s['chg_gap']:7d} {s['delta_last']:6d} "
                      f"{s['phase_step']}  {s['skew_changed']:4d}  {s['phase']}  {s['phase_ok']:04b}")
                time.sleep(args.interval_ms / 1000)
            core.mode(0)
        elif args.cmd == "gate":
            if not trainable(args.pattern):
                raise ValueError("a pattern needs eight distinct rotations")
            core.request(0x0E, args.pattern)
            write_address(core, 0, 0, args.pattern, args.write_ms / 1000)
            print(f"read-run {args.read_run} gap {args.read_gap}: the frame move per "
                  "interruption, all four lanes")
            print("delay gate  eligible  match 0..3                      moves  at-gap  step[0..3]")
            for d in args.delays:
                for k in args.offsets:
                    core.request(0x22, d)
                    core.request(0x25, k)
                    core.mode(0)
                    core.mode(3)
                    core.request(0x23)                  # clear the monitor
                    time.sleep(args.settle_ms / 1000)
                    s = core.snapshot()
                    print(f"{d:5d} {k:4d}  {s['eligible']:8d}  " +
                          " ".join(f"{s['lanes'][n]['count']:6d}" for n in range(4)) +
                          f"  {s['chg_total']:13d}  {s['chg_gap']:6d}  {s['phase_step']}")
            core.request(0x25, 0)
            core.request(0x22, args.read_delay)
            core.mode(0)
        elif args.cmd == "prewrite":
            prewrite(core, args.row, args.write_ms / 1000)
            print(f"wrote the sixteen rd_check rows at row {args.row & ~1:#06x}/{args.row | 1:#06x}")
        elif args.cmd == "random":
            if args.read_gap < 8:
                raise ValueError("random mode spaces READs at least 8 PCLK apart")
            if args.prewrite:
                prewrite(core, args.row, args.write_ms / 1000)
                # rd_check needs every DQ bit in frame: align them on bank
                # 0's row, which holds the first pattern, in a read stream
                core.request(0x0E, RC_PATTERNS[0])
                core.mode(3)
                core.settle()
                align_framing(core, RC_PATTERNS[0])
                core.mode(0)
            core.address(0, args.row & ~1)
            core.set_slips(args.slips)
            core.request(0x28, args.step)
            cases = [(d, k) for d in range(8) for k in range(4)] if args.sweep_gate \
                else [(args.read_delay, args.gate)]
            failures = 0
            for d, k in cases:
                core.request(0x22, d)
                core.request(0x25, k)
                lat = args.lat
                if lat < 0:
                    # a short run at any offset fills hist; take its window
                    core.request(0x26, 31)
                    c = random_session(core, 0.05)
                    start, width = hist_window(c)
                    lat = start + 1 if width >= 2 else 31
                core.request(0x26, lat)
                for session in range(args.sessions):
                    c = random_session(core, args.seconds)
                    ok = c["total"] > 0 and c["good"] == c["total"]
                    failures += not ok
                    print(f"delay {d} gate {k} session {session + 1}: "
                          f"{'PASS' if ok else 'FAIL'} {check_line(c)}")
                    if not args.sweep_gate:
                        print("    hist " + " ".join(
                            f"{j}:{h}" for j, h in enumerate(c["hist"]) if h) +
                            f"  of {c['hist_n']}")
                    for line in fail_lines(c):
                        print("    " + line)
            core.request(0x25, 0)
            core.request(0x22, args.read_delay)
            if failures and not args.sweep_gate:
                raise RuntimeError(f"{failures} random session(s) failed")
        elif args.cmd == "train":
            if args.prewrite:
                prewrite(core, args.row, 0.2)
            core.request(0x0E, RC_PATTERNS[0])
            core.mode(3)                        # a read stream to align in
            core.settle()
            align_framing(core, RC_PATTERNS[0])
            core.mode(0)
            core.address(0, args.row & ~1)
            core.set_slips([0, 0, 0, 4])
            core.request(0x09, max(args.gap, 8))
            core.request(0x29, 1)
            if args.vendor_delay:
                step = core.status()["step"]
                core.request(0x0A)              # RLOADN: every lane's tap back to STEP
                for lane in range(4):
                    core.move(lane, True, max(step - 4, 0))   # RDIR = 1: down a tap each
                print(f"read delay set as the vendor does: STEP {step}, {max(step - 4, 0)} RMOVE "
                      "pulses at RDIR = 1 on every lane, tap 4")
            if args.vendor_search:
                locked, tried = vendor_search(core, args)
            else:
                locked = [None] * 4
                tried = 0
                for pos in range(args.max_pos + 1):
                    d, k = divmod(pos, 4)
                    prev = [False] * 4
                    for rs in range(8):
                        sets = [locked[n] if locked[n] else (d, k, rs) for n in range(4)]
                        core.set_lanes([x[0] for x in sets], [x[1] for x in sets], [x[2] for x in sets])
                        core.mode(4)                # entering random mode arms the counters
                        time.sleep(args.seconds)
                        core.mode(0)
                        c = core.train_counts()
                        tried += 1
                        n = c["reads"]
                        ok = [n > 100 and abs(c["rv"][l] - n) <= args.tol and abs(c["rb"][l] - n) <= args.tol
                              for l in range(4)]
                        if args.verbose:
                            print(f"gate {pos:2d} (delay {d} k {k}) rclksel {rs}: {n} READs; "
                                  + "  ".join(f"L{l} rv {c['rv'][l] / max(n, 1):5.2f} rb {c['rb'][l] / max(n, 1):5.2f}"
                                              f"{' pass' if ok[l] else '     '}" for l in range(4)))
                        for l in range(4):
                            if locked[l] is None:
                                if ok[l] and prev[l]:
                                    locked[l] = (d, k, rs)
                                    print(f"lane {l} locked at gate {pos} (delay {d} k {k}) rclksel {rs}")
                                prev[l] = ok[l]
                    if all(locked):
                        break
            print(f"{tried} settings tried; trained (delay, k, rclksel) per lane: {locked}")
            # TOOL-037: often only some lanes lock in a load, and those are
            # the ones whose lag matters; an unlocked lane is checked at the
            # old shared setting and marked as such
            if any(locked):
                sets = [locked[n] or (1, 2, 0) for n in range(4)]
                if not all(locked):
                    print("untrained lanes at delay 1 k 2 rclksel 0: "
                          + " ".join(str(n) for n in range(4) if not locked[n]))
                core.set_lanes([x[0] for x in sets], [x[1] for x in sets], [x[2] for x in sets])
                if args.calib_fix:
                    calib_fix(core, args, sets, locked)
                if args.center:
                    center_delay(core, args, sets, locked)
                own = [0.0] * 4
                # per lane, the (share, lag, lat) of its most frequent class
                # other than none, over every check offset
                top = [(0.0, None, None)] * 4
                for lat in args.lats:
                    core.request(0x26, lat)
                    core.mode(4)
                    time.sleep(args.lag_seconds)
                    core.mode(0)
                    g = core.lag()
                    n = g["eval"] or 1
                    own = [max(own[l], 100.0 * g["lag"][l][0] / n) for l in range(4)]
                    for l in range(4):
                        for k in range(LAGS + 1):
                            share = 100.0 * g["lag"][l][k] / n
                            if share > top[l][0]:
                                top[l] = (share, k, lat)
                    print(lag_line(lat, g))
                print("best own % per lane: " + " ".join(f"{v:5.1f}" for v in own))
                for l in range(4):
                    share, k, lat = top[l]
                    print(f"lane {l}{'' if locked[l] else ' (untrained)'}: most often lag {k}"
                          f" in {share:5.1f}% at lat {lat}")
                if args.log:
                    core.request(0x26, args.log_lat)
                    core.request(0x32, args.log_skip)
                    core.mode(4)                # entering random mode arms the log
                    # (skip + 1) x 1024 READs, each at least max(gap, 8) + 5 PCLK
                    # apart and a refresh in place of one every 700 PCLK, at
                    # PCLK 100 MHz; twice that, and never under 50 ms
                    reads = (args.log_skip + 1) * 1024
                    time.sleep(max(0.05, 2 * reads * (max(args.gap, 8) + 5) * 10e-9 * 1.1))
                    core.mode(0)
                    entries = core.read_log()
                    if len(entries) < 1024:
                        print(f"warning: the READ log holds {len(entries)} entries, not 1024")
                    json.dump({"lat": args.log_lat, "skip": args.log_skip, "gap": args.gap,
                               "settings": sets, "locked": [bool(x) for x in locked],
                               "entries": entries}, open(args.log, "w"))
                    print(f"READ log: {len(entries)} READs saved to {args.log}")
                    log_report(json.load(open(args.log)))
                if args.sweep:
                    slip_sweep(core, args, sets, locked)
        elif args.cmd == "lag":
            if args.prewrite:
                prewrite(core, args.row, 0.2)
            core.request(0x0E, RC_PATTERNS[0])
            core.mode(3)                        # a read stream to align in
            core.settle()
            align_framing(core, RC_PATTERNS[0])
            core.mode(0)
            core.address(0, args.row & ~1)
            core.set_slips(args.slips)
            core.set_lanes(args.delay, args.gate, args.rclksel)
            core.request(0x09, max(args.gap, 8))  # random mode's access period
            core.request(0x29, 1 if args.rvalid else 0)
            for lat in args.lats:
                core.request(0x26, lat)
                core.mode(4)                    # entering random mode arms the counters
                time.sleep(args.seconds)
                core.mode(0)
                g = core.lag()
                if lat == args.lats[0]:
                    print(f"delay {g['delay']} gate {g['gate']} rclksel {g['rclksel']} "
                          f"RVALID-held {g['rv_held']}")
                print(lag_line(lat, g))
        elif args.cmd == "pos":
            if args.prewrite:
                prewrite(core, args.row, 0.2)
            core.request(0x0E, RC_PATTERNS[0])
            core.mode(3)                        # a read stream to align in
            core.settle()
            align_framing(core, RC_PATTERNS[0])
            core.mode(0)
            core.address(0, args.row & ~1)
            core.request(0x22, args.read_delay)
            core.request(0x25, args.gate)
            core.set_slips(args.slips)
            core.mode(4)                        # entering random mode arms the counters
            time.sleep(args.seconds)
            p = core.pos()
            core.mode(0)
            total = sum(p["counts"].values())
            print(header(core.status()))
            print(f"READs classified {total}: " + "  ".join(
                f"{n} {p['counts'][n]}" for n in ("both", "only11", "only19", "other")))
            for n in ("both", "only11", "only19", "other"):
                lo, hi = p["phase"][n]
                if p["counts"][n]:
                    print(f"    {n:6s} phase {lo}..{hi}")
            print("    last eight classes, newest first: " +
                  " ".join(str(c) for c in p["classes"]))
        elif args.cmd in ("align", "alignsweep"):
            if not trainable(args.pattern if args.cmd == "align" else args.patterns[0]):
                raise ValueError("a pattern needs eight distinct rotations to train")
            values = args.wstep * 4 if len(args.wstep) == 1 else args.wstep
            if len(values) != 4:
                raise ValueError("--wstep needs one value or four lane values")
            set_wstep(core, values)
            failures = 0
            if args.cmd == "align":
                core.request(0x0E, args.pattern)
                row = args.row
                write_address(core, args.bank, row, args.pattern, args.write_ms / 1000)
                for session in range(args.sessions):
                    core.mode(3)                # entering read mode retrains
                    s = settled_status(core, args.pattern)
                    core.mode(0)
                    bad = check_aligned(s, args.pattern, args.pass_ratio)
                    failures += bool(bad)
                    print(f"session {session + 1}: {aligned_line(s, args.pattern)}: " +
                          ("PASS" if not bad else "FAIL"))
                    for line in bad:
                        print("    " + line)
                if failures:
                    raise RuntimeError(f"{failures} align session(s) failed")
            else:
                for bank in args.banks:
                    for row in args.rows:
                        for pattern in args.patterns:
                            if not trainable(pattern):
                                raise ValueError(f"pattern {pattern:#04x} cannot train")
                            write_address(core, bank, row, pattern, args.write_ms / 1000)
                            core.mode(3)
                            s = settled_status(core, pattern)
                            core.mode(0)
                            bad = check_aligned(s, pattern, args.pass_ratio)
                            failures += bool(bad)
                            print(f"bank {bank} row {row:#06x} pattern {pattern:#04x}: " +
                                  ("PASS " if not bad else "FAIL ") +
                                  aligned_line(s, pattern))
                            for line in bad:
                                print("    " + line)
                if failures:
                    raise RuntimeError(f"{failures} aligned memory cases failed")
        else:
            values = args.wstep * 4 if len(args.wstep) == 1 else args.wstep
            if len(values) != 4:
                raise ValueError("--wstep needs one value or four lane values")
            set_wstep(core, values)
            failures = 0
            for bank in args.banks:
                for row in args.rows:
                    for pattern in args.patterns:
                        write_address(core, bank, row, pattern, args.write_ms / 1000)
                        core.mode(3)
                        s = core.settle()
                        core.mode(0)
                        ok = all(passing(s, lane, args.pass_ratio) for lane in range(4))
                        failures += not ok
                        print(f"bank {bank} row {row:#06x} pattern {pattern:#04x}: " +
                              ("PASS " if ok else "FAIL ") +
                              f"eligible {s['eligible']} " + " ".join(
                                  f"L{lane}={s['lanes'][lane]['count']}" for lane in range(4)))
            if failures:
                raise RuntimeError(f"{failures} memory cases failed")
        print(header(core.status()))
    finally:
        core.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
