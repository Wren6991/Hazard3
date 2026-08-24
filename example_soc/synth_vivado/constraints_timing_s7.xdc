### Timing

# 12 MHz board oscillator
create_clock -add -name clk_osc -period 83.333 -waveform {0 41.666} [get_ports { clk_osc }];
# 30 MHz JTAG input
create_clock -add -name tck -period 33.333 [get_pins soc_u/dtm_u/bscan_dtmcs/TCK]
# Label the PLL output for constraints (Vivado should infer its period)
create_generated_clock -name clk_sys [get_nets clk_sys]

# These paths should all be handled by bus CDC in DTM, so 2-dest-cycle maxdelay is sufficient
set_max_delay -datapath_only -from [get_clocks tck]     -to [get_clocks clk_sys] 25.000
set_max_delay -datapath_only -from [get_clocks clk_sys] -to [get_clocks tck]     66.666

# Unimportant as it's asynchronous
set_false_path -through [get_ports uart_rx]
set_false_path -through [get_ports uart_tx]

# Status outputs -- don't care
set_false_path -through [get_ports led]

