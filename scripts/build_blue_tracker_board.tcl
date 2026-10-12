# Build a previously isolated integration copy; never use the original project.
# -tclargs build/tracker_board_mode0
set root [file normalize [file join [file dirname [info script]] ..]]
if {[llength $argv] != 1} {error "Usage: -tclargs build/<integrated-copy>"}
set folder [file normalize [file join $root [lindex $argv 0]]]
if {[string first "${root}/build/" "${folder}/"] != 0} {error "Only build/ copies may be built"}
if {![file exists [file join $folder integration_summary.txt]]} {error "Integration/validation marker missing"}
cd $folder
open_project [file join $folder ov5640_lcd.xpr]
set bd [get_files */system.bd]
open_bd_design $bd
validate_bd_design
generate_target all $bd
set wrapper [make_wrapper -files $bd -top]
foreach f [get_files -quiet *system_wrapper.v] {remove_files $f}
add_files -norecurse $wrapper
set_property top system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"}
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed: [get_property STATUS [get_runs impl_1]]"}
open_run impl_1
file mkdir board_reports
report_timing_summary -report_unconstrained -file board_reports/timing_summary.rpt
report_utilization -file board_reports/utilization.rpt
report_drc -file board_reports/drc.rpt
report_cdc -file board_reports/cdc.rpt
set failing [get_timing_paths -quiet -delay_type max -slack_lesser_than 0 -max_paths 1]
if {[llength $failing]} {error "Setup timing failed; inspect board_reports before programming"}
set failing [get_timing_paths -quiet -delay_type min -slack_lesser_than 0 -max_paths 1]
if {[llength $failing]} {error "Hold timing failed; inspect board_reports before programming"}
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Bitstream failed: [get_property STATUS [get_runs impl_1]]"}
open_run impl_1
write_hw_platform -fixed -include_bit -force -file [file join $folder system_wrapper.xsa]
puts "BOARD_BUILD: PASS project=$folder"
close_project
