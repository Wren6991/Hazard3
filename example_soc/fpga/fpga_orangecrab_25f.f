file fpga_orangecrab_25f.v
file ../libfpga/common/reset_sync.v
file ../libfpga/common/fpga_reset.v

list ../soc/soc.f

# ECP5 DTM is not in main SoC list because the JTAGG primitive doesn't exist
# on most platforms
list ../../hdl/debug/dtm/hazard3_ecp5_jtag_dtm.f

