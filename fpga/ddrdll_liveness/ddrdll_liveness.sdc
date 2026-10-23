create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]
create_clock -name pll_clk -period 2.857 [get_nets {pll_clk}]
