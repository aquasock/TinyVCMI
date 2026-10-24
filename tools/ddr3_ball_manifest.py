#!/usr/bin/env python3
"""Write or check the DDR3 ball manifest a design declares its DDR context with.

Apicula refuses every pad on banks 6 and 7 of the GW5AST-138C unless the
design is packed with `gowin_pack --ddr3-context MANIFEST`, and then admits
only the balls the manifest lists, each in exactly the configuration it
states.  Which balls the board's DDR3 uses is a board fact, so the manifest
lives here, generated from the hardware-proven controller's pin map
(Tang-PSX `gateware/ddr3_vendor/tang_psx_ddr3.cst`):

* every `ddr_*` ball with its port, IO site and bank, read from the chipdb
  pinout, and refused unless the bank is 6 or 7;
* `SSTL15` for a single-ended ball and `SSTL15D` for both halves of a strobe
  or clock pair, with the pair's partner and the half (`P` or `N`);
* the electrical settings every listed ball must carry, as the proven
  constraints do: `BANK_VCCIO=1.5`, `PULL_MODE=NONE`, and `DRIVE=8` on
  outputs.

`--check` regenerates the manifest in memory and fails unless it equals the
committed file byte for byte.

Usage:
    tools/ddr3_ball_manifest.py                 # write fpga/ddr3/ddr3_balls.json
    tools/ddr3_ball_manifest.py --check

Run it with the open-flow environment sourced (`tools/openflow_env.sh`).
"""

import argparse
import json
import os
import re
import sys

import dqs_port_probe as base

PIN_MAP = "/run/media/vash/GIT/Tang-PSX/gateware/ddr3_vendor/tang_psx_ddr3.cst"
SOURCE = "Tang-PSX commit 61974ca, gateware/ddr3_vendor/tang_psx_ddr3.cst"
OUT = os.path.join(base.ROOT, "fpga/ddr3/ddr3_balls.json")
DDR3_BANKS = (6, 7)


def build(pin_map: str) -> dict:
    import fs_site_diff as fsd

    dev = fsd.chipdb.load_chipdb(fsd.DB)
    pinout = dev.pinout["GW5AST-138C"]["PBGA484A"]
    with open(pin_map) as f:
        text = f.read()
    types = dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+IO_TYPE=(\w+)', text))
    balls = []
    for port, pins in re.findall(r'IO_LOC\s+"(ddr_[^"]+)"\s+([\w,]+)', text):
        pins = pins.split(",")
        io_type = types[port]
        if (len(pins) == 2) != (io_type == "SSTL15D") or io_type not in ("SSTL15", "SSTL15D"):
            raise SystemExit(f"{port}: {pins} at {io_type} is neither one SSTL15 ball "
                             f"nor an SSTL15D pair")
        for half, pin in zip("PN", pins):
            site = pinout[pin][0]
            bank = dev.pin_bank.get(site)
            if bank not in DDR3_BANKS:
                raise SystemExit(f"{port} ball {pin} ({site}) is on bank {bank}, not a DDR3 bank")
            entry = {"pin": pin, "site": site, "bank": bank, "port": port, "io_type": io_type}
            if len(pins) == 2:
                entry["half"] = half
                entry["pair"] = pins[1] if half == "P" else pins[0]
            balls.append(entry)
    balls.sort(key=lambda b: (b["bank"], b["site"]))
    if len({b["site"] for b in balls}) != len(balls):
        raise SystemExit("a ball is listed twice")
    return {
        "device": "GW5AST-138C",
        "package": "PBGA484A",
        "source": SOURCE,
        "settings": {"BANK_VCCIO": "1.5", "PULL_MODE": "NONE", "DRIVE": "8"},
        "balls": balls,
    }


def render(manifest: dict) -> str:
    head = {k: v for k, v in manifest.items() if k != "balls"}
    lines = json.dumps(head, indent=2)[:-2] + ',\n  "balls": [\n'
    lines += ",\n".join("    " + json.dumps(b) for b in manifest["balls"])
    return lines + "\n  ]\n}\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pin-map", default=PIN_MAP)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--check", action="store_true",
                    help="fail unless the committed manifest equals a fresh one")
    args = ap.parse_args()
    manifest = build(args.pin_map)
    text = render(manifest)
    banks = {b: sum(1 for x in manifest["balls"] if x["bank"] == b) for b in DDR3_BANKS}
    summary = (f"{len(manifest['balls'])} balls, bank 6 {banks[6]}, bank 7 {banks[7]}, "
               f"{sum('half' in b for b in manifest['balls']) // 2} SSTL15D pairs")
    if args.check:
        with open(args.out) as f:
            ok = f.read() == text
        print(f"{'PASS' if ok else 'FAIL'}  {os.path.relpath(args.out, base.ROOT)}: {summary}"
              + ("" if ok else "; differs from the proven pin map"))
        return 0 if ok else 1
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as f:
        f.write(text)
    print(f"wrote {os.path.relpath(args.out, base.ROOT)}: {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
