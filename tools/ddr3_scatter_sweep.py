#!/usr/bin/env python3
"""Closed-page scatter reads at every RCLKSEL, read delay and DQS gate offset.

Drives the fpga/ddr3_write image through tools/ddr3_write_probe.py's `Core`,
after `ddr3_write_probe.py calibrate` has aligned the lanes.  It writes the
sixteen rd_check rows, aligns word framing on a stream, then for each setting
sets RCLKSEL on every lane (command 0x06), the READ gate delay (0x22) and
offset (0x25), runs random mode (mode 4) for --seconds and prints one line:
the burst-position classifier's pass rate (0x2B), the best offset of the
checker's 32-offset histogram (0x27), and each lane's RVALID and RBURST level
sampled once from the status frame while random mode runs.

    tools/ddr3_scatter_sweep.py [--rclksel 0 .. 7] [--delays 0 .. 7] [--gates 0 .. 3]
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ddr3_write_probe as probe  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--rclksel", type=int, nargs="+", default=list(range(8)))
    ap.add_argument("--delays", type=int, nargs="+", default=list(range(8)))
    ap.add_argument("--gates", type=int, nargs="+", default=list(range(4)))
    ap.add_argument("--seconds", type=float, default=0.1)
    ap.add_argument("--row", type=int, default=0)
    ap.add_argument("--slips", type=int, nargs=4, default=[0, 0, 0, 4])
    args = ap.parse_args()

    core = probe.Core(args.port)
    try:
        probe.prewrite(core, args.row, 0.2)
        core.request(0x0E, probe.RC_PATTERNS[0])
        core.mode(3)                            # a read stream to align in
        core.settle()
        probe.align_framing(core, probe.RC_PATTERNS[0])
        core.mode(0)
        core.address(0, args.row & ~1)
        core.set_slips(args.slips)
        for rs in args.rclksel:
            core.request(0x06, rs)
            for d in args.delays:
                for g in args.gates:
                    core.request(0x22, d)
                    core.request(0x25, g)
                    core.mode(0)
                    core.mode(4)                # entering random mode arms the counters
                    time.sleep(args.seconds)
                    st = core.status()
                    pos = core.pos()
                    core.mode(0)
                    chk = core.check()
                    cnt = pos["counts"]
                    total = sum(cnt.values()) or 1
                    ok = cnt["both"] + cnt["only11"] + cnt["only19"]
                    hist = chk["hist"]
                    best = max(range(32), key=lambda j: hist[j])
                    rv = "".join(str(lane["rv"]) for lane in st["lanes"])
                    rb = "".join(str(lane["rb"]) for lane in st["lanes"])
                    print(f"rclksel {rs} delay {d} gate {g}: pos {100.0 * ok / total:6.2f}% "
                          f"(both {cnt['both']} 11 {cnt['only11']} 19 {cnt['only19']} "
                          f"of {total})  hist max {hist[best]} at {best} of {chk['hist_n']}  "
                          f"rv {rv} rb {rb}", flush=True)
    finally:
        core.mode(0)
        core.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
