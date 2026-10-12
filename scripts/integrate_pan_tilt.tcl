# Fresh copy from the original project, with all accepted calibration values explicit.
set pan_root [file normalize [file join [file dirname [info script]] ..]]
set pan_out build/pan_tilt_tracking
set pan_apply 0
for {set i 0} {$i<[llength $argv]} {incr i} {
    set k [lindex $argv $i]
    if {$k eq "-apply"} {set pan_apply 1} elseif {$k eq "-out"} {
        incr i;set pan_out [lindex $argv $i]
    } else {error "Unknown pan-tilt argument $k"}
}
puts "PAN PLAN: MODE2 800x480, blue=80/60/35 ratio=2 run=3 count=256 border=2 cross=0"
puts "PAN PLAN: new AXI-Lite 0x43C20000/4K; J4-3 U5 yaw, J4-4 T5 pitch, reset PWM OFF"
if {!$pan_apply} {puts "Review only; use -apply -out build/<new-copy>";return}
set argv [list -apply -out $pan_out -width 800 -height 480 -mode 2 -blue_min 80 -br_delta 60 -bg_delta 35 -red_ratio 2 -min_run 3 -min_pixels 256]
source [file join $pan_root scripts integrate_blue_tracker.tcl]
set pan_folder [file normalize [file join $pan_root $pan_out]]
set pan_ip [file join $pan_folder ip_repo pan_tilt_ctrl]
create_project pan_ip_pack [file join $pan_folder ip_pack_project] -part xc7z020clg400-2
add_files [glob [file join $pan_folder rtl pan_tilt *.v]]
set_property top pan_tilt_ctrl [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $pan_ip -vendor user.org -library user -taxonomy /UserIP -import_files
set core [ipx::current_core]
set_property name pan_tilt_ctrl $core
set_property version 1.0 $core
set_property display_name {Pan Tilt PWM and Blue Tracker Snapshot} $core
set bus [ipx::get_bus_interfaces S_AXI -of_objects $core]
if {[llength $bus]!=1} {error "AXI bus inference failed"}
set proto [ipx::get_bus_parameters PROTOCOL -of_objects $bus]
if {![llength $proto]} {set proto [ipx::add_bus_parameter PROTOCOL $bus]}
set_property value AXI4LITE $proto
set map [ipx::get_memory_maps S_AXI -of_objects $core]
if {![llength $map]} {set map [ipx::add_memory_map S_AXI $core]}
set block [ipx::get_address_blocks Reg -of_objects $map]
if {![llength $block]} {set block [ipx::add_address_block Reg $map]}
set_property -dict {base_address 0 range 4096 width 32 usage register} $block
set bp [ipx::add_address_block_parameter OFFSET_BASE_PARAM $block]
set_property value C_S_AXI_BASEADDR $bp
set hp [ipx::add_address_block_parameter OFFSET_HIGH_PARAM $block]
set_property value C_S_AXI_HIGHADDR $hp
set_property slave_memory_map_ref S_AXI $bus
foreach name {C_S_AXI_BASEADDR C_S_AXI_HIGHADDR} {
    set par [ipx::get_user_parameters $name -of_objects $core]
    set_property value_format long $par
}
ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core
close_project
open_project [file join $pan_folder ov5640_lcd.xpr]
set_property ip_repo_paths [list [file join $pan_folder ip_repo rgb2lcd] [file join $pan_folder ip_repo ov5640_capture_data] $pan_ip] [current_project]
update_ip_catalog
open_bd_design [file join $pan_folder ov5640_lcd.srcs sources_1 bd system system.bd]
# Reject any overlapping segment before assigning the new register range.
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
    set lo [get_property OFFSET $seg];set sz [get_property RANGE $seg]
    if {$lo < 0x43C21000 && $lo+$sz > 0x43C20000} {error "Address conflicts with $seg"}
}
set_property CONFIG.NUM_MI 5 [get_bd_cells ps7_0_axi_periph]
create_bd_cell -type ip -vlnv user.org:user:pan_tilt_ctrl:1.0 pan_tilt_ctrl_0
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M04_AXI] [get_bd_intf_pins pan_tilt_ctrl_0/S_AXI]
foreach pin {pan_tilt_ctrl_0/s_axi_aclk ps7_0_axi_periph/M04_ACLK} {
    connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins $pin]
}
foreach pin {pan_tilt_ctrl_0/s_axi_aresetn ps7_0_axi_periph/M04_ARESETN} {
    connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins $pin]
}
foreach pin {bbox_valid result_pulse frame_error bbox_xmin bbox_xmax bbox_ymin bbox_ymax blue_pixel_count} {
    connect_bd_net [get_bd_pins axis_blue_tracker_0/$pin] [get_bd_pins pan_tilt_ctrl_0/$pin]
}
foreach pin {servo_yaw_pwm servo_pitch_pwm} {
    create_bd_port -dir O $pin
    connect_bd_net [get_bd_pins pan_tilt_ctrl_0/$pin] [get_bd_ports $pin]
}
assign_bd_address -offset 0x43C20000 -range 4K -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs pan_tilt_ctrl_0/S_AXI/Reg]
file copy [file join $pan_root constraints pan_tilt.xdc] [file join $pan_folder ov5640_lcd.srcs constrs_1 new pan_tilt.xdc]
add_files -fileset constrs_1 [file join $pan_folder ov5640_lcd.srcs constrs_1 new pan_tilt.xdc]
set_property -dict {CONFIG.BORDER_WIDTH 2 CONFIG.CENTER_CROSS 0} [get_bd_cells axis_blue_tracker_0]
validate_bd_design
save_bd_design
write_bd_tcl [file join $pan_folder system_pan_tilt.tcl]
set fp [open [file join $pan_folder pan_tilt_summary.txt] w]
puts $fp "MODE2 800x480 BLUE_MIN=80 BR_DELTA=60 BG_DELTA=35 MIN_B_R_RATIO=2 MIN_BLUE_RUN=3 MIN_PIXELS=256 BORDER_WIDTH=2 CENTER_CROSS=0"
puts $fp "AXI-Lite address: [get_property OFFSET [get_bd_addr_segs processing_system7_0/Data/SEG_pan_tilt_ctrl_0_Reg]]; clock100MHz; reset disabled PWM"
puts $fp "J4-3 U5 yaw; J4-4 T5 pitch; actual package/bank check during full implementation"
close $fp
close_project
puts "PAN_INTEGRATION: PASS $pan_folder"
