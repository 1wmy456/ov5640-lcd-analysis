# Same C command parser as UART. No direct PWM/verification bypass.
if {[llength $argv]!=2} {error "Expected generated BSP address and one command"}
set base [lindex $argv 0]
set command [lindex $argv 1]
if {[string length $command]>31} {error "Mailbox command maximum is 31 ASCII characters"}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
proc read_reg {offset} {
    global base
    return [expr {[mrd -force -value [expr {$base+$offset}]]}]
}
proc write_reg {offset value} {
    global base
    mwr -force [expr {$base+$offset}] $value
}
if {[read_reg 0]!=0x50544c54} {error "Peripheral ID mismatch"}
if {([read_reg 0xa8]&0x80000000)==0} {error "Application not ready; do not issue motion commands"}
set request [read_reg 0xa0]
if {$request!=[read_reg 0xa4]} {error "Mailbox busy; wait for prior command acknowledgement"}
binary scan $command cu* bytes
for {set i 0} {$i<8} {incr i} {
    set word 0
    for {set j 0} {$j<4} {incr j} {
        set index [expr {$i*4+$j}]
        if {$index<[llength $bytes]} {set word [expr {$word|([lindex $bytes $index]<<($j*8))}]}
    }
    write_reg [expr {0x80+$i*4}] $word
}
set request [expr {($request+1)&0xffffffff}]
write_reg 0xa0 $request
set deadline [expr {[clock milliseconds]+3000}]
while {[read_reg 0xa4]!=$request} {
    if {[clock milliseconds]>$deadline} {error "Application command acknowledgement timed out"}
    after 20
}
set result [read_reg 0xac]
puts "PAN_COMMAND: command={$command} result=$result enable=[read_reg 8] pwm_status=[format 0x%08X [read_reg 0x38]] applied_sequence=[read_reg 0x3c] yaw_us=[read_reg 0x14] pitch_us=[read_reg 0x18] app_status=[format 0x%08X [read_reg 0xa8]]"
if {$result!=0} {error "Firmware rejected command ($result: 1 invalid, 2 auto prerequisites)"}
puts "PAN_COMMAND: PASS acknowledged by running firmware"
disconnect
