# Verified against Navigator V3.9 schematic J1/JC2 and zynq_lvgl LCD.xdc.
# Dedicated AXI GPIO bits: SCL, SDA, CT_RST, CT_INT; no PS GPIO renumbering.
set_property -dict {PACKAGE_PIN R19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {touch_io_tri_io[0]}]
set_property -dict {PACKAGE_PIN P20 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {touch_io_tri_io[1]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {touch_io_tri_io[2]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33 PULLUP true} [get_ports {touch_io_tri_io[3]}]
