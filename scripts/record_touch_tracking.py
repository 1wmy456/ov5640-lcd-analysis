"""Record actual raw-frame hardware and PS build; never infer physical acceptance."""
import argparse,json,hashlib,re,shutil
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--project',required=True);p.add_argument('--workspace',required=True);p.add_argument('--application',default='app_compiled');a=p.parse_args()
root=Path(__file__).resolve().parents[1];project=root/a.project;ws=root/a.workspace;app=ws/a.application
out=root/'docs/evidence/touch_tracking';out.mkdir(parents=True,exist_ok=True)
params=(ws/'board_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include/xparameters.h').read_text()
for macro,address in [('XPAR_TOUCH_GPIO_BASEADDR','0x43C30000'),('XPAR_RAW_CAPTURE_DMA_BASEADDR','0x43C40000')]:
 assert re.search(r'#define '+macro+' '+address+r'\b',params),macro
manifest=json.loads((app/'build_manifest.json').read_text());assert int(manifest['end_address'],16)<0x01100000
for name in ['touch/appearance_runtime.c','touch/appearance_tracker.c','touch/box_shape_filter.c','touch/touch_driver.c','touch/touch_events.c','pan_tilt/pan_tilt_app.c','pan_tilt/tracking_control.c','pan_tilt/position_trajectory.c']:
 assert name in manifest['compiled_sources']
 assert hashlib.sha256((root/'vitis/ov5640_lcd/src'/name).read_bytes()).hexdigest()==manifest['source_sha256'][name],name
for name in ['axis_touch_cross.v','axis_raw_capture.v']:
 assert (root/'rtl/touch'/name).read_bytes()==(project/'rtl/touch'/name).read_bytes(),name
assert (root/'rtl/pan_tilt/pan_tilt_ctrl.v').read_bytes()==(project/'ip_repo/pan_tilt_ctrl/src/pan_tilt_ctrl.v').read_bytes(),'packaged raw feedback RTL differs'
assert (project/'system_wrapper.xsa').read_bytes()==(ws/'board_platform/hw/system_wrapper.xsa').read_bytes()
for name in ['timing_summary.rpt','cdc.rpt','drc.rpt','utilization.rpt','touch_pins.txt','servo_pins.txt']:
 shutil.copy2(project/'board_reports'/name,out/name)
for src,dst in [('build/raw_capture_sim/rtl.txt','raw_capture.txt'),('build/raw_capture_sim/feedback.txt','raw_feedback.txt'),('build/touch_sim/rtl.txt','cross.txt'),('build/touch_sim/status.txt','status.txt'),('build/appearance_sim/result.txt','appearance.txt'),('build/appearance_sim/runtime.txt','appearance_runtime.txt'),('build/appearance_sim/touch_pd.txt','touch_pd.txt'),('build/touch_tracking_pid_regression.txt','pid_regression.txt'),('build/touch_component_regression.txt','component_regression.txt'),('build/touch_legacy_regression.txt','legacy_regression.txt')]:
 if (root/src).exists():shutil.copy2(root/src,out/dst)
files=[project/'system_wrapper.xsa',project/'ov5640_lcd.runs/impl_1/system_wrapper.bit',app/'ov5640_lcd.elf']
if (root/'build/appearance_sim/box_shape.txt').exists():shutil.copy2(root/'build/appearance_sim/box_shape.txt',out/'box_shape.txt')
for name in ['capture','capture_before','capture_reject','trajectory']:
 if (root/('build/appearance_sim/'+name+'.txt')).exists():shutil.copy2(root/('build/appearance_sim/'+name+'.txt'),out/(name+'.txt'))
report={'project':a.project,'workspace':a.workspace,'application':a.application,'compiled_sources':manifest['compiled_sources'],'end_address':manifest['end_address'],'files':{f.relative_to(root).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files},'physical_acceptance':'See BOARD_VALIDATION.md; simulation is separate.'}
(out/'BUILD_MANIFEST.json').write_bytes((json.dumps(report,indent=2)+'\n').encode())
print('TOUCH_TRACKING_RECORD PASS real compiled sources/raw hardware/new BSP/link boundary')
