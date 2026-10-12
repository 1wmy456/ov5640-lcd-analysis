# Read-only enumeration: does not reset, halt, or program a device.
open_hw_manager
if {[catch {connect_hw_server} message]} {
    puts "BOARD_PROBE: hardware server connection failed: $message"
    close_hw_manager
    exit 2
}
set targets [get_hw_targets -quiet]
puts "BOARD_PROBE: targets=[llength $targets]"
foreach target $targets {
    puts "BOARD_PROBE: target=$target"
    if {[catch {open_hw_target $target} message]} {
        puts "BOARD_PROBE: open failed: $message"
        continue
    }
    foreach device [get_hw_devices -quiet] {
        puts "BOARD_PROBE: device=$device part=[get_property PART $device]"
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
