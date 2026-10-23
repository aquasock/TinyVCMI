#!/usr/bin/env bash

# Shared paths for the local GW5AST open-flow forks. Source this file.

tinyvcmi_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
oss_suite=${OSS_CAD_SUITE:-/home/vash/oss-cad-suite}
nextpnr_himbaechel=${NEXTPNR_HIMBAECHEL:-/home/vash/tools/nextpnr-mathieufro/nextpnr-himbaechel}
apicula_fork=${APICULA_FORK:-$(dirname "$tinyvcmi_root")/apicula-mathieufro}
python_deps=${PYDEPS:-/home/vash/tools/pydeps}
gowin_device=GW5AST-LV138PG484AC1/I0
gowin_family=GW5AST-138C

[[ -f "$oss_suite/environment" ]] || {
    echo "missing OSS CAD Suite environment: $oss_suite/environment" >&2
    return 2
}

# shellcheck disable=SC1090
source "$oss_suite/environment"
export PYTHONHOME="$oss_suite"
export PYTHONPATH="$apicula_fork:$python_deps:${PYTHONPATH:-}"

[[ -x "$nextpnr_himbaechel" ]] || {
    echo "missing nextpnr-himbaechel: $nextpnr_himbaechel" >&2
    return 2
}
[[ -f "$apicula_fork/apycula/$gowin_family.msgpack.xz" ]] || {
    echo "missing Apicula database: $apicula_fork/apycula/$gowin_family.msgpack.xz" >&2
    return 2
}
