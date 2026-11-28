#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run a TinyVCMI program under TinyTang's ae350run, in 2-wire mode.

TinyTang owns the card and the core's UART in 2-wire mode, and its ae350run
loads a program from the card into the AE350 and answers the program's card
file requests while it runs (PROT-004, firmware/rt/card.c).  This puts the
ELF on the card with tangput, runs ae350run on it, prints everything the
console says until the shell's prompt returns, and exits with the program's
own exit code, or 1 if it never printed one.

The AE350 image must be loaded and handed over first, with the boot ROM at
TinyVCMI LOAD (tangload, then tools/ddr3_write_probe.py on the console port).

    tools/tang_ae350run.py build/firmware/apps/card_test/card_test.elf
"""

import argparse
import hashlib
import os
import re
import sys
import time

import serial

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tang_console import PROMPT, READY, WROTE, read_until  # noqa: E402

CONSOLE = "/dev/serial/by-id/usb-TinyTang_TinyTang_CDC_0.1.3-if00"
REMOTE_DIR = "/root/tinyvcmi"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("elf")
    ap.add_argument("--port", default=CONSOLE,
                    help="TinyTang's USB console (ffff:5454)")
    ap.add_argument("--remote", default=None,
                    help=f"card path for the ELF (default {REMOTE_DIR}/<name>)")
    ap.add_argument("--timeout", type=float, default=1800.0,
                    help="seconds to follow the program (default 1800)")
    args = ap.parse_args()

    data = open(args.elf, "rb").read()
    remote = args.remote or f"{REMOTE_DIR}/{os.path.basename(args.elf)}"
    with serial.Serial(args.port, 115200, timeout=0.2, write_timeout=60) as ser:
        ser.reset_input_buffer()
        ser.write(b"\r\n")
        try:
            read_until(ser, PROMPT, 5.0)
        except TimeoutError:
            pass
        ser.write(f"mkdir {os.path.dirname(remote)}\r\n".encode())
        read_until(ser, PROMPT, 10.0)

        # "\r" alone: a "\n" after it would become the file's first byte.
        ser.write(f"tangput {len(data)} {remote}\r".encode())
        read_until(ser, READY, 15.0)
        t0 = time.time()
        ser.write(data)
        ser.flush()
        out = read_until(ser, WROTE, 180.0)
        print(f"tangput: {len(data)} bytes to {remote} in {time.time() - t0:.1f} s, "
              f"sha256 {hashlib.sha256(data).hexdigest()[:16]}")
        if b"tangput: wrote" not in out:
            print(out.decode("utf-8", "replace"))
            return 1
        # The prompt can arrive in the same read as "tangput: wrote".
        if PROMPT not in out.split(WROTE, 1)[1]:
            read_until(ser, PROMPT, 10.0)

        ser.write(f"ae350run {remote}\r\n".encode())
        buf = b""
        lines = 0
        code = None
        deadline = time.time() + args.timeout
        while time.time() < deadline:
            chunk = ser.read(4096)
            if chunk:
                buf += chunk
                while b"\n" in buf:
                    line, _, buf = buf.partition(b"\n")
                    text = line.decode("utf-8", "replace").rstrip("\r")
                    lines += 1
                    if text.startswith("TinyVCMI FILE "):
                        continue    # the program's requests; replies are binary
                    print(text, flush=True)
                    m = re.match(r"TinyVCMI EXIT (-?\d+)", text)
                    if m:
                        code = int(m.group(1))
            # The shell's prompt ends without a newline: ae350run has returned.
            if lines > 1 and buf.rstrip(b" ").endswith(b"#"):
                break
        else:
            print(f"tang_ae350run: still running after {args.timeout:.0f} s")
            return 1
    return code if code is not None else 1


if __name__ == "__main__":
    sys.exit(main())
