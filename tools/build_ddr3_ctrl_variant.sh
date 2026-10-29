#!/usr/bin/env bash
# Build a variant of the DDR3 controller image from tools/ddr3_ctrl_variant.py
# (TOOL-052) as tools/build_ddr3_ctrl.sh steps 3 to 6 build the real one: Yosys
# and the boundary netlist check with the variant's counts, nextpnr, packing,
# its own Gowin fuse reference at place option 1 and route option 0, the
# 306-table check and the raw image.  Nothing here touches the board.
#
#   tools/build_ddr3_ctrl_variant.sh <dir> <n DFFN> <n DFFNS>
#
# <dir>/src/top.v is the variant; the image is <dir>/open/ctrl.bin.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
gowin=${GOWINHOME:-/home/vash/tools/gowin-1.9.11.03}
source "$root/tools/openflow_env.sh" >/dev/null
d=$(cd "$1" && pwd); nlo=$2; nhi=$3
src="$root/fpga/ddr3_ctrl"; wsrc="$root/fpga/ddr3_write"; out="$d/open"; ven="$d/vendor"
mkdir -p "$out"
cells="$oss_suite/share/yosys/gowin/cells_xtra_gw5a.v"
manifest="$root/fpga/ddr3/ddr3_balls.json"

# the Gowin reference, in the background
rm -rf "$ven"; mkdir -p "$ven"
cp "$d/src/top.v" "$src/top.cst" "$wsrc/wr_core.v" "$wsrc/rd_align.v" "$wsrc/rd_check.v" \
   "$src/ctrl_glue.v" "$src/dfi_phy.v" "$src/ddr3_derot.v" "$src/ddr3_bist.v" "$src/ddr3_ctl.v" "$ven/"
cp "$src/vendor.sdc" "$ven/top.sdc"
(cd "$root/tools" && python3 -c "import ddr3_write as w; print(w.tcl(1, 0, True), end=\"\")") >"$ven/run.tcl"
grep -q 'place_option 1' "$ven/run.tcl" && grep -q 'route_option 0' "$ven/run.tcl"
( cd "$ven" && QT_QPA_PLATFORM=offscreen LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libfreetype.so.6 \
    "$gowin/IDE/bin/gw_sh" run.tcl >gw_sh.log 2>&1 ) &
gpid=$!

echo "[3] Yosys"
yosys -Q -T -q -l "$out/synth.log" -p "
    read_verilog -lib $cells
    read_verilog $d/src/top.v $wsrc/wr_core.v $wsrc/rd_align.v $wsrc/rd_check.v
    read_verilog $src/ctrl_glue.v $src/dfi_phy.v $src/ddr3_derot.v $src/ddr3_bist.v
    read_verilog $src/ddr3_ctl.v
    synth_gowin -family gw5a -top top
    write_json $out/ctrl.json
"
python3 - "$out/ctrl.json" "$nlo" "$nhi" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))["modules"]["top"]
want = {"bnd_lo[": ("DFFN", int(sys.argv[2])), "bnd_hi[": ("DFFNS", int(sys.argv[3]))}
reg = re.compile(r"^(bnd_lo\[|bnd_hi\[)\d+\]\.ff\.[rs]\.ff$")
drv = {}
for name, c in m["cells"].items():
    for p, dd in c.get("port_directions", {}).items():
        if dd == "output":
            for b in c["connections"][p]:
                drv[b] = c["type"]
seen = dict.fromkeys(want, 0); bad = []
for name, c in m["cells"].items():
    for p in ("CLK", "PCLK", "FCLK", "ICLK", "TCLK"):
        if p in c["connections"] and drv.get(c["connections"][p][0], "").startswith("LUT"):
            bad.append(f"{name} {p} driven by a LUT")
    r = reg.match(name)
    if r:
        seen[r.group(1)] += 1
        if c["type"] != want[r.group(1)][0] or drv.get(c["connections"]["CLK"][0]) != "CLKDIV":
            bad.append(f"{name} is {c['type']}")
bad += [f"{k}: {n} found, {want[k][1]} expected" for k, n in seen.items() if n != want[k][1]]
if bad:
    sys.exit("\n".join(bad[:20]))
print(f"boundary: {seen['bnd_lo[']} DFFN and {seen['bnd_hi[']} DFFNS on the CLKDIV; no LUT on a clock")
PY
echo "[4] nextpnr"
"$nextpnr_himbaechel" --json "$out/ctrl.json" --write "$out/ctrl-routed.json" --device "$gowin_device" \
    --freq 50 --vopt "cst=$src/top.cst" --sdc "$src/open.sdc" >"$out/nextpnr.log" 2>&1
grep -E "Max frequency for clock" "$out/nextpnr.log" | tail -2
! grep -qE "matched no objects|Cell .* not found|feeds a DQS FCLK" "$out/nextpnr.log"
echo "[5] pack"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack -d "$gowin_family" --ddr3-context "$manifest" \
    -o "$out/ctrl.fs" "$out/ctrl-routed.json" >"$out/pack.log" 2>&1
echo "[6] Gowin reference and table check"
wait $gpid || true
[[ -f "$ven/impl/pnr/probe.fs" ]] || { grep -E 'ERROR' "$ven/gw_sh.log" | head -3; exit 2; }
(cd "$root/tools" && python3 ddr3_image_check.py "$out/ctrl.fs" --vendor "$ven/impl/pnr/probe.fs" --exact-lanes) | grep -E 'PASS|FAIL|All tables'
"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" "$out/ctrl.fs" "$out/ctrl.bin"
sha256sum "$out/ctrl.bin"
echo "variant image written; hardware was not accessed"
