param([string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',[string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo build/touch_sim
New-Item -ItemType Directory -Force $out | Out-Null
$oldPath=$env:PATH
try{
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_touch_events.c" "$repo/vitis/ov5640_lcd/src/touch/touch_events.c" -o "$out/events.exe"
 if($LASTEXITCODE){throw 'Touch C compile failed'}
 & "$out/events.exe" | Tee-Object "$out/events.txt"
 if($LASTEXITCODE){throw 'Touch C self-check failed'}
}finally{$env:PATH=$oldPath}
Push-Location $out
try{
 & "$VivadoBin/xvlog.bat" --sv "$repo/rtl/touch/axis_touch_cross.v" "$repo/sim/touch/tb_touch_cross.sv" *> compile.txt
 if($LASTEXITCODE){throw 'Touch RTL compile failed'}
 & "$VivadoBin/xelab.bat" tb_touch_cross -s touch_cross -timescale 1ns/1ps *> elaborate.txt
 if($LASTEXITCODE){throw 'Touch RTL elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" touch_cross -runall 2>&1
 $result | Tee-Object rtl.txt
 if($LASTEXITCODE -or -not($result -match '^PASS TOUCH_CROSS')){throw 'Touch RTL self-check failed'}
}finally{Pop-Location}
