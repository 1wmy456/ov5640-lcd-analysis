"""Freeze the accepted visual-PD release without collecting dirty working files."""
from pathlib import Path
import hashlib, json, shutil, subprocess
root=Path(__file__).resolve().parents[1]
dest=root/'build/releases/lost'
if dest.exists():
    raise SystemExit('lost already exists; refusing overwrite')
files={
 'system_wrapper.bit':'build/component_tracker_v2/ov5640_lcd.runs/impl_1/system_wrapper.bit',
 'system_wrapper.xsa':'build/component_tracker_v2/system_wrapper.xsa',
 'bsp_system_wrapper.xsa':'build/visual_pid_sw/board_platform/hw/system_wrapper.xsa',
 'ps7_init.tcl':'build/visual_pid_sw/board_platform/hw/ps7_init.tcl',
 'ov5640_lcd.elf':'build/visual_pid_sw/app_compiled/ov5640_lcd.elf',
 'build_manifest.json':'build/visual_pid_sw/app_compiled/build_manifest.json',
 'SETTINGS.json':'docs/evidence/visual_pid/SETTINGS.json',
 'SESSION.json':'docs/evidence/visual_pid/SESSION.json'}
assert all((root/p).is_file() for p in files.values())
elf_manifest=json.loads((root/files['build_manifest.json']).read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(root/files['ov5640_lcd.elf'])==elf_manifest['elf_sha256']
assert sha(root/files['system_wrapper.xsa'])==sha(root/files['bsp_system_wrapper.xsa'])
dest.mkdir(parents=True)
for name,src in files.items():shutil.copy2(root/src,dest/name)
with (dest/'source.zip').open('wb') as f:
    subprocess.run(['git','archive','--format=zip','HEAD'],cwd=root,stdout=f,check=True)
shutil.copytree(root/'build/visual_pid_sw/app_compiled/src',dest/'compiled_src')
# Keep dirty inputs separately: these are not implicitly part of the accepted binary.
subprocess.run(['git','diff','--binary','--output='+str(dest/'working_tree.patch')],cwd=root,check=True)
manifest={'name':'lost','source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
 'hardware':'component_tracker_v2','software':'visual_pid_sw','startup':'manual/PWM OFF',
 'files':{p.relative_to(dest).as_posix():sha(p) for p in dest.rglob('*') if p.is_file()}}
(dest/'release.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
e=root/'docs/releases';e.mkdir(exist_ok=True)
(e/'lost.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('LOST: frozen and SHA256 verified:',dest)
