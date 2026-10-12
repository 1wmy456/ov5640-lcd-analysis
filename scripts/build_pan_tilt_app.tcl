set pan_root [file normalize [file join [file dirname [info script]] ..]]
set extra_driver_repository [file join $pan_root sw_repo]
source [file join $pan_root scripts build_blue_tracker_app.tcl]
