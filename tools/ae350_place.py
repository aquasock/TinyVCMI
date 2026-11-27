# SPDX-License-Identifier: GPL-3.0-only
# nextpnr --pre-place script for the AE350 image (tools/ae350_ddr3_sweep.sh):
# keep the AE350 system's fabric beside the AE350 macro.
#
# The macro is fixed at X159 Y0, the chip's top-right corner, and every AHB
# path leaves it and comes back, some through it combinationally (EXTS_HREADYIN
# to EXTS_HSEL).  Unconstrained, the placer pulled ahb_ram, the UART registers
# and the bridge's bus half to the far left beside ddr3_ctl, and those paths
# spent 23 ns of a 13.3 ns bus clock crossing the chip and back.  The bus half
# meets the PCLK half through the queue's Gray pointers and the line return,
# whose paths are asynchronous and untimed, and through the queue RAM's write
# port, one register-to-RAM hop, so it can sit by the macro.
#
# Constrained to the region: every cell under the soc instance, every cell
# clocked by bus_clk (the flattened names of a few soc registers come from
# top-level nets), and then any logic cell all of whose loads are already
# constrained.  The bridge's queue RAM, xport.fr.mem, is written on bus_clk
# but read asynchronously on PCLK into the command registers beside it, so
# it is left out and the placer puts it with the PCLK half: the one long
# path is then the bus side's staging registers to the RAM's write port.  The region holds 69 or so block RAMs on rows y 9, 27 and 45,
# against the 48 the boot ROM and the block RAM need.
#
# No logic goes in the rightmost column, x 181, which holds the HDMI clocks'
# only ways in: the 371.25 MHz serial clock reaches the HCLK lane that feeds
# every OSER10 from hdmi_pll at X177Y81 through X181Y81's X01 and CLK0
# wires, and hdmi_pll27's CLKFB, tied low, through X181Y45's local wires
# (TinyNES's routed image).  With this region reaching x 181 and the pixel
# side's flops drawn to the divider at X181Y81, every seed of the first
# video sweep left one of those two arcs unrouted.  So the region stops at
# x 180, and every other unplaced logic cell is kept in x 0 to 180.
#
# The video's pixel side is kept the same way beside the HDMI bank, whose
# TMDS pins' OSER10s sit at x 181, rows 57 to 104, with the pixel clock's
# divider at X181Y81: every cell under vpix and hdmi, every cell clocked by
# pix_clk, and logic feeding only those.  Left to itself the placer spread it
# toward the middle of the die, after the FIFO's PCLK flops, and the global
# router found no branch to carry pix_clk to 632 of its sinks there; routed
# before pclk, pix_clk instead took the branches pclk needed and left all
# 25,036 of pclk's sinks to general routing, which could not route them.
X0, Y0, X1, Y1 = 105, 0, 180, 50
REGION = "ae350"
PX0, PY0, PX1 = 140, 55, 180
PIXEL = "pixel"
FABRIC = "fabric"
X_LAST = 180
CLOCK = "bus_clk"
PIX_CLOCK = "pix_clk"

ctx.createRectangularRegion(REGION, X0, Y0, X1, Y1)
Y_LAST = max(ctx.getBelLocation(b).y for b in ctx.getBels())
ctx.createRectangularRegion(FABRIC, 0, 0, X_LAST, Y_LAST)
ctx.createRectangularRegion(PIXEL, PX0, PY0, PX1, Y_LAST)


def clock_net(cell):
    for p in ("CLK", "CLKA", "CLKB"):
        if p in cell.ports and cell.ports[p].net is not None:
            return cell.ports[p].net.name
    return None


fixed_types = ("AE350_SOC", "PLL", "IOB", "IBUF", "OBUF", "TBUF", "IOBUF")
logic = ("LUT1", "LUT2", "LUT3", "LUT4", "MUX2_LUT5", "MUX2_LUT6", "MUX2_LUT7", "MUX2_LUT8")


def gather(prefixes, clock, taken, exclude=()):
    """Cells under the prefixes or clocked by clock, but not under exclude,
    then logic all of whose loads are among them."""
    got = set()
    for name, cell in ctx.cells:
        if name in taken or cell.type in fixed_types or cell.bel is not None:
            continue
        if name.startswith(exclude) and not name.startswith(prefixes):
            continue
        if name.startswith(prefixes) or clock_net(cell) == clock:
            got.add(name)
    for _ in range(4):
        grown = 0
        for name, cell in ctx.cells:
            if name in got or name in taken or cell.type not in logic or cell.bel is not None:
                continue
            loads = []
            for pname, port in cell.ports:
                if port.type == PortType.PORT_OUT and port.net is not None:
                    loads += [u.cell.name for u in port.net.users]
            if loads and all(l in got for l in loads):
                got.add(name)
                grown += 1
        if not grown:
            break
    return got


inside = gather(("soc.",), CLOCK, set(), exclude=("xport.",))
pixel = gather(("vpix.", "hdmi."), PIX_CLOCK, inside)
for name in inside:
    ctx.constrainCellToRegion(name, REGION)
for name in pixel:
    ctx.constrainCellToRegion(name, PIXEL)
inside |= pixel
movable = logic + ("ALU", "DFF", "DFFE", "DFFS", "DFFSE", "DFFR", "DFFRE", "DFFP", "DFFPE",
                   "DFFC", "DFFCE", "DFFN", "DFFNE", "DFFNS", "DFFNSE", "DFFNR", "DFFNRE",
                   "DFFNP", "DFFNPE", "DFFNC", "DFFNCE", "RAM16SDP1", "RAM16SDP2", "RAM16SDP4")
rest = [name for name, cell in ctx.cells
        if name not in inside and cell.bel is None and cell.type in movable]
for name in rest:
    ctx.constrainCellToRegion(name, FABRIC)
print(f"ae350_place: {len(inside) - len(pixel)} cells kept in X{X0}..{X1} Y{Y0}..{Y1} beside "
      f"the AE350, {len(pixel)} in X{PX0}..{PX1} Y{PY0}.. beside the HDMI bank, "
      f"{len(rest)} more in X0..{X_LAST}")
