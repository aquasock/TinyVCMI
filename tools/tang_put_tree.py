#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Copy a directory tree onto the Tang's SD card through TinyTang's console,
and prove the copy by reading every file back.

In 2-wire mode the card is TinyTang's, and the host reaches it only through
the shell's `tangput` and `tangget` (PROT-004).  This makes each directory one
level at a time, puts every file, then reads every file back with `tangget`
and compares it byte for byte with the source, so the card holds exactly the
tree it was given or the tool says which files it does not.  It ends with one
SHA-256 over the sorted list of "<path> <sha256>" lines, a digest of the whole
tree that the same source always gives.

    tools/tang_put_tree.py <local-dir> <card-dir>

    # VCMI 1.7.5's config and Mods beside the game data, as MiSTer lays it out
    tools/tang_put_tree.py ../MiSTer-VCMI/work/vcmi-src/config /root/media/vcmi/data/config
    tools/tang_put_tree.py ../MiSTer-VCMI/work/vcmi-src/Mods /root/media/vcmi/data/Mods

The console is driven by TinyTang's own tools/tinytang_sync.py (its Console
class), taken from the TinyTang checkout beside this repository.  Nothing on
the card is deleted; a file already there is overwritten.
"""

import argparse
import hashlib
import os
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
CONSOLE = "/dev/serial/by-id/usb-TinyTang_TinyTang_CDC_0.1.3-if00"


def tree(root: Path):
    """Every file under root, as (relative posix path, absolute path), sorted."""
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            full = Path(dirpath) / name
            if full.is_symlink():
                raise SystemExit(f"tang_put_tree: {full} is a link; refusing")
            out.append((full.relative_to(root).as_posix(), full))
    return sorted(out)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("local", type=Path)
    ap.add_argument("remote", help="absolute card path, e.g. /root/media/vcmi/data/config")
    ap.add_argument("--port", default=CONSOLE, help="TinyTang's USB console (ffff:5454)")
    ap.add_argument("--tinytang", type=Path, default=HERE.parent.parent / "TinyTang",
                    help="TinyTang checkout whose tools/tinytang_sync.py drives the console")
    args = ap.parse_args()

    sys.path.insert(0, str(args.tinytang / "tools"))
    from tinytang_sync import Console, ConsoleError  # noqa: E402

    if not args.local.is_dir():
        raise SystemExit(f"tang_put_tree: {args.local} is not a directory")
    remote = "/" + args.remote.strip("/")
    files = tree(args.local)
    total = sum(p.stat().st_size for _, p in files)
    dirs = sorted({str(Path(rel).parent) for rel, _ in files} - {"."})
    print(f"{len(files)} files, {total} bytes, {len(dirs)} subdirectories -> {remote}",
          flush=True)

    con = Console(args.port)
    t0 = time.time()
    try:
        if not con.at_prompt():
            raise SystemExit("tang_put_tree: the console is not at its shell prompt")
        con.make_dirs(remote)
        made = set()
        for d in dirs:
            # make_dirs walks from the root each time; make only the new tail.
            parts = d.split("/")
            for i in range(1, len(parts) + 1):
                sub = "/".join(parts[:i])
                if sub not in made:
                    con.command(f'mkdir "{remote}/{sub}"')
                    made.add(sub)
        for n, (rel, full) in enumerate(files, 1):
            con.put(full, f"{remote}/{rel}", full.stat().st_size)
            if n % 50 == 0 or n == len(files):
                print(f"  put {n}/{len(files)}  {time.time() - t0:.0f} s", flush=True)

        bad = []
        lines = []
        with tempfile.TemporaryDirectory() as tmp:
            back = Path(tmp) / "back"
            for n, (rel, full) in enumerate(files, 1):
                data = full.read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                lines.append(f"{rel} {digest}\n")
                try:
                    con.get(f"{remote}/{rel}", back)
                    same = back.read_bytes() == data
                except ConsoleError as exc:
                    same = False
                    print(f"  {rel}: {exc}", flush=True)
                if not same:
                    bad.append(rel)
                if n % 100 == 0 or n == len(files):
                    print(f"  checked {n}/{len(files)}  {time.time() - t0:.0f} s", flush=True)
    finally:
        con.close()

    tree_digest = hashlib.sha256("".join(lines).encode()).hexdigest()
    print(f"tree sha256 {tree_digest}")
    if bad:
        print(f"tang_put_tree: {len(bad)} of {len(files)} files differ on the card:")
        for rel in bad:
            print(f"  {rel}")
        return 1
    print(f"tang_put_tree: all {len(files)} files read back equal, "
          f"{total} bytes in {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
