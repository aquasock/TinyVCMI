#!/usr/bin/env bash
# One load's read check for repeating across Tang reboots: load the RVALID-
# held write image, calibrate, run the lag classifier with RVALID capture at
# the old shared setting and at one per-lane combination over check offsets
# 14 to 25, re-enter random mode five times at offset 20, restore the desktop
# core and summarise.  Run it once per boot (or per load) and compare.
# Touches the board: TinyTang must be up with ddr3_rv.bin on its card.
#
#   tools/ddr3_boot_repeat.sh <run-name>      results in build/ddr3_boot/<run-name>
set -u
cd /run/media/vash/GIT/TinyVCMI
out=build/ddr3_boot/$1
mkdir -p "$out"
python3 tools/tang_console.py run tangload /root/cores/console138k/ddr3_rv.bin 2>&1 | grep 'tangload:' | tail -1
sleep 2
python3 tools/ddr3_write_probe.py calibrate > "$out/cal.txt" 2>&1 || { echo "calibrate failed"; tail -2 "$out/cal.txt"; }
grep 'session 5' "$out/cal.txt"
p="python3 tools/ddr3_write_probe.py lag --rvalid --gap 40 --seconds 0.15"
$p --prewrite --lats $(seq 14 25) > "$out/shared.txt" 2>&1
$p --delay 1 1 1 1 --gate 3 1 0 0 --rclksel 3 3 3 5 --lats $(seq 14 25) > "$out/perlane.txt" 2>&1
$p --delay 1 1 1 1 --gate 3 1 0 0 --rclksel 3 3 3 5 --lats 20 20 20 20 20 > "$out/reentry.txt" 2>&1
python3 tools/tang_console.py run tangload /root/cores/console138k/tinytang.bin 2>&1 | grep 'tangload:' | tail -1
python3 - "$out" <<'PY'
import re,sys,os
d=sys.argv[1]
def parse(f):
    rows=[]
    for l in open(os.path.join(d,f)):
        m=re.match(r'lat +(\d+): (\d+) READs, % at lag 0 1 2 3 none: (.*?)   RBURST level % (.*?)   RVALID % (.*)',l)
        if not m: continue
        lanes=re.findall(r'L(\d) +([\d.]+) +([\d.]+) +([\d.]+) +([\d.]+) +([\d.]+)',m.group(3))
        own=[float(x[1]) for x in lanes]; rv=[float(x) for x in m.group(5).split()]
        rows.append((int(m.group(1)),own,rv))
    return rows
for f in ('shared.txt','perlane.txt'):
    r=parse(f)
    if not r: print(f, 'no data:', open(os.path.join(d,f)).read()[-200:]); continue
    best=[max(x[1][l] for x in r) for l in range(4)]
    at=[[x[0] for x in r if x[1][l]>=99.9] for l in range(4)]
    rvs=[sorted(set(x[2][l] for x in r)) for l in range(4)]
    print(f"{f:12s} best own % {best}  100% at {at}  RVALID % seen {rvs}")
r=parse('reentry.txt')
for x in r: print(f"reentry lat {x[0]}: own % {x[1]}  RVALID % {x[2]}")
PY
