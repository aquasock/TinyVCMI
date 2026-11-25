#!/usr/bin/env bash
# Build a nextpnr-himbaechel whose GW5AST-138C chipdb carries the timing arcs
# the fork's generator leaves out (tools/nextpnr_arcs.patch): LUT1 to LUT3
# take the LUT4's arcs (TOOL-065) and the LUT RAM's data inputs get their
# setup check, which the generator wrote as "DI[n" with no closing bracket so
# that it named no port (TOOL-070).  The installed toolchain and the fork's
# repository are left untouched: the binary is copied into OUT, and the
# generator is run from a patched copy beside links to its other files.
#
# Before anything is patched, the unpatched chipdb is regenerated the same
# way and must equal the installed one byte for byte, so the patched chipdb
# differs from the installed one by the patch alone.
#
#   nextpnr_arcs.sh [OUT]      (default /home/vash/tools/nextpnr-tinyvcmi-arcs)
#
# Then NEXTPNR_HIMBAECHEL=OUT/nextpnr-himbaechel selects it in
# tools/openflow_env.sh.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-/home/vash/tools/nextpnr-tinyvcmi-arcs}
fork=${NEXTPNR_FORK:-/run/media/vash/GIT/nextpnr-mathieufro}
build=${NEXTPNR_BUILD:-/home/vash/tools/nextpnr-mathieufro}
apicula=${APICULA_FORK:-/run/media/vash/GIT/apicula-mathieufro}
py=${PYTHON3:-/home/vash/oss-cad-suite/py3bin/python3}
src="$fork/himbaechel/uarch/gowin"
installed="$build/share/himbaechel/gowin/chipdb-GW5AST-138C.bin"

mirror() {      # dir: the generator's directory, every file linked but the generator
    mkdir -p "$1/himbaechel/uarch/gowin"
    ln -sfn "$fork/himbaechel/himbaechel_dbgen" "$1/himbaechel/himbaechel_dbgen"
    for f in "$src"/*; do
        case "$(basename "$f")" in
            gowin_arch_gen.py|__pycache__) ;;
            *) ln -sfn "$f" "$1/himbaechel/uarch/gowin/$(basename "$f")" ;;
        esac
    done
}
generate() {    # dir, out.bin
    (cd "$1/himbaechel/uarch/gowin" &&
        PYTHONPATH="$apicula" "$py" gowin_arch_gen.py -d GW5AST-138C -o "$1/chipdb.bba" >"$1/gen.log" 2>&1)
    "$build/bba/bbasm" --le "$1/chipdb.bba" "$2"
}

mkdir -p "$out/share/himbaechel/gowin"
echo "control: the unpatched generator must reproduce the installed chipdb"
mirror "$out/gen"
cp "$src/gowin_arch_gen.py" "$out/gen/himbaechel/uarch/gowin/gowin_arch_gen.py"
generate "$out/gen" "$out/gen/control.bin"
cmp "$out/gen/control.bin" "$installed"
echo "  identical to $installed"

echo "patched: tools/nextpnr_arcs.patch"
mirror "$out/genfix"
cp "$src/gowin_arch_gen.py" "$out/genfix/himbaechel/uarch/gowin/gowin_arch_gen.py"
(cd "$out/genfix" && patch -p1 --quiet <"$root/tools/nextpnr_arcs.patch")
generate "$out/genfix" "$out/share/himbaechel/gowin/chipdb-GW5AST-138C.bin"
cp "$build/nextpnr-himbaechel" "$out/nextpnr-himbaechel"
sha256sum "$out/share/himbaechel/gowin/chipdb-GW5AST-138C.bin" "$out/nextpnr-himbaechel"
echo "NEXTPNR_HIMBAECHEL=$out/nextpnr-himbaechel"
