# Standalone out-of-context resource/timing estimate, NOT board/full-system closure.
set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build blue_tracker_ooc]
file mkdir $out
create_project -in_memory -part xc7z020clg400-2
read_verilog [glob [file join $root rtl blue_tracker *.v]]
synth_design -top axis_blue_tracker -mode out_of_context -part xc7z020clg400-2
create_clock -name axis_clk -period 10.000 [get_ports aclk]
set_input_delay 1.000 -clock axis_clk [get_ports -filter {DIRECTION == IN && NAME != aclk && NAME != aresetn}]
set_output_delay 1.000 -clock axis_clk [get_ports -filter {DIRECTION == OUT}]
set_false_path -from [get_ports aresetn]
opt_design
place_design
route_design
report_utilization -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing_summary.rpt]
report_drc -file [file join $out drc.rpt]
write_checkpoint -force [file join $out routed.dcp]
puts "PASS: standalone OOC reports generated; no full-system timing claim."
