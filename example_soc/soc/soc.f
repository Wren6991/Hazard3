# SoC integration file

file example_soc.v

# CPU + debug components

list $HDL/hazard3.f
list $HDL/debug/dtm/hazard3_jtag_dtm.f
list $HDL/debug/dm/hazard3_dm.f

# Generic SoC components from libfpga

file ../libfpga/common/reset_sync.v

list ../libfpga/peris/uart/uart.f
list ../libfpga/peris/spi_03h_xip/spi_03h_xip.f
list ../libfpga/mem/ahb_cache.f
list ../libfpga/mem/ahb_sync_sram.f

list ../libfpga/busfabric/ahbl_crossbar.f
file ../libfpga/busfabric/ahbl_to_apb.v
file ../libfpga/busfabric/apb_splitter.v

