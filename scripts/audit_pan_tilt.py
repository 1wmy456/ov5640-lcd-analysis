"""Audit preservation, accepted calibration and new hardware/source connections."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "15e98ec"
parser = argparse.ArgumentParser()
parser.add_argument("project", type=Path)
args = parser.parse_args()
copy = args.project.resolve()
bd = "ov5640_lcd.srcs/sources_1/bd/system/system.bd"
original = json.loads((ROOT / bd).read_text())["design"]
actual = json.loads((copy / bd).read_text())["design"]
assert actual["components"].keys() - original["components"].keys() == {"axis_blue_tracker_0", "pan_tilt_ctrl_0"}
for name, spec in original["components"].items():
    new = actual["components"][name]
    for key, val in spec.items():
        if key == "parameters":
            for p, v in val.items():
                if name == "ps7_0_axi_periph" and p == "NUM_MI":
                    assert new[key][p]["value"] == "5"
                else:
                    assert new[key][p] == v, (name, p)
        elif name == "ps7_0_axi_periph" and key == "interface_ports":
            assert new[key].keys() - val.keys() == {"M04_AXI"}
            assert all(new[key][p] == v for p, v in val.items())
        elif name == "ps7_0_axi_periph" and key == "ports":
            assert new[key].keys() - val.keys() == {"M04_ACLK", "M04_ARESETN"}
            assert all(new[key][p] == v for p, v in val.items())
        elif name == "ps7_0_axi_periph" and key == "components":
            assert new[key].keys() - val.keys() == {"m04_couplers", "s00_mmu"}
            assert all(new[key][p] == v for p, v in val.items() if p != "xbar")
            assert new[key]["xbar"]["parameters"]["NUM_MI"]["value"] == "5"
        elif name == "ps7_0_axi_periph" and key in ("nets", "interface_nets"):
            # Vivado regenerates the internal crossbar clock/reset fanout and
            # inserts its address MMU when assigning the fifth peripheral.
            ignored = {"ps7_0_axi_periph_ACLK_net", "ps7_0_axi_periph_ARESETN_net", "ps7_0_axi_periph_to_s00_couplers"}
            assert all(new[key].get(p) == v for p, v in val.items() if p not in ignored)
        else:
            assert new[key] == val, (name, key)
for name, net in original["nets"].items():
    expected = set(net["ports"])
    if name == "processing_system7_0_FCLK_CLK0":
        expected.update(["axis_blue_tracker_0/aclk", "pan_tilt_ctrl_0/s_axi_aclk", "ps7_0_axi_periph/M04_ACLK"])
    elif name == "rst_ps7_0_100M_peripheral_aresetn":
        expected.update(["axis_blue_tracker_0/aresetn", "pan_tilt_ctrl_0/s_axi_aresetn", "ps7_0_axi_periph/M04_ARESETN"])
    assert set(actual["nets"][name]["ports"]) == expected, name
for name, net in original["interface_nets"].items():
    if name == "v_vid_in_axi4s_0_video_out":
        assert set(actual["interface_nets"][name]["interface_ports"]) == {"v_vid_in_axi4s_0/video_out", "axis_blue_tracker_0/S_AXIS"}
    else:
        assert actual["interface_nets"][name] == net, name
assert any(set(n["interface_ports"]) == {"axis_blue_tracker_0/M_AXIS", "axi_vdma_0/S_AXIS_S2MM"} for n in actual["interface_nets"].values())
for pin in ["bbox_valid", "result_pulse", "frame_error", "bbox_xmin", "bbox_xmax", "bbox_ymin", "bbox_ymax", "blue_pixel_count"]:
    assert any(set(n["ports"]) == {"axis_blue_tracker_0/"+pin, "pan_tilt_ctrl_0/"+pin} for n in actual["nets"].values()), pin
cal = {"MODE":2,"IMAGE_WIDTH":800,"IMAGE_HEIGHT":480,"BLUE_MIN":80,"BR_DELTA":60,"BG_DELTA":35,"MIN_B_R_RATIO":2,"MIN_BLUE_RUN":3,"MIN_PIXELS":256,"BORDER_WIDTH":2,"CENTER_CROSS":0}
for key, val in cal.items():
    assert int(actual["components"]["axis_blue_tracker_0"]["parameters"][key]["value"]) == val
for peripheral, spec in original["addressing"].items():
    for space, values in spec["address_spaces"].items():
        segments = actual["addressing"][peripheral]["address_spaces"][space]["segments"]
        for name, val in values["segments"].items():
            assert segments[name] == val
new = actual["addressing"]["/processing_system7_0"]["address_spaces"]["Data"]["segments"]["SEG_pan_tilt_ctrl_0_Reg"]
assert new["offset"] == "0x43C20000" and new["range"] == "4K"
names = subprocess.check_output(["git","ls-tree","-r","--name-only",BASELINE],cwd=ROOT).decode().splitlines()
protected = [n for n in names if n.startswith(("ip_repo/","ov5640_lcd.srcs/","vitis/","rtl/blue_tracker/")) or n == "ov5640_lcd.xpr"]
count = 0
for name in protected:
    before = subprocess.check_output(["git","show",f"{BASELINE}:{name}"],cwd=ROOT)
    if name == "vitis/ov5640_lcd/src/main.c":
        expected = before.replace(b'#include "ov5640/ov5640_init.h"\r\n',b'#include "ov5640/ov5640_init.h"\r\n#include "pan_tilt/pan_tilt_app.h"\r\n')
        expected = expected.replace(b'xil_printf("Pixel clock    : %d\\r\\n", vd_mode.freq);',b'xil_printf("Pixel clock kHz: %d\\r\\n", (int)(vd_mode.freq*1000.0));')
        expected = expected.replace(b'    return 0;\r\n',b'    pan_tilt_run(vd_mode.width, vd_mode.height, status == 0);\r\n    return 0;\r\n')
        assert (ROOT/name).read_bytes() == expected, name
    else:
        assert (ROOT/name).read_bytes() == before, name
        count += 1
for src in (ROOT/"rtl").rglob("*.v"):
    assert src.read_bytes() == (copy/src.relative_to(ROOT)).read_bytes(), str(src)
print(f"PASS PAN_AUDIT: {count} protected files byte-identical to 15e98ec; main has exactly 3 authorized edits")
print("PASS PAN_AUDIT: native cells/nets/addresses preserved, only interconnect M04/tracker/PWM branch added; calibration exact")
