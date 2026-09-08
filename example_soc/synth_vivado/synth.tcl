source filelist.tcl

# Determine part based on constraints file
if {[info exists CONSTRAINTS_IO] && [string match "*_s7.xdc" $CONSTRAINTS_IO]} {
	set PART xc7s50csga324-1
} else {
	set PART xc7a100tcsg324-1
}

set TOP fpga

# Use BITFILE from Makefile if defined, otherwise default
if {![info exists BITFILE]} {
	set BITFILE fpga.bit
}

proc checkpoint_and_report {stage} {
	write_checkpoint -force ${stage}.dcp
	report_timing_summary -file ${stage}_timing.rpt
	report_utilization -file ${stage}_util.rpt
	report_timing_summary -no_detailed_paths
}

add_files $FILES
read_xdc $CONSTRAINTS_TIMING

synth_design -include_dirs $INCDIRS -part $PART -top $TOP \
	-verilog_define HAZARD3_REGFILE_RAM_STYLE_DISTRIBUTED \
	-directive PerformanceOptimized
checkpoint_and_report synth

read_xdc $CONSTRAINTS_IO
place_design -directive Explore
checkpoint_and_report place

route_design -directive Explore
phys_opt_design -directive Explore
checkpoint_and_report route

write_bitstream -force $BITFILE
