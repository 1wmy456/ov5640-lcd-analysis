param([string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo 'build/visual_pid_sim'
New-Item -ItemType Directory -Force -Path $out | Out-Null
& "$PSScriptRoot/test_smooth_control.ps1" -HostGcc $HostGcc
if($LASTEXITCODE){throw 'Legacy/smooth regression failed'}
$pidOriginalPath=$env:PATH
try{
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/pan_tilt/test_pid_control.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -lm -o "$out/test_pid_control.exe"
 if($LASTEXITCODE){throw 'PID host compilation failed'}
 $result=& "$out/test_pid_control.exe" "$out/synthetic_plant_trace.csv" 2>&1
 $result | Tee-Object -FilePath "$out/test_pid_control.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS VISUAL_PID')){throw 'PID regression failed'}
}finally{$env:PATH=$pidOriginalPath}
