# Diagnostic DDR snapshot; capture can span writes, so this is not an atomic frame.
# xsct scripts/capture_blue_tracker_frame.tcl <output.bin>
if {[llength $argv] != 1} {error "Expected binary output path"}
connect -url tcp:127.0.0.1:3121
targets -set -filter {name =~ "APU"}
set height [lindex [mrd -force -value 0x430000A0] 0]
set bytes_per_line [lindex [mrd -force -value 0x430000A4] 0]
set stride [expr {[lindex [mrd -force -value 0x430000A8] 0] & 0xffff}]
if {$height != 480 || $bytes_per_line != 2400 || $stride != 2400} {error "Expected confirmed 800x480 RGB888 mode"}
set park [lindex [mrd -force -value 0x43000028] 0]
set writing [expr {($park >> 24) & 31}]
set index [expr {($writing + 2) % 3}]
set address [lindex [mrd -force -value [expr {0x430000AC + $index*4}]] 0]
if {$address < 0x01100000 || $address >= 0x02000000} {error "Unexpected framebuffer address $address"}
puts [format "DDR_SNAPSHOT: index=%d address=0x%08x bytes=%d" $index $address [expr {$height*$stride}]]
mrd -force -bin -file [lindex $argv 0] $address [expr {$height*$stride/4}]
puts "DDR_SNAPSHOT: diagnostic non-atomic capture complete"
disconnect
