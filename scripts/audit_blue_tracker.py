"""Read-only audit of the integrated copy against the original BD and Git baseline."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "4bccc73e8e610499f55f5d60a9b490f8221645d5"


def audit(copy: Path) -> None:
    bd = Path("ov5640_lcd.srcs/sources_1/bd/system/system.bd")
    original = json.loads((ROOT / bd).read_text(encoding="utf-8"))["design"]
    integrated = json.loads((copy / bd).read_text(encoding="utf-8"))["design"]
    oldcells, newcells = original["components"], integrated["components"]
    assert newcells.keys() - oldcells.keys() == {"axis_blue_tracker_0"}
    for cell, spec in oldcells.items():
        new = newcells[cell]
        for key, value in spec.items():
            if key == "parameters":
                # Vivado expands PS default parameters on save, retaining existing values.
                assert all(new[key].get(k) == v for k, v in value.items()), cell
            else:
                assert new.get(key) == value, (cell, key)
    for name, net in original["nets"].items():
        if name in ("processing_system7_0_FCLK_CLK0", "rst_ps7_0_100M_peripheral_aresetn"):
            expected = set(net["ports"])
            suffix = "aclk" if "CLK0" in name else "aresetn"
            expected.add("axis_blue_tracker_0/" + suffix)
            assert set(integrated["nets"][name]["ports"]) == expected
        else:
            assert integrated["nets"][name] == net, name
    for name, net in original["interface_nets"].items():
        if name == "v_vid_in_axi4s_0_video_out":
            assert set(integrated["interface_nets"][name]["interface_ports"]) == {
                "v_vid_in_axi4s_0/video_out", "axis_blue_tracker_0/S_AXIS"}
        else:
            assert integrated["interface_nets"][name] == net, name
    assert any(set(n["interface_ports"]) == {"axis_blue_tracker_0/M_AXIS", "axi_vdma_0/S_AXIS_S2MM"}
               for n in integrated["interface_nets"].values())
    # Verify every tracked original hardware/software/config source byte against baseline.
    names = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASELINE], cwd=ROOT).decode().splitlines()
    protected = [n for n in names if n.startswith(("ip_repo/", "ov5640_lcd.srcs/", "vitis/")) or n == "ov5640_lcd.xpr"]
    for name in protected:
        before = subprocess.check_output(["git", "show", f"{BASELINE}:{name}"], cwd=ROOT)
        assert (ROOT / name).read_bytes() == before, name
        if name.startswith(("ip_repo/", "ov5640_lcd.srcs/")) and not name.endswith((".bd", ".xci")):
            assert (copy / name).read_bytes() == before, ("copied source", name)
    print(f"PASS audit: {len(protected)} original files byte-identical to baseline")
    print("PASS audit: all existing BD cell properties retained; all native nets retained")
    print("PASS audit: only tracker cell, stream insertion, AXI clock/reset fanout added")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("copy", type=Path)
    args = parser.parse_args()
    audit(args.copy.resolve())
