# Diagnostic immutable snapshot: halt PS, let the one-shot DMA finish, then read DDR.
# All servo outputs must already be disabled. Resumes PS even if extraction fails.
if {[llength $argv]!=2} {error "Expected ELF raw symbol address and output binary"}
set address [lindex $argv 0]
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
if {[expr {[mrd -force -value 0x43c20008]}]!=0} {error "Disable PWM before raw diagnostics"}
stop
set result [catch {
 after 150
 set status [expr {[mrd -force -value 0x43c40034]}]
 set tail [expr {[mrd -force -value [expr {$address+800*480*4-4}]]}]
 if {($status&0x4070)||(($tail>>24)&255)!=0} {error "No complete raw frame available status=$status tail=$tail"}
 mrd -force -bin -file [lindex $argv 1] $address [expr {800*480}]
 puts "RAW_DIAGNOSTIC: PASS complete held DDR packet, PS temporarily halted; not a displayed-frame match"
} message]
con
disconnect
if {$result} {error $message}
