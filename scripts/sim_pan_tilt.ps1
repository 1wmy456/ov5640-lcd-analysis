param([string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',[string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo 'build/pan_tilt_sim'
New-Item -ItemType Directory -Force $out | Out-Null
$panOriginalPath=$env:PATH
try {
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 & $HostGcc -std=c11 -Wall -Wextra -Werror "$repo/sim/pan_tilt/test_tracking_control.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -o "$out/test_control.exe"
 if($LASTEXITCODE){throw 'Host control compile failed'}
 & "$out/test_control.exe" | Tee-Object -FilePath "$out/control.txt"
 if($LASTEXITCODE){throw 'Control test failed'}
} finally {$env:PATH=$panOriginalPath}
Push-Location $out
try{
 & "$VivadoBin/xvlog.bat" --sv "$repo/rtl/pan_tilt/dual_servo_pwm.v" "$repo/rtl/pan_tilt/pwm_wave_monitor.v" "$repo/rtl/pan_tilt/pan_tilt_ctrl.v" "$repo/sim/pan_tilt/tb_pan_tilt.sv"
 if($LASTEXITCODE){throw 'RTL compile failed'}
 & "$VivadoBin/xelab.bat" tb_pan_tilt -s pan_tilt -timescale 1ns/1ps
 if($LASTEXITCODE){throw 'RTL elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" pan_tilt -runall 2>&1
 $result | Set-Content -Encoding UTF8 rtl.txt
 $result | Write-Output
 if($LASTEXITCODE -or -not($result -match '^PASS PAN_RTL') -or ($result -match '^FAIL')){throw 'RTL test failed'}
}finally{Pop-Location}
& "$PSScriptRoot/sim_blue_tracker.ps1" -VivadoBin $VivadoBin
if($LASTEXITCODE){throw 'Video regression failed'}
