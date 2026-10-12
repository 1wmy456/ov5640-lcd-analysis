# XSCT read-only snapshot; no halt/reset/register writes.
connect -url tcp:127.0.0.1:3121
puts "BOARD_STATUS: [targets]"
targets -set -filter {name =~ "APU"}
foreach {label address count} {
    SLCR_IDCODE 0xF8000530 1
    VDMA_MM2S_CONTROL_STATUS 0x43000000 2
    VDMA_MM2S_FRAME_SIZES 0x43000050 3
    VDMA_S2MM_CONTROL_STATUS 0x43000030 2
    VDMA_S2MM_FRAME_SIZES 0x430000A0 3
    LCD_GPIO_DATA_TRI 0x41200000 2
} {
    if {[catch {mrd -force $address $count} value]} {
        puts "BOARD_STATUS: $label READ_FAILED $value"
    } else {
        puts "BOARD_STATUS: $label\n$value"
    }
}
disconnect
