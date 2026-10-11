# Run in the Vivado 2020.2 Tcl console from any directory.
set project_root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $project_root ov5640_lcd.xpr]
set_property ip_repo_paths [list [file join $project_root ip_repo rgb2lcd] [file join $project_root ip_repo ov5640_capture_data]] [current_project]
update_ip_catalog
puts "Project opened with bundled custom IP. Validate BD and regenerate output products before building."
