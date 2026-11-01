# Stage B transport only: raw one-shot DMA, keeping all accepted video/PWM IP.
set cap_root [file normalize [file join [file dirname [info script]] ..]]
set cap_out build/touch_capture
set cap_apply 0
for {set i 0} {$i<[llength $argv]} {incr i} {
 set k [lindex $argv $i]
 if {$k eq "-apply"} {set cap_apply 1} elseif {$k eq "-out"} {incr i;set cap_out [lindex $argv $i]} else {error "Unknown argument $k"}
}
puts "RAW PLAN: pre-overlay one-shot full RGB frame -> AXI DMA -> PS-owned buffer; no VDMA reconfiguration"
if {!$cap_apply} {puts "Review only";return}
set argv [list -apply -out $cap_out]
source [file join $cap_root scripts integrate_touch_selection.tcl]
set cap_folder [file normalize [file join $cap_root $cap_out]]
open_project [file join $cap_folder ov5640_lcd.xpr]
open_bd_design [get_files */system.bd]
foreach seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data]] {
 set lo [get_property OFFSET $seg];set span [get_property RANGE $seg]
 if {$lo ne ""&&$span ne ""&&[expr {$lo<=0x43c4ffff&&$lo+$span>0x43c40000}]} {error "Capture address occupied $seg"}
}
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma:7.1 raw_capture_dma
set_property -dict {CONFIG.c_include_sg 0 CONFIG.c_include_mm2s 0 CONFIG.c_include_s2mm 1 CONFIG.c_s_axis_s2mm_tdata_width 32 CONFIG.c_m_axi_s2mm_data_width 64 CONFIG.c_sg_length_width 23 CONFIG.c_s2mm_burst_size 16} [get_bd_cells raw_capture_dma]
set_property CONFIG.NUM_MI 7 [get_bd_cells ps7_0_axi_periph]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M06_AXI] [get_bd_intf_pins raw_capture_dma/S_AXI_LITE]
set_property CONFIG.NUM_SI 3 [get_bd_cells axi_mem_intercon]
connect_bd_intf_net [get_bd_intf_pins raw_capture_dma/M_AXI_S2MM] [get_bd_intf_pins axi_mem_intercon/S02_AXI]
foreach p {raw_capture_dma/s_axi_lite_aclk raw_capture_dma/m_axi_s2mm_aclk ps7_0_axi_periph/M06_ACLK axi_mem_intercon/S02_ACLK} {connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins $p]}
foreach p {raw_capture_dma/axi_resetn ps7_0_axi_periph/M06_ARESETN axi_mem_intercon/S02_ARESETN} {connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins $p]}
assign_bd_address -offset 0x43C40000 -range 64K -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs raw_capture_dma/S_AXI_LITE/Reg]
assign_bd_address -offset 0 -range 1G -target_address_space [get_bd_addr_spaces raw_capture_dma/Data_S2MM] [get_bd_addr_segs processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM]
add_files -norecurse [file join $cap_folder rtl touch axis_raw_capture.v]
update_compile_order -fileset sources_1
create_bd_cell -type module -reference axis_raw_capture axis_raw_capture_0
set_property CONFIG.TOUCH_MODE 1 [get_bd_cells pan_tilt_ctrl_0]
foreach pin {result_frame_id result_valid result_pulse} target {raw_result_frame raw_result_valid raw_result_pulse} {
 connect_bd_net [get_bd_pins axis_raw_capture_0/$pin] [get_bd_pins pan_tilt_ctrl_0/$target]
}
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_raw_capture_0/aclk]
connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins axis_raw_capture_0/aresetn]
connect_bd_net [get_bd_pins touch_gpio/gpio2_io_o] [get_bd_pins axis_raw_capture_0/control]
set old [get_bd_intf_nets -of_objects [get_bd_intf_pins axis_blue_tracker_0/S_AXIS]]
disconnect_bd_intf_net $old [get_bd_intf_pins axis_blue_tracker_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins v_vid_in_axi4s_0/video_out] [get_bd_intf_pins axis_raw_capture_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_raw_capture_0/M_AXIS] [get_bd_intf_pins axis_blue_tracker_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_raw_capture_0/CAPTURE] [get_bd_intf_pins raw_capture_dma/S_AXIS_S2MM]
validate_bd_design
save_bd_design
write_bd_tcl [file join $cap_folder system_touch_capture.tcl]
close_project
puts "TOUCH_CAPTURE_INTEGRATION: PASS $cap_folder"
