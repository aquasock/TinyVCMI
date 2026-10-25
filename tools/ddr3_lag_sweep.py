#!/usr/bin/env python3
"""Per-lane READ gate and RCLKSEL sweep of the lag classifier.

Drives the fpga/ddr3_write image through tools/ddr3_write_probe.py's `Core`,
after `ddr3_write_probe.py calibrate`.  Every lane has its own READ gate delay,
gate offset and RCLKSEL (commands 0x2C, 0x2D, 0x2E) and its own lag counts
(frame 0x2F), so setting all four lanes alike sweeps every lane's choice at
once.  For each setting it runs closed-page single READs (mode 4) at the
access period --gap and, at each check offset in --lats, reads which READ's
pattern each lane held.  One line per setting: per lane, the largest share of
READs holding their own pattern over those offsets and the offset it came
at, the RBURST level share and the RVALID share.  --rvalid checks each lane's
word held from its last RVALID cycle (command 0x29).

    tools/ddr3_lag_sweep.py [--prewrite] [--gap 40] [--lats 12 16 20 24 28]
                            [--rclksel 0 .. 7] [--delays 0 .. 7] [--gates 0 .. 3]
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
    ap.add_argument("--prewrite", action="store_true")
    ap.add_argument("--row", type=int, default=0)
    ap.add_argument("--gap", type=int, default=40)
    ap.add_argument("--lats", type=int, nargs="+", default=[12, 16, 20, 24, 28])
    ap.add_argument("--rclksel", type=int, nargs="+", default=list(range(8)))
    ap.add_argument("--delays", type=int, nargs="+", default=list(range(8)))
    ap.add_argument("--gates", type=int, nargs="+", default=list(range(4)))
    ap.add_argument("--seconds", type=float, default=0.08)
    ap.add_argument("--slips", type=int, nargs=4, default=[0, 0, 0, 4])
    ap.add_argument("--rvalid", action="store_true",
                    help="check each lane's word held from its last RVALID cycle (0x29)")
    args = ap.parse_args()

    core = probe.Core(args.port)
    try:
        if args.prewrite:
            probe.prewrite(core, args.row, 0.2)
        core.request(0x0E, probe.RC_PATTERNS[0])
        core.mode(3)                            # a read stream to align in
        core.settle()
        probe.align_framing(core, probe.RC_PATTERNS[0])
        core.mode(0)
        core.address(0, args.row & ~1)
        core.set_slips(args.slips)
        core.request(0x09, max(args.gap, 8))
        core.request(0x29, 1 if args.rvalid else 0)
        for rs in args.rclksel:
            for d in args.delays:
                for g in args.gates:
                    core.set_lanes([d] * 4, [g] * 4, [rs] * 4)
                    best = [(0.0, 0)] * 4
                    rb = [0.0] * 4
                    rv = [0.0] * 4
                    for lat in args.lats:
                        core.request(0x26, lat)
                        core.mode(4)            # entering random mode arms the counters
                        time.sleep(args.seconds)
                        core.mode(0)
                        f = core.lag()
                        n = f["eval"] or 1
                        for lane in range(4):
                            own = 100.0 * f["lag"][lane][0] / n
                            if own > best[lane][0]:
                                best[lane] = (own, lat)
                        rb = [100.0 * c / (f["cycles"] or 1) for c in f["rb"]]
                        rv = [100.0 * c / (f["cycles"] or 1) for c in f["rv"]]
                    lanes = "  ".join(f"L{lane} {best[lane][0]:5.1f}@{best[lane][1]:2d}"
                                      for lane in range(4))
                    print(f"rclksel {rs} delay {d} gate {g}: own {lanes}   RB "
                          + " ".join(f"{v:5.1f}" for v in rb) + "   RV "
                          + " ".join(f"{v:5.1f}" for v in rv), flush=True)
    finally:
        core.mode(0)
        core.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
