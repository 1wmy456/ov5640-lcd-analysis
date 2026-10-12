proc generate {drv_handle} {
    ::hsi::utils::define_include_file $drv_handle "xparameters.h" "PAN_TILT_CTRL" "NUM_INSTANCES" "DEVICE_ID" "C_S_AXI_BASEADDR" "C_S_AXI_HIGHADDR"
}
