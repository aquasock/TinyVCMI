#!/usr/bin/env bash
# Place, route, pack and check one seed of an already synthesised controller
# netlist, with or without a pinned DDR3 boundary (tools/ddr3_pin_boundary.py).
#
#   ddr3_pin_seed.sh SEED OUT_DIR [PINS.cst]
#
# The netlist is $TINYVCMI_CTRL_JSON (default build/ddr3_ctrl/open/ctrl.json,
# written by tools/build_ddr3_ctrl.sh, which also runs the simulations and the
# boundary check this skips).  The pins are appended to the generated top.cst.
# After routing, every pinned cell is checked to be on the bel it was given.
# Nothing here touches the board.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export APICULA_FORK=${APICULA_FORK:-/run/media/vash/GIT/apicula-mathieufro}
# shellcheck source=tools/openflow_env.sh
source "$root/tools/openflow_env.sh"

seed=$1
out=$(mkdir -p "$2" && cd "$2" && pwd)
pins=${3:-}
json=${TINYVCMI_CTRL_JSON:-$root/build/ddr3_ctrl/open/ctrl.json}
vendor=$root/build/ddr3_ctrl/vendor/impl/pnr/probe.fs
mkdir -p "$out"
rm -f "$out/DONE" "$out/FAILED"
fail() { echo "seed $seed: $*" | tee "$out/FAILED"; exit 1; }

cat "$root/fpga/ddr3_ctrl/top.cst" ${pins:+"$pins"} >"$out/top.cst"

"$nextpnr_himbaechel" \
    --json "$json" --write "$out/ctrl-routed.json" \
    --device "$gowin_device" --freq 50 --seed "$seed" \
    --vopt "cst=$out/top.cst" --sdc "${TINYVCMI_SDC:-$root/fpga/ddr3_ctrl/open.sdc}" ${TINYVCMI_PNR_EXTRA:-} \
    >"$out/nextpnr.log" 2>&1 || fail "nextpnr refused: $(grep -E 'ERROR|Max frequency for clock +.pclk' "$out/nextpnr.log" | tail -2 | tr '\n' ' ')"
grep -qE "matched no objects|Cell .* not found" "$out/nextpnr.log" && fail "a constraint matched nothing"
grep -E "Max frequency for clock +'pclk'" "$out/nextpnr.log" | tail -1

if [[ -n $pins ]]; then
    env -u PYTHONHOME -u PYTHONPATH /usr/bin/python3 - "$out/ctrl-routed.json" "$pins" <<'PY' || fail "a pinned cell moved"
import json, re, sys
cells = json.load(open(sys.argv[1]))["modules"]["top"]["cells"]
want = re.compile(r'INS_LOC "([^"]+)" R(\d+)C(\d+)\[(\d)\]\[([AB])\];')
bad = n = 0
for line in open(sys.argv[2]):
    m = want.match(line)
    if not m:
        continue
    n += 1
    name, r, c, cls, h = m[1], int(m[2]), int(m[3]), int(m[4]), m[5]
    bel = cells[name]["attributes"]["NEXTPNR_BEL"]
    x, y, k = re.match(r"X(\d+)Y(\d+)/(?:LUT|DFF)(\d+)", bel).groups()
    if (int(x) + 1, int(y) + 1, int(k) // 2, "AB"[int(k) % 2]) != (c, r, cls, h):
        bad += 1
print(f"pins held: {n - bad} of {n}")
sys.exit(1 if bad else 0)
PY
fi

rm -f "$out/ctrl.fs"
"$oss_suite/py3bin/python3" -m apycula.gowin_pack -d "$gowin_family" \
    --ddr3-context "$root/fpga/ddr3/ddr3_balls.json" \
    -o "$out/ctrl.fs" "$out/ctrl-routed.json" >"$out/pack.log" 2>&1 || fail "pack failed"

(cd "$root/tools" && python3 ddr3_image_check.py "$out/ctrl.fs" --vendor "$vendor" --exact-lanes) \
    >"$out/check.log" 2>&1 || fail "image differs from the vendor reference: $(grep FAIL "$out/check.log" | head -2 | tr '\n' ' ')"
grep -E "^All tables" "$out/check.log"

"$oss_suite/py3bin/python3" "$root/tools/fs2bin.py" "$out/ctrl.fs" "$out/ctrl.bin" >/dev/null
rm -f "$out/ctrl-routed.json.gz"
sha256sum "$out/ctrl.fs" "$out/ctrl.bin" | tee "$out/sha256"
echo done >"$out/DONE"
