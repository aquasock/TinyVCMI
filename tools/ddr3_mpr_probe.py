#!/usr/bin/env python3
"""Drive the DDR3 MPR read-back image on the board and sweep its read path.

The image (fpga/ddr3_mpr, built by tools/build_ddr3_mpr.sh and loaded with
TinyTang's `tangload`) initializes the DDR3 device, puts it in MPR mode and
streams reads once asked to.  This tool opens TinyTang's `fpgapipe` once and
talks to the core over it:

  status      wait for initialization, print the decoded status
  sweep       switch reads on and step RCLKSEL through 0..7, printing every
              lane's pattern count and DQ words at each setting
  delay       at one RCLKSEL, step every lane's read delay with RMOVE from
              its default, printing the same at each step

A lane's pattern count is the number of PCLK cycles, out of 65535, in which
all eight of its DQ words are equal and either 0x55 or 0xAA -- the MPR
pattern at any alignment.  It touches nothing but the link; the board must
already be running the image.

Usage:
    tools/ddr3_mpr_probe.py status
    tools/ddr3_mpr_probe.py sweep
    tools/ddr3_mpr_probe.py delay --rclksel 2 --steps 32 [--dir 1]
"""

import argparse
import sys
import time

import serial

STATES = ["idle", "reset", "cke", "xpr", "mrs", "zq", "mpr", "reads"]


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
        b = self.request(0x03, expect=60)[4:]
        s = {"ready": b[0] >> 7 & 1, "pll": b[0] >> 6 & 1, "lock": b[0] >> 5 & 1,
             "cke": b[0] >> 3 & 1, "reset_n": b[0] >> 2 & 1, "reads": b[0] >> 1 & 1,
             "step": b[1], "rclksel": b[2] >> 4 & 7, "state": STATES[b[2] & 7] if b[2] & 15 < 8 else b[2] & 15,
             "moves": int.from_bytes(b[3:4], "little", signed=True),
             "sys": int.from_bytes(b[4:6], "little"), "pclk": int.from_bytes(b[6:8], "little"),
             "lanes": []}
        for n in range(4):
            o = 8 + 12 * n
            s["lanes"].append({"rv": b[o] >> 3 & 1, "rb": b[o] >> 2 & 1, "rf": b[o] >> 1 & 1,
                               "wf": b[o] & 1, "rp": b[o + 1] >> 3 & 7, "wp": b[o + 1] & 7,
                               "good": int.from_bytes(b[o + 2:o + 4], "little"),
                               "words": b[o + 4:o + 12].hex(" ")})
        return s

    def snapshot(self) -> dict:
        self.request(0x04)
        time.sleep(0.01)
        return self.status()


def header(s: dict) -> str:
    return (f"ready {s['ready']} pll {s['pll']} lock {s['lock']} cke {s['cke']} "
            f"reset_n {s['reset_n']} reads {s['reads']} state {s['state']} STEP {s['step']:#04x} "
            f"RCLKSEL {s['rclksel']} moves {s['moves']:+d} sys {s['sys']:5d} pclk {s['pclk']:5d}")


def lanes(s: dict) -> str:
    return "\n".join(f"    lane {n}: pattern {l['good']:5d}/65535  words {l['words']}  "
                     f"rv{l['rv']} rb{l['rb']} rf{l['rf']} wf{l['wf']} rp{l['rp']} wp{l['wp']}"
                     for n, l in enumerate(s["lanes"]))


def settle(core: Core) -> dict:
    # two full 65535-cycle windows at 100 MHz
    time.sleep(0.005)
    return core.snapshot()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    sub.add_parser("sweep")
    d = sub.add_parser("delay")
    d.add_argument("--rclksel", type=int, default=2)
    d.add_argument("--steps", type=int, default=32)
    d.add_argument("--dir", type=int, default=1, choices=(0, 1))
    args = ap.parse_args()

    core = Core(args.port)
    try:
        if core.request(0x01)[4] != 0x56:
            raise RuntimeError("the loaded core is not TinyVCMI's")
        deadline = time.time() + 10
        s = core.status()
        while s["state"] != "reads" and time.time() < deadline:
            time.sleep(0.2)
            s = core.status()
        print(header(s))
        if args.cmd == "status":
            print(lanes(settle(core)))
            return 0
        core.request(0x08, 1)
        if args.cmd == "sweep":
            for sel in range(8):
                core.request(0x06, sel)
                core.request(0x0A)
                s = settle(core)
                print(f"RCLKSEL {sel}")
                print(lanes(s))
        else:
            core.request(0x06, args.rclksel)
            core.request(0x0A)
            s = settle(core)
            print(f"RCLKSEL {args.rclksel}, read delay default")
            print(lanes(s))
            for i in range(1, args.steps + 1):
                core.request(0x07, args.dir)
                s = settle(core)
                print(f"RCLKSEL {args.rclksel}, read delay {s['moves']:+d}")
                print(lanes(s))
        core.request(0x08, 0)
        print(header(core.status()))
    finally:
        core.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
