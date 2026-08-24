### IO Placement

## Clock signal (100 MHz)
# set_property -dict { PACKAGE_PIN R2    IOSTANDARD  SSTL135 } [get_ports { clk_osc }]; 
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { clk_osc }]; #IO_L13P_T2_MRCC_15 Sch=uclk

## USB-UART Interface
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]; 
set_property -dict { PACKAGE_PIN V12    IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]; 

## LEDs
set_property -dict { PACKAGE_PIN E18    IOSTANDARD LVCMOS33 } [get_ports { led[0] }]; 
set_property -dict { PACKAGE_PIN F13    IOSTANDARD LVCMOS33 } [get_ports { led[1] }]; 
set_property -dict { PACKAGE_PIN E13    IOSTANDARD LVCMOS33 } [get_ports { led[2] }]; 
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { led[3] }]; 

