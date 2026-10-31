"""Report route delay across the DDR3 I/O boundary, at --post-route.

nextpnr's Gowin timing model has no arcs for IDES8_MEM, OSER8, OSER8_MEM or
DQS (TOOL-050), so nothing in the normal timing report covers the crossings
between those cells and the fabric.  This hook measures them directly:
getNetinfoRouteDelay from a net's driver to each of its sinks, for the ports
that leave or enter the DDR3 cells.

    nextpnr-himbaechel ... --post-route tools/bnd_delay.py
"""
import statistics
import sys

IO_TYPES = ("IDES8_MEM", "OSER8_MEM", "OSER8")
classes = {"in": [], "out": [], "dqs_in": [], "dqs_out": []}
detail = {"in": [], "out": [], "dqs_in": [], "dqs_out": []}


def ns(net, port):
    try:
        return ctx.getDelayNS(ctx.getNetinfoRouteDelay(net, port))
    except Exception:
        return None


def ctype(cell):
    return cell.type if cell is not None else None


def classify(driver_cell, sink_cell):
    d = ctype(driver_cell)
    s = ctype(sink_cell)
    if d == "IDES8_MEM" and s not in IO_TYPES and s != "DQS":
        return "in"
    if s in IO_TYPES and d not in IO_TYPES and d != "IDES8_MEM":
        return "out"
    if d == "DQS" and s not in IO_TYPES and s != "DQS":
        return "dqs_out"
    if s == "DQS" and d not in IO_TYPES:
        return "dqs_in"
    return None


for net_kv in ctx.nets:
    net = net_kv.second
    drv = net.driver
    if drv is None:
        continue
    for user in net.users:
        cls = classify(drv.cell, user.cell)
        if cls is None:
            continue
        d = ns(net, user)
        if d is None:
            continue
        classes[cls].append(d)
        detail[cls].append((d, net.name, "%s.%s" % (drv.cell.name, drv.port),
                            "%s.%s" % (user.cell.name, user.port)))

for cls in ("in", "out", "dqs_in", "dqs_out"):
    v = classes[cls]
    if not v:
        print("BND %-8s none" % cls)
        continue
    v.sort()
    print("BND %-8s n=%4d max=%6.3f p95=%6.3f med=%6.3f ns"
          % (cls, len(v), v[-1], v[int(len(v) * 0.95) - 1], statistics.median(v)))
    for d, net, src, snk in sorted(detail[cls], reverse=True)[:4]:
        print("    worst %6.3f ns  %s  %s -> %s" % (d, net, src, snk))
sys.stdout.flush()
