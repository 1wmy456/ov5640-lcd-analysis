# Review by default. Create a fresh calibrated component/PD hardware copy.
set touch_root [file normalize [file join [file dirname [info script]] ..]]
set touch_out build/touch_stage_a
set touch_apply 0
for {set i 0} {$i<[llength $argv]} {incr i} {
 set k [lindex $argv $i]
 if {$k eq "-apply"} {set touch_apply 1} elseif {$k eq "-out"} {incr i;set touch_out [lindex $argv $i]} else {error "Unknown argument $k"}
}
puts "TOUCH PLAN: independent 4-bit AXI GPIO + frame-latched AXIS cross; 0x43C30000; R19 P20 M19 U19"
if {!$touch_apply} {puts "Review only. -apply -out build/<fresh-copy>";return}
set argv [list -apply -components -out $touch_out]
source [file join $touch_root scripts integrate_pan_tilt.tcl]
set touch_folder [file normalize [file join $touch_root $touch_out]]
open_project [file join $touch_folder ov5640_lcd.xpr]
open_bd_design [get_files */system.bd]
# Address must be free; preserve existing IP locations.
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
 set lo [get_property OFFSET $seg];set span [get_property RANGE $seg]
 if {$lo ne "" && $span ne "" && [expr {$lo <= 0x43C3ffff && $lo+$span>0x43C30000}]} {error "Touch address occupied by $seg"}
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 touch_gpio
set_property -dict {CONFIG.C_GPIO_WIDTH 4 CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_DOUT_DEFAULT 0x00000000 CONFIG.C_TRI_DEFAULT 0xffffffff CONFIG.C_DOUT_DEFAULT_2 0x00000000} [get_bd_cells touch_gpio]
if {[get_property CONFIG.NUM_MI [get_bd_cells ps7_0_axi_periph]]!=5} {error "Unexpected AXI master count"}
set_property CONFIG.NUM_MI 6 [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M05_AXI] [get_bd_intf_pins touch_gpio/S_AXI]
foreach p {touch_gpio/s_axi_aclk ps7_0_axi_periph/M05_ACLK} {connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins $p]}
foreach p {touch_gpio/s_axi_aresetn ps7_0_axi_periph/M05_ARESETN} {connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins $p]}
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:gpio_rtl:1.0 touch_io
connect_bd_intf_net [get_bd_intf_pins touch_gpio/GPIO] [get_bd_intf_ports touch_io]
assign_bd_address -offset 0x43C30000 -range 64K -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs touch_gpio/S_AXI/Reg]
file mkdir [file join $touch_folder rtl touch]
file copy -force [file join $touch_root rtl touch axis_touch_cross.v] [file join $touch_folder rtl touch axis_touch_cross.v]
add_files -norecurse [file join $touch_folder rtl touch axis_touch_cross.v]
update_compile_order -fileset sources_1
create_bd_cell -type module -reference axis_touch_cross axis_touch_cross_0
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_touch_cross_0/aclk]
connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins axis_touch_cross_0/aresetn]
connect_bd_net [get_bd_pins touch_gpio/gpio2_io_o] [get_bd_pins axis_touch_cross_0/marker]
set old [get_bd_intf_nets -of_objects [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]]
disconnect_bd_intf_net $old [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
connect_bd_intf_net [get_bd_intf_pins axis_blue_tracker_0/M_AXIS] [get_bd_intf_pins axis_touch_cross_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_touch_cross_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
file copy [file join $touch_root constraints touch.xdc] [file join $touch_folder ov5640_lcd.srcs constrs_1 new touch.xdc]
add_files -fileset constrs_1 [file join $touch_folder ov5640_lcd.srcs constrs_1 new touch.xdc]
validate_bd_design
save_bd_design
write_bd_tcl [file join $touch_folder system_touch.tcl]
close_project
puts "TOUCH_INTEGRATION: PASS $touch_folder"
