"""Check actual compiled touch inputs/new BSP; collect reproducible phase-A evidence."""
import argparse,hashlib,json,re,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--project',required=True);p.add_argument('--workspace',required=True);p.add_argument('--application',default='app_compiled');a=p.parse_args()
root=Path(__file__).resolve().parents[1];project=root/a.project;workspace=root/a.workspace
bsp=workspace/'board_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0'
params=(bsp/'include/xparameters.h').read_text()
assert re.search(r'#define XPAR_TOUCH_GPIO_BASEADDR 0x43C30000\b',params),'Missing fresh touch BSP address'
manifest=json.loads((workspace/a.application/'build_manifest.json').read_text())
for name in ['touch/touch_events.c','touch/touch_driver.c','pan_tilt/pan_tilt_app.c']:
 assert name in manifest['compiled_sources'],name
 assert hashlib.sha256((root/'vitis/ov5640_lcd/src'/name).read_bytes()).hexdigest()==manifest['source_sha256'][name],name
assert int(manifest['end_address'],16)<0x01100000
assert (project/'system_wrapper.xsa').read_bytes()==(workspace/'board_platform/hw/system_wrapper.xsa').read_bytes()
out=root/'docs/evidence/touch_stage_a';out.mkdir(parents=True,exist_ok=True)
for name in ['timing_summary.rpt','cdc.rpt','drc.rpt','utilization.rpt','touch_pins.txt','servo_pins.txt']:
 shutil.copy2(project/'board_reports'/name,out/name)
for src,dst in [(root/'build/touch_sim/events.txt','touch_events.txt'),(root/'build/touch_sim/rtl.txt','touch_cross.txt'),(root/'build/touch_pid_regression.txt','pid_regression.txt')]:
 if src.is_file():shutil.copy2(src,out/dst)
files={str(f.relative_to(root)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in [project/'system_wrapper.xsa',project/'ov5640_lcd.runs/impl_1/system_wrapper.bit',workspace/a.application/'ov5640_lcd.elf']}
(out/'BUILD_MANIFEST.json').write_bytes((json.dumps({'stage':'A','project':a.project,'workspace':a.workspace,'application':a.application,'compiled_sources':manifest['compiled_sources'],'end_address':manifest['end_address'],'files':files,'physical_touch_validation':'see BOARD_VALIDATION.md'},indent=2)+'\n').encode('utf-8'))
print('TOUCH_BUILD_RECORD: PASS compiled inputs/new BSP/link layout/XSA/hashes')
