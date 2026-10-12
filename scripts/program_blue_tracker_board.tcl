# Volatile JTAG bring-up: no QSPI/SD/flash writes.
# xsct scripts/program_blue_tracker_board.tcl <bit> <ps7_init.tcl> <elf>
if {[llength $argv] != 3} {error "Expected BIT, PS initialization Tcl, and ELF"}
foreach file $argv {if {![file exists $file]} {error "Artifact not found: $file"}}
connect -url tcp:127.0.0.1:3121
if {[catch {targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}}]} {
    # A failed AXI memory access can leave DAP sticky error state; system reset
    # restores target enumeration before starting the authorized bring-up.
    targets -set -filter {name =~ "DAP*"}
    rst -system
    after 1000
}
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
stop
rst -system
after 1000
targets -set -filter {name =~ "xc7z020"}
fpga -file [lindex $argv 0]
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
source [lindex $argv 1]
ps7_init
ps7_post_config
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
dow [lindex $argv 2]
con
after 3000
puts "BOARD_PROGRAM: JTAG download and application start completed"
disconnect
