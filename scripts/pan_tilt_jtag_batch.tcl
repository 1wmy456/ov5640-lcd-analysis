# Run ordinary firmware commands through its acknowledged mailbox; no PWM bypass.
if {[llength $argv]!=2} {error "Expected BSP peripheral base and ASCII command file"}
set base [lindex $argv 0]
set f [open [lindex $argv 1] r];set commands [split [read $f] "\n"];close $f
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "ARM Cortex-A9 MPCore #0"}
proc read_reg {o} {global base;return [expr {[mrd -force -value [expr {$base+$o}]]}]}
proc write_reg {o v} {global base;mwr -force [expr {$base+$o}] $v}
if {[read_reg 0]!=0x50544c54||([read_reg 0xa8]&0x80000000)==0} {error "Firmware peripheral is not ready"}
foreach command $commands {
 set command [string trim $command]
 if {$command eq ""||[string index $command 0] eq "#"} {continue}
 if {[string length $command]>31} {error "Command longer than mailbox capacity"}
 set req [read_reg 0xa0]
 if {$req!=[read_reg 0xa4]} {error "Mailbox busy"}
 binary scan $command cu* bytes
 for {set i 0} {$i<8} {incr i} {
  set word 0
  for {set j 0} {$j<4} {incr j} {
   set k [expr {$i*4+$j}]
   if {$k<[llength $bytes]} {set word [expr {$word|([lindex $bytes $k]<<($j*8))}]}
  }
  write_reg [expr {0x80+$i*4}] $word
 }
 set req [expr {($req+1)&0xffffffff}];write_reg 0xa0 $req
 set deadline [expr {[clock milliseconds]+3000}]
 while {[read_reg 0xa4]!=$req} {if {[clock milliseconds]>$deadline} {error "ACK timeout for $command"};after 10}
 if {[read_reg 0xac]!=0} {error "Firmware rejected command $command"}
 puts "PAN_BATCH: ACK {$command} yaw=[read_reg 0x14] pitch=[read_reg 0x18] en=[read_reg 8]"
 after 80
}
disconnect
puts "PAN_BATCH: PASS all ordinary firmware commands acknowledged"
