# Read-only current hardware profile. Never halt/reset or write an AXI register.
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
set base 0x43c20000
if {[expr {[mrd -force -value $base]}]!=0x50544c54} {error "Peripheral ID mismatch"}
foreach {label offset} {
 enable 0x08 yaw_us 0x14 pitch_us 0x18 yaw_min 0x1c yaw_max 0x20
 pitch_min 0x24 pitch_max 0x28 yaw_center 0x2c pitch_center 0x30
} {
 puts "PROFILE $label=[expr {[mrd -force -value [expr {$base+$offset}]]}]"
}
disconnect
