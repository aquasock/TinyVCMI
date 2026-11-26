#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check a routed AE350 image's clocks and video block RAM against what this
board has been measured to run.  Exits nonzero, naming each failure.

    ae350_clock_check.py ROUTED_JSON

  * The A25's bus clock must reach the AE350's row-0 clock taps through
    global branch GB10: the taps X164Y0/CLK2 (AHB_CLK), X165Y0/CLK0
    (APB_CLK), X174Y0/CLK0 (DDR_CLK) and X179Y0/CLK0 (RTC_CLK) fed from
    GB20 left the A25 silent (TinyNES DEV-016).  Which branch it gets
    depends on the order nextpnr routes clocks in, so it is checked here
    rather than inferred from NPNR_GOWIN_CLK_FIRST.
  * The HDMI pixel clock must reach the spines only through the clock bridge
    sets measured to clock it: SPINE26 alone, or SPINE16 and SPINE25
    together (TinyNES tools/build_ae350_soc.sh, its core-log entries 14 and
    41; SPINE17 and SPINE18 clock nothing, its DEV-017).  Any other set is
    refused rather than guessed at, except with --trial-pixel-bridges, which
    reports it as UNMEASURED instead: an image so built is not acceptable
    until the picture it shows has been confirmed on the board, and the set
    then added to PIX_BRIDGES with its record.  The two spine sets were
    measured with the pixel clock from a CLKDIV; this image's comes from
    hdmi_pll's CLKOUT0, which no global route reaches, so it runs on general
    routing and uses no bridge at all, which was measured on the board in
    core-log entry 18 (TOOL-075).
  * Every block RAM of the video unit (vpix) must have both ports on one
    clock and only 9-bit-multiple widths: block RAM written on one clock and
    read on another, or in another width, read back wrong in TinyNES's video
    unit in this open flow (its core-log entry 14).
"""

import argparse
import json
import sys

TAPS = ("X164Y0/CLK2", "X165Y0/CLK0", "X174Y0/CLK0", "X179Y0/CLK0")
# the empty set: the pixel clock from hdmi_pll's CLKOUT0 at PLL_R[3] on
# general routing, which reaches no bridge (TinyVCMI TOOL-075), measured
# with the whole picture right on the board (core-log entry 18)
PIX_BRIDGES = ({"SPINE26/CBRIDGEOUT_BOTTOM2"},
               {"SPINE16/CBRIDGEOUT_BOTTOM2", "SPINE25/CBRIDGEOUT_BOTTOM2"},
               set())


def pips(net):
    return net["attributes"]["ROUTING"].split(";")[1::3]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("routed")
    ap.add_argument("--trial-pixel-bridges", action="store_true")
    args = ap.parse_args()
    with open(args.routed) as f:
        top = json.load(f)["modules"]["top"]
    nets, cells = top["netnames"], top["cells"]
    bad = []

    bus = pips(nets["bus_clk"])
    for tap in TAPS:
        fed = sorted(p.split("/")[2] for p in bus if p.startswith(tap + "/"))
        if fed != ["GB10"]:
            bad.append(f"bus_clk tap {tap} fed from {fed or 'nothing'}, not GB10")
    print("bus_clk taps: " + ("GB10 at all four" if not bad else "WRONG"))

    pix = pips(nets["pix_clk"])
    bridges = {p.split("/", 1)[1] for p in pix if "/CBRIDGEOUT" in p}
    print("pix_clk bridges: " + ", ".join(sorted(bridges)))
    if bridges not in PIX_BRIDGES:
        if args.trial_pixel_bridges:
            print("UNMEASURED  pix_clk's bridge set: confirm the picture on the board before accepting")
        else:
            bad.append(f"pix_clk uses unmeasured clock bridges: {sorted(bridges)}")

    rams = {n: c for n, c in cells.items() if n.startswith("vpix.")
            and any(p.startswith("CLKB") for p in c["connections"])}
    two = sorted(n for n, c in rams.items()
                 if c["connections"]["CLKA"] != c["connections"]["CLKB"])
    odd = sorted(n for n, c in rams.items()
                 if any(k.startswith("BIT_WIDTH") and int(v, 2) % 9
                        for k, v in c["parameters"].items()))
    if not rams:
        bad.append("no video block RAM found under vpix")
    if two:
        bad.append(f"video block RAMs on two clocks: {two[:4]}")
    if odd:
        bad.append(f"video block RAMs not in a 9-bit width: {odd[:4]}")
    print(f"video block RAMs: {len(rams)}")

    for b in bad:
        print("FAIL  " + b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
