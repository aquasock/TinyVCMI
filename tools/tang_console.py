#!/usr/bin/env python3
"""Drive TinyTang's USB console from the host.

TinyTang owns the filesystem and the JTAG programmer, so the host never talks
to the FPGA directly: it puts a file on the card with `tangput` and asks for it
with `tangload`.  Both commands run on the board; this script only types them
and, for `tangput`, streams the bytes the shell is waiting for.

    tools/tang_console.py put <local-file> <board-path>
    tools/tang_console.py run <command...>

The console is the USB CDC device TinyTang enumerates (`ffff:5454`).  Nothing
here programs the FPGA unless the command given is one that does.
"""

import argparse
import hashlib
import os
import sys
import time

import serial


PROMPT = b"# "
READY = b"tangput: ready for"
WROTE = b"tangput: wrote"


def read_until(ser: "serial.Serial", needle: bytes, timeout: float) -> bytes:
    buf = b""
    deadline = time.time() + timeout
    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            buf += chunk
            if needle in buf:
                return buf
    raise TimeoutError(f"timed out waiting for {needle!r}; saw: {buf[-400:]!r}")


def settle(ser: "serial.Serial", timeout: float = 3.0) -> None:
    """Drain whatever the board is saying until it goes quiet."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not ser.read(4096):
            break


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--baud", type=int, default=115200)
    sub = ap.add_subparsers(dest="cmd", required=True)

    put = sub.add_parser("put", help="tangput a local file to the board's card")
    put.add_argument("local")
    put.add_argument("remote")

    run = sub.add_parser("run", help="run one shell command and print its output")
    run.add_argument("command", nargs=argparse.REMAINDER)

    query = sub.add_parser(
        "query", help="send a raw frame through fpgapipe and print the reply")
    query.add_argument("frame", help="request bytes, hex, e.g. aa000301")
    query.add_argument("--expect", type=int, default=7,
                       help="reply bytes to read per attempt (default 7)")
    query.add_argument("--tries", type=int, default=6)

    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, timeout=0.2, write_timeout=60) as ser:
        ser.reset_input_buffer()
        ser.write(b"\r\n")
        try:
            read_until(ser, PROMPT, 5.0)
        except TimeoutError:
            pass  # an idle desktop may not redraw a prompt; commands still work

        if args.cmd == "put":
            data = open(args.local, "rb").read()
            digest = hashlib.sha256(data).hexdigest()
            line = f"tangput {len(data)} {args.remote}\r\n".encode()
            ser.write(line)
            read_until(ser, READY, 15.0)
            ser.write(data)
            ser.flush()
            out = read_until(ser, WROTE, 180.0)
            print(out.decode("utf-8", "replace").strip())
            print(f"host sha256: {digest}")
            if b"tangput: wrote" not in out:
                return 1
            return 0

        if args.cmd == "query":
            # fpgapipe hands the console to the core unframed until the host
            # closes the port, so this is the same serial line with nothing in
            # between: whatever the core transmits, we read.
            ser.write(b"fpgapipe\r\n")
            time.sleep(0.6)
            ser.reset_input_buffer()
            frame = bytes.fromhex(args.frame)
            for attempt in range(args.tries):
                ser.write(frame)
                ser.flush()
                buf = b""
                deadline = time.time() + 1.0
                while time.time() < deadline and len(buf) < args.expect:
                    chunk = ser.read(args.expect - len(buf))
                    if chunk:
                        buf += chunk
                print(f"attempt {attempt + 1}: {buf.hex(' ') or '(nothing)'}")
                if buf[:4] == bytes.fromhex("aa000403"):
                    return 0
                time.sleep(0.2)
            return 1

        command = " ".join(args.command).strip()
        ser.write(command.encode() + b"\r\n")
        try:
            out = read_until(ser, PROMPT, 120.0)
        except TimeoutError as exc:
            print(str(exc), file=sys.stderr)
            return 1
        print(out.decode("utf-8", "replace").strip())
        return 0


if __name__ == "__main__":
    sys.exit(main())
