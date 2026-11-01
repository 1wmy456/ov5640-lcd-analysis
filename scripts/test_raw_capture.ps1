param([string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo build/raw_capture_sim
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try{
 & "$VivadoBin/xvlog.bat" --sv "$repo/rtl/touch/axis_raw_capture.v" "$repo/sim/touch/tb_raw_capture.sv" *> compile.txt
 if($LASTEXITCODE){throw 'Raw capture compile failed'}
 & "$VivadoBin/xelab.bat" tb_raw_capture -s raw_capture -timescale 1ns/1ps *> elaborate.txt
 if($LASTEXITCODE){throw 'Raw capture elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" raw_capture -runall 2>&1
 $result | Tee-Object rtl.txt
 if($LASTEXITCODE -or -not($result -match '^PASS RAW_CAPTURE')){throw 'Raw capture simulation failed'}
 & "$VivadoBin/xvlog.bat" --sv (Get-ChildItem "$repo/rtl/pan_tilt/*.v" | ForEach-Object FullName) "$repo/sim/touch/tb_touch_feedback.sv" *> feedback_compile.txt
 if($LASTEXITCODE){throw 'Raw feedback compile failed'}
 & "$VivadoBin/xelab.bat" tb_touch_feedback -s touch_feedback -timescale 1ns/1ps *> feedback_elaborate.txt
 if($LASTEXITCODE){throw 'Raw feedback elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" touch_feedback -runall 2>&1
 $result | Tee-Object feedback.txt
 if($LASTEXITCODE -or -not($result -match '^PASS TOUCH_FEEDBACK')){throw 'Raw feedback self-check failed'}
}finally{Pop-Location}
