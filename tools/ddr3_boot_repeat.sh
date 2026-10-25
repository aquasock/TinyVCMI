#!/usr/bin/env bash
# One load's read training and lag check, for repeating across loads and Tang
# reboots: load the write image, calibrate, prewrite the sixteen rd_check rows,
# train each lane by the proven controller's rule and run the lag classifier
# at the trained settings over check offsets 14 to 25, restore the desktop core
# and summarise which lanes locked, where, and how many READs back each lane's
# delivered burst most often is.  Run it once per load and compare.
# Touches the board: TinyTang must be up with the image on its card.
#
#   tools/ddr3_boot_repeat.sh <run-name> [image]   results in build/ddr3_boot/<run-name>
#
# The image defaults to ddr3_lag8.bin, the eight-READ lag classifier's.  Until
# 2026-10-25 this script ran the fixed shared and per-lane lag checks of
# TOOL-035 on ddr3_rv.bin instead of training.
set -u
cd /run/media/vash/GIT/TinyVCMI
out=build/ddr3_boot/$1
image=${2:-ddr3_lag8.bin}
mkdir -p "$out"
python3 tools/tang_console.py run tangload "/root/cores/console138k/$image" 2>&1 | grep 'tangload:' | tail -1
sleep 2
python3 tools/ddr3_write_probe.py calibrate > "$out/cal.txt" 2>&1 || { echo "calibrate failed"; tail -2 "$out/cal.txt"; }
grep 'session 5' "$out/cal.txt"
python3 tools/ddr3_write_probe.py train --prewrite --lats $(seq 14 25) > "$out/train.txt" 2>&1 ||
    { echo "train failed"; tail -2 "$out/train.txt"; }
python3 tools/tang_console.py run tangload /root/cores/console138k/tinytang.bin 2>&1 | grep 'tangload:' | tail -1
grep -E '^(lane [0-3] locked|[0-9]+ settings tried|untrained|best own|lane [0-3].*most often)' "$out/train.txt"
