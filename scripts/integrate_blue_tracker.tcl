# Vivado 2020.2: review by default; -apply creates an isolated, self-contained copy.
# Example: vivado -mode batch -source scripts/integrate_blue_tracker.tcl \
#   -tclargs -apply -width 800 -height 480 -mode 2 -out build/blue_tracker_vivado
set root [file normalize [file join [file dirname [info script]] ..]]
array set opt {-apply 0 -width 0 -height 0 -mode 2 -out build/blue_tracker_vivado -blue_min 80 -br_delta 35 -bg_delta 20 -min_pixels 24 -min_run 1 -red_ratio 0 -bbox_filter 0 -component_mode 0}
for {set i 0} {$i < [llength $argv]} {incr i} {
    set key [lindex $argv $i]
    if {$key eq "-apply"} {set opt($key) 1; continue}
    if {![info exists opt($key)] || $i+1 >= [llength $argv]} {error "Unknown or missing argument: $key"}
    incr i; set opt($key) [lindex $argv $i]
}
puts "PLAN: copy original project, add RTL module reference, insert Video In -> tracker -> S2MM."
puts "PLAN: reuse original 100MHz stream clock and VDMA active-low reset; preserve native CDC, LCD, GPIO, DDR, XDC."
puts "PLAN: width=$opt(-width) height=$opt(-height) MODE=$opt(-mode); no original BD overwrite."
if {!$opt(-apply)} {puts "REVIEW ONLY: use -apply with the active camera resolution to create the copy."; return}
foreach k {-width -height} {
    if {![string is integer -strict $opt($k)] || $opt($k) < 1 || $opt($k) > 65535} {error "Explicit $k in 1..65535 required"}
}
if {$opt(-width)*$opt(-height) > 4294967295} {error "Pixel counter overflow"}
if {$opt(-mode) ni {0 1 2}} {error "MODE must be 0, 1, or 2"}
foreach k {-blue_min -br_delta -bg_delta -red_ratio} {
    if {![string is integer -strict $opt($k)] || $opt($k)<0 || $opt($k)>255} {error "Invalid $k"}
}
if {![string is integer -strict $opt(-min_run)] || $opt(-min_run)<1 || $opt(-min_run)>$opt(-width)} {error "Invalid minimum run"}
if {![string is integer -strict $opt(-min_pixels)] || $opt(-min_pixels)<1 || $opt(-min_pixels)>$opt(-width)*$opt(-height)} {error "Invalid minimum pixels"}
if {![string is integer -strict $opt(-bbox_filter)] || $opt(-bbox_filter)<0 || $opt(-bbox_filter)>4} {error "Invalid bbox filter shift"}
if {$opt(-component_mode) ni {0 1}} {error "Invalid component mode"}
if {$opt(-component_mode) && ($opt(-width)%4 || $opt(-height)%4 || (($opt(-width)/4)*($opt(-height)/4)+31)/32>896)} {error "Mask dimensions exceed 4KB register aperture"}
set out [file normalize [file join $root $opt(-out)]]
# Existing directory is never overwritten, even after a failed previous attempt.
if {[file exists $out]} {error "Output already exists: $out. Use a new -out directory to rerun safely."}
if {[string first "${root}/build/" "${out}/"] != 0} {error "Output must be a new directory under repository build/"}
file mkdir $out
foreach name {ov5640_lcd.xpr ov5640_lcd.srcs ip_repo} {file copy [file join $root $name] $out}
file copy [file join $root rtl] $out
cd $out
open_project [file join $out ov5640_lcd.xpr]
# Replace the original XPR's missing generated wrapper entry with its bundled copy.
foreach f [get_files -quiet *system_wrapper.v] {remove_files $f}
add_files -norecurse [file join $out ov5640_lcd.srcs sources_1 imports system_wrapper.v]
set_property ip_repo_paths [list [file join $out ip_repo rgb2lcd] [file join $out ip_repo ov5640_capture_data]] [current_project]
update_ip_catalog
add_files -norecurse [glob [file join $out rtl blue_tracker *.v]]
update_compile_order -fileset sources_1
open_bd_design [file join $out ov5640_lcd.srcs sources_1 bd system system.bd]
set src [get_bd_intf_pins v_vid_in_axi4s_0/video_out]
set dst [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
set oldnet [get_bd_intf_nets -of_objects $src]
if {[llength $oldnet]!=1 || $oldnet ne [get_bd_intf_nets -of_objects $dst] ||
    [llength [get_bd_intf_pins -of_objects $oldnet]]!=2} {error "Original direct stream connection was changed; refuse to rewire"}
foreach pin [list $src $dst] {
    if {[get_property CONFIG.TDATA_NUM_BYTES $pin] != 3 || [get_property CONFIG.TUSER_WIDTH $pin] != 1} {
        error "Unexpected video interface width at $pin"
    }
}
if {[get_property CONFIG.C_HAS_ASYNC_CLK [get_bd_cells v_vid_in_axi4s_0]] != 1} {error "Native video CDC must remain enabled"}
set clocknet [get_bd_nets -of_objects [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk]]
if {$clocknet ne [get_bd_nets -of_objects [get_bd_pins v_vid_in_axi4s_0/aclk]]} {error "Stream clocks differ"}
if {[get_property CONFIG.FREQ_HZ [get_bd_pins v_vid_in_axi4s_0/aclk]] != 100000000} {error "Expected 100MHz video AXI clock"}
set resetnet [get_bd_nets -of_objects [get_bd_pins axi_vdma_0/axi_resetn]]
create_bd_cell -type module -reference axis_blue_tracker axis_blue_tracker_0
set_property -dict [list CONFIG.IMAGE_WIDTH $opt(-width) CONFIG.IMAGE_HEIGHT $opt(-height) CONFIG.MODE $opt(-mode) \
    CONFIG.BLUE_MIN $opt(-blue_min) CONFIG.BR_DELTA $opt(-br_delta) CONFIG.BG_DELTA $opt(-bg_delta) \
    CONFIG.MIN_PIXELS $opt(-min_pixels) CONFIG.MIN_BLUE_RUN $opt(-min_run) CONFIG.MIN_B_R_RATIO $opt(-red_ratio) \
    CONFIG.BBOX_FILTER_SHIFT $opt(-bbox_filter) CONFIG.COMPONENT_MODE $opt(-component_mode) \
    CONFIG.MASK_BLOCK 4 CONFIG.MASK_CELL_MIN 4] [get_bd_cells axis_blue_tracker_0]
connect_bd_net [get_bd_pins axi_vdma_0/s_axis_s2mm_aclk] [get_bd_pins axis_blue_tracker_0/aclk]
connect_bd_net [get_bd_pins axi_vdma_0/axi_resetn] [get_bd_pins axis_blue_tracker_0/aresetn]
disconnect_bd_intf_net $oldnet $dst
connect_bd_intf_net $src [get_bd_intf_pins axis_blue_tracker_0/S_AXIS]
connect_bd_intf_net [get_bd_intf_pins axis_blue_tracker_0/M_AXIS] $dst
validate_bd_design
save_bd_design
write_bd_tcl [file join $out system_with_blue_tracker.tcl]
set fp [open [file join $out integration_summary.txt] w]
puts $fp "Validate Design passed; resolution=$opt(-width)x$opt(-height) MODE=$opt(-mode)"
puts $fp "thresholds: B>=$opt(-blue_min), BR>$opt(-br_delta), BG>$opt(-bg_delta), red_ratio=$opt(-red_ratio), min_run=$opt(-min_run), min_pixels=$opt(-min_pixels), bbox_filter_shift=$opt(-bbox_filter)"
puts $fp "component_mode=$opt(-component_mode); mask_block=4; mask_cell_min=4"
puts $fp "Original files untouched; copied project: [file join $out ov5640_lcd.xpr]"
close $fp
close_project
puts "PASS: isolated BD integration and validation: $out"
