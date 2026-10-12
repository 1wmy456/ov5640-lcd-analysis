# Rebuild actual application sources in a new Vitis workspace.
# Usage: xsct scripts/build_blue_tracker_app.tcl <xsa> <new-workspace>
set root [file normalize [file join [file dirname [info script]] ..]]
if {[llength $argv] != 2} {error "Expected XSA and new build workspace"}
set xsa [file normalize [file join $root [lindex $argv 0]]]
set workspace [file normalize [file join $root [lindex $argv 1]]]
if {[string first "${root}/build/" "${workspace}/"] != 0} {error "Workspace must be under build/"}
if {[file exists $workspace]} {error "Use a new workspace; refusing to overwrite"}
file mkdir $workspace
setws $workspace
if {[info exists extra_driver_repository]} {repo -set $extra_driver_repository}
platform create -name board_platform -hw $xsa -proc ps7_cortexa9_0 -os standalone
platform generate
puts [platform report board_platform]
# Compile with the installed Vitis GCC and generated BSP. This also avoids the
# Eclipse Empty Application template service, which hung on this host.
set bsp [file join $workspace board_platform ps7_cortexa9_0 standalone_domain bsp ps7_cortexa9_0]
puts [exec python [file join $root scripts compile_blue_tracker_app.py] --bsp $bsp --out [file join $workspace app_compiled] 2>@1]
puts "BOARD_APP: PASS application rebuilt in $workspace"
