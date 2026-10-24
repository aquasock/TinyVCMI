# core.pclk is the flattened name of the memory clock net
create_clock -name clk50 -period 20.000 [get_ports {sys_clk}]
create_clock -name clk400 -period 2.500 [get_nets {mclk}]
create_clock -name pclk -period 10.000 [get_nets {core.pclk}]
