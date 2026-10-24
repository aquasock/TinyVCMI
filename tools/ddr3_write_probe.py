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

Every mode is left back in idle.  It touches nothing but the link; the board
must already be running the image.

Usage:
    tools/ddr3_write_probe.py status
    tools/ddr3_write_probe.py level [--start 0 --stop 255 --step 4]
    tools/ddr3_write_probe.py rw --wstep 32 [--pattern 0x1d]
    tools/ddr3_write_probe.py rwsweep [--start 0 --stop 255 --step 8]
"""

import argparse
import sys
import time

import serial

MODES = ["idle", "level", "write", "read"]


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
        b = self.request(0x03, expect=72)[4:]
        s = {"ready": b[0] >> 7 & 1, "pll": b[0] >> 6 & 1, "lock": b[0] >> 5 & 1,
             "cke": b[0] >> 3 & 1, "reset_n": b[0] >> 2 & 1, "step": b[1],
             "mode": MODES[b[2] >> 6], "state": b[2] & 15, "pattern": b[3],
             "sys": int.from_bytes(b[4:6], "little"), "pclk": int.from_bytes(b[6:8], "little"),
             "eligible": int.from_bytes(b[8:10], "little"), "rclksel": b[10] & 7, "lanes": []}
        for n in range(4):
            o = 12 + 6 * n
            s["lanes"].append({"rv": b[o] >> 3 & 1, "rb": b[o] >> 2 & 1, "rp": b[o + 1] >> 3 & 7,
                               "wp": b[o + 1] & 7,
                               "count": int.from_bytes(b[o + 2:o + 4], "little"),
                               "wstep": b[o + 4],
                               "moves": int.from_bytes(b[o + 5:o + 6], "little", signed=True),
                               "words": b[36 + 8 * n:44 + 8 * n]})
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


def rotation(words: bytes, pattern: int) -> str:
    rots = [((pattern << r) | (pattern >> (8 - r))) & 0xFF for r in range(8)]
    return str(rots.index(words[0])) if words[0] in rots else "-"


def header(s: dict) -> str:
    return (f"ready {s['ready']} pll {s['pll']} lock {s['lock']} cke {s['cke']} "
            f"reset_n {s['reset_n']} mode {s['mode']} state {s['state']} STEP {s['step']:#04x} "
            f"pattern {s['pattern']:#04x} RCLKSEL {s['rclksel']}")


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
    sw = sub.add_parser("rwsweep")
    sw.add_argument("--start", type=int, default=0)
    sw.add_argument("--stop", type=int, default=255)
    sw.add_argument("--step", type=int, default=8)
    sw.add_argument("--pattern", type=lambda x: int(x, 0), default=0x1D)
    sw.add_argument("--write-ms", type=float, default=20)
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
        else:
            core.request(0x0E, args.pattern)
            for v in range(args.start, args.stop + 1, args.step):
                set_wstep(core, [v] * 4)
                s = read_back(core, args.write_ms / 1000)
                print(f"WSTEP {v:3d}: eligible {s['eligible']:5d}  " + "  ".join(
                    f"L{n} {l['count']:5d} r{rotation(l['words'], args.pattern)}"
                    for n, l in enumerate(s["lanes"])))
        print(header(core.status()))
    finally:
        core.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
