set_device GW5AST-LV138PG484AC1/I0 -device_version C
add_file -type verilog top.v
add_file -type cst top.cst
add_file -type sdc top.sdc
set_option -top_module top
set_option -output_base_name ddrdll_oracle
set_option -verilog_std v2001
set_option -timing_driven 1
set_option -gen_text_timing_rpt 1
set_option -gen_sdf 1
set_option -gen_verilog_sim_netlist 1
set_option -use_cpu_as_gpio 1
set_option -bit_compress 0
run all
