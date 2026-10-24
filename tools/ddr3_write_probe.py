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
import sys
import time

import serial

MODES = ["idle", "level", "write", "read"]
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
             "mode": MODES[b[2] >> 6], "state": b[2] & 15, "pattern": b[3],
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
        s["burst_count"] = [b[123 + n] for n in range(4)]
        return s

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
        for _ in range(count):
            self.request(0x07, (1 << (4 + lane)) | int(up))

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
                     ratio: float = 0.75) -> list[int]:
    """Sweep signed delay positions with alternating data to reject stale words."""
    core.mode(0)
    alternate = other_pattern(pattern)
    centers = []
    for lane in range(4):
        core.request(0x0A)
        for previous, center in enumerate(centers):
            core.move(previous, center >= 0, abs(center))
        core.move(lane, False, 128)
        results = []
        for index in range(256):
            test_pattern = pattern if index % 2 == 0 else alternate
            write_address(core, 0, 0, test_pattern, write_s)
            core.mode(3)
            s = core.settle()
            results.append(passing(s, lane, ratio))
            core.mode(0)
            if index != 255:
                core.move(lane, True)
        start, width = longest_run(results)
        if width == 0:
            raise RuntimeError(f"lane {lane} has no passing read-delay position")
        center = -128 + start + width // 2
        centers.append(center)
        fails = 256 - sum(results)
        print(f"lane {lane}: pass window start {start - 128:+d}, width {width}, "
              f"center {center:+d}, "
              f"failed positions {fails}")
    core.request(0x0A)
    for lane, center in enumerate(centers):
        core.move(lane, center >= 0, abs(center))
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
    bu.add_argument("--samples", type=int, default=5)
    bu.add_argument("--interval-ms", type=float, default=20.0)
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
            print("read-delay centers: " +
                  " ".join(f"L{n}={v:+d}" for n, v in enumerate(centers)))
            if args.sessions:
                write_address(core, 0, 0, args.pattern, args.write_ms / 1000)
                verify_sessions(core, args.pattern, args.sessions, args.pass_ratio)
        elif args.cmd == "burst":
            if not trainable(args.pattern):
                raise ValueError("a pattern needs eight distinct rotations")
            core.request(0x0E, args.pattern)
            write_address(core, 0, 0, args.pattern, 0.02)
            core.mode(3)
            time.sleep(0.05)                            # let the read stream start
            print("RCLKSEL  rvalid          RBURST seen   counts 0..3     edges/s")
            for sel in range(8):
                core.request(0x06, sel)
                time.sleep(0.02)
                core.request(0x24)                      # clear the counters
                time.sleep(0.02)
                a = core.status()
                time.sleep(0.25)                        # measure over 250 ms
                b = core.status()
                spans = [(b["burst_count"][n] - a["burst_count"][n]) & 0xFF
                         for n in range(4)]
                rate = [int(v / 0.25) for v in spans]
                print(f"{sel:7d}  {[l['rv'] for l in b['lanes']]}  "
                      f"{b['burst_seen']:04b}          {b['burst_count']}  {rate}")
                time.sleep(args.interval_ms / 1000)
            core.request(0x06, 0)
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
