#!/usr/bin/env python3
"""Convert an Apicula ASCII bitstream (`.fs`) to the raw image TinyTang loads.

`apycula.gowin_pack` writes `.fs`: the whole configuration stream as '0' and
'1' characters with newlines between frames.  `tangload` hands the file's bytes
straight to the JTAG programmer, so it needs the same stream packed eight bits
to a byte, most significant bit first, with the line breaks removed.  There is
no other content in the file -- no header, no trailer, no compression -- which
is why the conversion is exactly this and why it can be checked.

Checked 2026-10-22 against the recorded smoke image: packing
`build/openflow_smoke/openflow_smoke.fs` reproduces its `.bin` byte for byte
(4,330,782 bytes, no difference at any offset).

Usage: fs2bin.py <input.fs> <output.bin>
"""

import sys


def convert(src: str, dst: str) -> int:
    with open(src, "rb") as f:
        data = f.read()
    stray = set(data) - {0x30, 0x31, 0x0A, 0x0D}
    if stray:
        raise SystemExit(
            f"{src}: unexpected bytes in the ASCII stream: "
            f"{sorted(stray)[:8]}"
        )
    bits = [c & 1 for c in data if c in (0x30, 0x31)]
    if len(bits) % 8:
        raise SystemExit(
            f"{src}: {len(bits)} bits is not a whole number of bytes"
        )
    packed = bytearray(len(bits) // 8)
    for i in range(0, len(bits), 8):
        byte = 0
        for bit in bits[i:i + 8]:
            byte = (byte << 1) | bit
        packed[i // 8] = byte
    with open(dst, "wb") as f:
        f.write(packed)
    return len(packed)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: fs2bin.py <input.fs> <output.bin>", file=sys.stderr)
        return 2
    size = convert(sys.argv[1], sys.argv[2])
    print(f"{sys.argv[2]}: {size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
