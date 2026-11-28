#!/usr/bin/env python3
"""List every failing timing endpoint of a routed design, by module.

nextpnr-himbaechel reports only the worst path of each clock pair and a slack
histogram, so a design that misses timing does not say how many paths miss or
where they are.  This tool gives the whole list in two steps.

1. As a nextpnr hook it dumps the routed graph -- every net's driver, its sinks
   and nextpnr's own routed delay to each -- to the file named by
   $TINYVCMI_STA_DUMP:

       TINYVCMI_STA_DUMP=out/sta.json nextpnr-himbaechel ... --post-route tools/ddr3_sta.py

2. Run on that dump it times every register endpoint with the fork's cell arcs
   (gowin_arch_gen.py create_timing_info, Apicula's C1/I0 timing groups, the
   values below) and prints the failing endpoints grouped by module:

       ddr3_sta.py out/sta.json [--top N] [--paths N] [--module PREFIX]

Like nextpnr it times only paths between registers of one clock (both edges),
gives cells without arcs no delay through them (the DDR3 I/O cells, TOOL-050),
and ignores clock skew.  Unlike the fork it times LUT1 to LUT3 as LUT4, so it
is correct on a netlist that has not been through tools/lut4ify.py
(TOOL-065), and it gives ALU's I2 the LUT's c_f arc, which the fork omits.
Check its figures against the nextpnr log's critical paths before relying on
them: the summary prints the worst path of each clock for that purpose.
"""
import collections
import json
import os
import re
import sys

# Apicula GW5AST-138C, speed grade C1/I0, max of the four unateness values (ns).
LUT = {"I0": 0.686, "I1": 0.712, "I2": 0.578, "I3": 0.464}
MUX = {"I0": 0.336, "I1": 0.336, "S0": 0.131}
ALU_SUM = {"I0": 0.686, "I1": 0.712, "I2": 0.578, "I3": 0.464, "CIN": 0.587}
ALU_COUT = {"I0": 0.686, "I1": 0.712, "I2": 0.578, "I3": 0.464, "CIN": 0.044}
RAD_DO = {0: 0.686, 1: 0.712, 2: 0.578, 3: 0.464}
CLK_Q = 0.29
RAM_CLK_DO = 0.392
BSRAM_CLK_DO = 2.82    # SDP read data after its clock, as nextpnr times it
SETUP = 0.044
RAM_SETUP = 0.043
# Every constrained clock in fpga/ae350_ddr3/open.sdc whose domain has
# register-to-register paths.  clk50 is here as core.rx.clk: the 50 MHz pin's
# only sink in the routed netlist is one IBUF, and its output net is that name,
# which is where nextpnr times the domain (20 ns, as the SDC's clk50).  pix_clk5
# is left out: it reaches only the OSER10s' FCLK, so it has no register paths.
PERIODS = {"pclk": 10.0, "mclk": 2.5, "core.rx.clk": 20.0,
           "bus_clk": 13.333, "pix_clk": 13.468}


# --------------------------------------------------------------------------
# Hook mode: inside nextpnr, `ctx` exists.
def dump(path):
    nets = []
    for kv in ctx.nets:  # noqa: F821 (nextpnr's global)
        net = kv.second
        drv = net.driver
        users = []
        for u in net.users:
            if u.cell is None:
                continue
            try:
                d = ctx.getDelayNS(ctx.getNetinfoRouteDelay(net, u))  # noqa: F821
            except Exception:
                d = None
            users.append([u.cell.name, u.port, u.cell.type, d])
        nets.append({
            "net": net.name,
            "drv": [drv.cell.name, drv.port, drv.cell.type] if drv is not None and drv.cell is not None else None,
            "users": users,
        })
    with open(path, "w") as f:
        json.dump({"nets": nets}, f)
    print("STA dump: %d nets to %s" % (len(nets), path))
    sys.stdout.flush()


