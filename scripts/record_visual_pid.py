"""Add truthful software-only PID provenance to the standard build evidence."""
from pathlib import Path
import hashlib
import json
import re

root=Path(__file__).resolve().parents[1]
out=root/'docs/evidence/visual_pid'
path=out/'BUILD_MANIFEST.json'
m=json.loads(path.read_text(encoding='utf-8'))
m['software_baseline']='c7b9d02'
m['hardware_reused']=True
m['new_synthesis_or_implementation']=False
m['cold_start']={'controller':'p','automatic':False,'pwm_enabled':False,'ki':[0,0],'kd':[0.03,0.03]}
m['initial_pd_profile']={'kp':[0.7,0.7],'ki':[0,0],'kd':[0.03,0.03],'tau_ms':[100,100],
                         'i_limit_us_s':[10,10],'d_limit_px_s':[1000,1000],
                         'rate_us_s':[75,75],'acceleration_us_s2':[400,400],
                         'deceleration_us_s2':[600,600],'deadband_px':[15,22]}
control=(out/'control_regression.txt').read_text(encoding='utf-8-sig')
match=re.search(r'PASS VISUAL_PID checks=(\d+)',control)
assert match,'Missing PID PASS evidence'
m['pid_checks']=int(match[1])
m['controller_source_sha256']={str(p.relative_to(root)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
    for p in (root/'vitis/ov5640_lcd/src/pan_tilt').glob('*') if p.suffix in ('.c','.h')}
path.write_text(json.dumps(m,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print('PASS PID_PROVENANCE: software baseline, reused hardware and actual tests recorded')
