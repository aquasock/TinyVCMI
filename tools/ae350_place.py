# SPDX-License-Identifier: GPL-3.0-only
# nextpnr --pre-place script for the AE350 image (tools/ae350_ddr3_sweep.sh):
# keep the AE350 system's fabric beside the AE350 macro.
#
# The macro is fixed at X159 Y0, the chip's top-right corner, and every AHB
# path leaves it and comes back, some through it combinationally (EXTS_HREADYIN
# to EXTS_HSEL).  Unconstrained, the placer pulled ahb_ram, the UART registers
# and the bridge's bus half to the far left beside ddr3_ctl, and those paths
# spent 23 ns of a 13.3 ns bus clock crossing the chip and back.  The bus half
# only meets the PCLK half through the handshake's registers, whose paths are
# asynchronous and untimed, so it can sit by the macro at no cost.
#
# Constrained to the region: every cell under the soc instance, every cell
# clocked by bus_clk (the flattened names of a few soc registers come from
# top-level nets), and then any logic cell all of whose loads are already
# constrained.  The region holds 69 or so block RAMs on rows y 9, 27 and 45,
# against the 48 the boot ROM and the block RAM need.
X0, Y0, X1, Y1 = 105, 0, 181, 50
REGION = "ae350"
CLOCK = "bus_clk"

ctx.createRectangularRegion(REGION, X0, Y0, X1, Y1)


def clock_net(cell):
    for p in ("CLK", "CLKA", "CLKB"):
        if p in cell.ports and cell.ports[p].net is not None:
            return cell.ports[p].net.name
    return None


fixed_types = ("AE350_SOC", "PLL", "IOB", "IBUF", "OBUF", "TBUF", "IOBUF")
inside = set()
for name, cell in ctx.cells:
    if cell.type in fixed_types or cell.bel is not None:
        continue
    if name.startswith("soc.") or clock_net(cell) == CLOCK:
        inside.add(name)

logic = ("LUT1", "LUT2", "LUT3", "LUT4", "MUX2_LUT5", "MUX2_LUT6", "MUX2_LUT7", "MUX2_LUT8")
for _ in range(4):
    grown = 0
    for name, cell in ctx.cells:
        if name in inside or cell.type not in logic or cell.bel is not None:
            continue
        loads = []
        for pname, port in cell.ports:
            if port.type == PortType.PORT_OUT and port.net is not None:
                loads += [u.cell.name for u in port.net.users]
        if loads and all(l in inside for l in loads):
            inside.add(name)
            grown += 1
    if not grown:
        break

for name in inside:
    ctx.constrainCellToRegion(name, REGION)
print(f"ae350_place: {len(inside)} cells kept in X{X0}..{X1} Y{Y0}..{Y1} beside the AE350")
