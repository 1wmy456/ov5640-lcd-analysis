set saved_argv $argv
source [file join [file dirname [info script]] audit_touch_stage_a.tcl]
set argv $saved_argv
open_project [file join $folder ov5640_lcd.xpr]
open_bd_design [get_files */system.bd]
if {[get_property CONFIG.TOUCH_MODE [get_bd_cells pan_tilt_ctrl_0]]!=1} {error "Raw result provenance guard disabled"}
if {[get_property OFFSET [get_bd_addr_segs processing_system7_0/Data/SEG_raw_capture_dma_Reg]]!=0x43C40000} {error "Wrong raw DMA address"}
foreach a {result_frame_id result_valid result_pulse} b {raw_result_frame raw_result_valid raw_result_pulse} {
 if {[get_bd_nets -of_objects [get_bd_pins axis_raw_capture_0/$a]] ne [get_bd_nets -of_objects [get_bd_pins pan_tilt_ctrl_0/$b]]} {error "Raw provenance disconnected $a"}
}
foreach pin {axis_raw_capture_0/aclk raw_capture_dma/s_axi_lite_aclk raw_capture_dma/m_axi_s2mm_aclk} {
 if {[get_bd_nets -of_objects [get_bd_pins $pin]] ne [get_bd_nets -of_objects [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk]]} {error "Capture domain differs $pin"}
}
close_project
puts "TOUCH_TRACKING_AUDIT: PASS raw DMA/address/clock/frame provenance; calibrated video and pins preserved"
