# Post-route audit in an isolated build, no original project edits.
set root [file normalize [file join [file dirname [info script]] ..]]
if {[llength $argv]!=1} {error "Expected build/<touch-project>"}
set folder [file normalize [file join $root [lindex $argv 0]]]
if {[string first "${root}/build/" "${folder}/"]!=0} {error "Only isolated build copies"}
open_project [file join $folder ov5640_lcd.xpr]
open_run impl_1
set f [open [file join $folder board_reports touch_pins.txt] w]
foreach {bit package} {0 R19 1 P20 2 M19 3 U19} {
 set name [format {touch_io_tri_io[%d]} $bit]
 set p [get_ports $name]
 if {[llength $p]!=1||[get_property PACKAGE_PIN $p] ne $package||[get_property IOSTANDARD $p] ne "LVCMOS33"} {error "Touch pin mismatch $name"}
 if {[llength [get_ports -filter "PACKAGE_PIN == $package"]]!=1} {error "Duplicate package pin $package"}
 puts $f "$name pin=$package standard=[get_property IOSTANDARD $p] bank=[get_property BANK [get_package_pins $package]] pullup=[get_property PULLUP $p]"
}
close $f
close_design
open_bd_design [get_files */system.bd]
if {[get_property OFFSET [get_bd_addr_segs processing_system7_0/Data/SEG_touch_gpio_Reg]]!=0x43C30000} {error "Touch address changed"}
if {[get_property CONFIG.C_HAS_ASYNC_CLK [get_bd_cells v_vid_in_axi4s_0]]!=1} {error "Native camera CDC changed"}
foreach {prop value} {IMAGE_WIDTH 800 IMAGE_HEIGHT 480 MODE 2 BLUE_MIN 80 BR_DELTA 60 BG_DELTA 35 MIN_B_R_RATIO 2 MIN_BLUE_RUN 3 MIN_PIXELS 256 COMPONENT_MODE 1 BORDER_WIDTH 2 CENTER_CROSS 0} {
 if {[get_property CONFIG.$prop [get_bd_cells axis_blue_tracker_0]]!=$value} {error "Calibration mismatch $prop"}
}
validate_bd_design
close_project
puts "TOUCH_AUDIT: PASS pins/address/calibration/native_CDC"