# --------------------------------------------------------------------------
# Analysis mode.
def is_ff(t):
    return t.startswith("DFF")


def ff_edge(t):
    return "neg" if t.startswith("DFFN") else "pos"


def comb_arcs(ctype, out_port):
    """Input ports and delays feeding out_port of a combinational cell."""
    if ctype.startswith("LUT"):
        return LUT if out_port == "F" else {}
    if ctype.startswith("MUX2_LUT"):
        return MUX if out_port == "O" else {}
    if ctype == "ALU":
        if out_port == "SUM":
            return ALU_SUM
        if out_port == "COUT":
            return ALU_COUT
        return {}
    if ctype == "RAM16SDP4":
        m = re.match(r"DO\[?(\d+)\]?$", out_port)
        if m:
            return {"RAD[%d]" % i: d for i, d in RAD_DO.items()}
    return {}


def analyse(path, top, npaths, module, by_reg=False):
    d = json.load(open(path))["nets"]
    ctype = {}
    sinks_of = {}           # (cell, out_port) -> [(cell, in_port, delay)]
    driver_of = {}          # (cell, in_port) -> ((cell, out_port), delay)
    clk_of = {}             # cell -> clock net
    for n in d:
        for c, p, t, dl in n["users"]:
            ctype[c] = t
        if n["drv"] is None:
            continue
        dc, dp, dt = n["drv"]
        ctype[dc] = dt
        lst = []
        for c, p, t, dl in n["users"]:
            if p == "CLK" or (t in ("SDP", "SDPB", "DPB", "SP") and p in ("CLKB", "CLK")):
                clk_of[c] = n["net"]          # a block RAM's read clock
                continue
            dl = 0.0 if dl is None else dl
            lst.append((c, p, dl))
            driver_of[(c, p)] = ((dc, dp), dl)
        sinks_of[(dc, dp)] = lst

    clocks = {}
    for c, net in clk_of.items():
        clocks.setdefault(net, 0)
        clocks[net] += 1

    def clock_name(net):
        for k in PERIODS:
            if net == k or net.endswith("." + k) or net == k.replace(".", "_"):
                return k
        return net

    # Arrival at each driver pin, per launch (clock, edge): memoised DFS.
    memo = {}
    sys.setrecursionlimit(100000)

    def arrival(pin):
        """{(clock, edge): (time, prev_pin)} at an output pin."""
        if pin in memo:
            return memo[pin]
        memo[pin] = {}
        c, p = pin
        t = ctype.get(c, "")
        res = {}
        if is_ff(t) and p == "Q" and c in clk_of:
            res[(clock_name(clk_of[c]), ff_edge(t))] = (CLK_Q, None)
        elif t == "RAM16SDP4" and p.startswith("DO") and c in clk_of:
            res[(clock_name(clk_of[c]), "pos")] = (RAM_CLK_DO, None)
        elif t in ("SDP", "SDPB", "DPB", "SP") and p.startswith("DO") and c in clk_of:
            res[(clock_name(clk_of[c]), "pos")] = (BSRAM_CLK_DO, None)
        if (t == "RAM16SDP4" and p.startswith("DO")) or (not is_ff(t) and t not in ("SDP", "SDPB", "DPB", "SP")):
            for ip, cd in comb_arcs(t, p).items():
                drv = driver_of.get((c, ip))
                if drv is None:
                    continue
                src, rd = drv
                for k, (at, _) in arrival(src).items():
                    v = at + rd + cd
                    if k not in res or v > res[k][0]:
                        res[k] = (v, (c, ip))
        memo[pin] = res
        return res

    endpoints = []
    for (c, p), (src, rd) in driver_of.items():
        t = ctype.get(c, "")
        if is_ff(t):
            if p not in ("D", "CE", "RESET", "SET", "CLEAR", "PRESET"):
                continue
            setup, cedge = SETUP, ff_edge(t)
        elif t == "RAM16SDP4" and (p.startswith("DI") or p.startswith("WAD") or p == "WRE"):
            setup, cedge = RAM_SETUP, "pos"
        else:
            continue
        if c not in clk_of:
            continue
        cclk = clock_name(clk_of[c])
        if cclk not in PERIODS:
            continue
        per = PERIODS[cclk]
        for (lclk, ledge), (at, _) in arrival(src).items():
            if lclk != cclk:
                continue
            req = per if ledge == cedge else per / 2
            arr = at + rd + setup
            endpoints.append((req - arr, arr, req, cclk, ledge, cedge, c, p, src))

    def trace(src):
        """Path back from a driver pin to its launching register."""
        out = []
        pin = src
        key = None
        while pin is not None:
            arr = arrival(pin)
            if key is None:
                key = max(arr, key=lambda k: arr[k][0])
            if key not in arr:
                break
            at, prev = arr[key]
            out.append("%7.2f  %s.%s (%s)" % (at, pin[0], pin[1], ctype.get(pin[0], "?")))
            if prev is None:
                break
            pin = driver_of[prev][0]
        return out[::-1]

    def mod(cell):
        parts = cell.split(".")
        return ".".join(parts[:2]) if parts[0] in ("glue", "core") and len(parts) > 2 else parts[0]

    print("clocks: " + ", ".join("%s (%d cells)" % (clock_name(k), v) for k, v in sorted(clocks.items(), key=lambda x: -x[1])))
    by_clock = collections.defaultdict(list)
    for e in endpoints:
        by_clock[(e[3], e[4], e[5])].append(e)
    for k, es in sorted(by_clock.items()):
        w = min(es)
        fail = [e for e in es if e[0] < 0]
        print("%-12s %s->%s: %6d endpoints timed, %5d failing, worst slack %6.2f ns (path %.2f ns of %.1f)"
              % (k[0], k[1], k[2], len(es), len(fail), w[0], w[1], w[2]))
    fail = sorted(e for e in endpoints if e[0] < 0)
    if module:
        fail = [e for e in fail if e[6].startswith(module)]
    groups = collections.defaultdict(list)
    for e in fail:
        groups[(e[3], mod(e[6]))].append(e)
    print("\nfailing endpoints by clock and module:")
    for (clk, m), es in sorted(groups.items(), key=lambda x: min(x[1])[0]):
        print("  %-12s %-24s %5d  worst %6.2f ns" % (clk, m, len(es), min(es)[0]))
    if by_reg:
        regs = collections.defaultdict(list)
        for e in fail:
            regs[(e[3], re.sub(r"_(DFF|RAM16)\w*$", "", e[6]))].append(e[0])
        print("\nfailing endpoints by register:")
        for (clk, r), sl in sorted(regs.items(), key=lambda x: min(x[1])):
            print("  %-12s %-56s %4d  worst %6.2f ns" % (clk, r, len(sl), min(sl)))
    if top:
        print("\nworst %d endpoints (by register, worst port):" % top)
        seen = set()
        n = 0
        for e in fail:
            reg = re.sub(r"_DFF\w*$|_DFF\w*_Q(_\d+)?$", "", e[6])
            if e[6] in seen:
                continue
            seen.add(e[6])
            print("  %6.2f  %-12s %s.%s" % (e[0], e[3], e[6], e[7]))
            n += 1
            if n >= top:
                break
    for e in fail[:npaths]:
        print("\npath to %s.%s, slack %.2f ns:" % (e[6], e[7], e[0]))
        for line in trace(e[8]):
            print("   " + line)


if "ctx" in globals():
    dump(os.environ.get("TINYVCMI_STA_DUMP", "sta.json"))
elif __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dump")
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--paths", type=int, default=3)
    ap.add_argument("--module", default="")
    ap.add_argument("--by-reg", action="store_true", help="count failing endpoints per register")
    a = ap.parse_args()
    analyse(a.dump, a.top, a.paths, a.module, a.by_reg)
