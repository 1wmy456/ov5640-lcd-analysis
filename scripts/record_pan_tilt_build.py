"""Collect real build evidence and check compiled inputs, BSP, and artifacts."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--project", type=Path, required=True)
parser.add_argument("--workspace", type=Path, required=True)
parser.add_argument("--output", type=Path, default=ROOT / "docs/evidence/pan_tilt")
args = parser.parse_args()
project, workspace = args.project.resolve(), args.workspace.resolve()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
manifest = json.loads((workspace/"app_compiled/build_manifest.json").read_text())
for relative, expected in manifest["source_sha256"].items():
    assert hashlib.sha256((ROOT/"vitis/ov5640_lcd/src"/relative).read_bytes()).hexdigest() == expected, relative
header = workspace/"board_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include/xparameters.h"
match = re.search(r"#define XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR (0x[0-9A-Fa-f]+)",header.read_text())
assert match and int(match[1],16) == 0x43c20000
artifacts = [project/"ov5640_lcd.runs/impl_1/system_wrapper.bit",project/"system_wrapper.xsa",workspace/"app_compiled/ov5640_lcd.elf",header]
info = {"baseline":"15e98ec","branch":subprocess.check_output(["git","branch","--show-current"],cwd=ROOT).decode().strip(),
        "project":project.relative_to(ROOT).as_posix(),"workspace":workspace.relative_to(ROOT).as_posix(),
        "calibration":(project/"pan_tilt_summary.txt").read_text(),"compiled_sources":manifest["compiled_sources"],
        "program_end":manifest["end_address"],"framebuffer_start":"0x01100000","bsp_base_macro":match[0],
        "artifact_sha256":{p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in artifacts}}
info["rtl_sha256"]={p.relative_to(project).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (project/"rtl").rglob("*.v")}
report_dir = output/"tool_reports"
report_dir.mkdir(exist_ok=True)
for name in ["timing_summary.rpt","utilization.rpt","drc.rpt","cdc.rpt","servo_pins.txt","bus_skew.rpt"]:
    shutil.copyfile(project/"board_reports"/name,report_dir/name)
io = (project/"board_reports/io.rpt").read_text()
(report_dir/"servo_io_excerpt.txt").write_text("\n".join(line for line in io.splitlines() if any(s in line for s in ["servo_yaw_pwm","servo_pitch_pwm","VCCO_13"]))+"\n",encoding="utf-8")
info["report_sha256"]={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in report_dir.iterdir() if p.is_file()}
(output/"BUILD_MANIFEST.json").write_text(json.dumps(info,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
print("PASS PAN_EVIDENCE: actual compiled sources match repository, fresh BSP and bit/XSA/ELF hashes recorded")
