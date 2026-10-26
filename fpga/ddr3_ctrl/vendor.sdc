create_clock -name clk50 -period 20.000 [get_ports {sys_clk}]
create_clock -name clk400 -period 2.500 [get_nets {mclk}]
create_clock -name pclk -period 10.000 [get_nets {pclk}]
set_clock_groups -exclusive -group [get_clocks {clk400}] -group [get_clocks {clk50}] -group [get_clocks {pclk}]
