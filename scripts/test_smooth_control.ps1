param([string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo 'build/smooth_control_sim'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$smoothOriginalPath=$env:PATH
try{
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 foreach($test in @('test_tracking_control','test_smooth_control')){
  & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/pan_tilt/$test.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -lm -o "$out/$test.exe"
  if($LASTEXITCODE){throw "Compile failed: $test"}
  $result=& "$out/$test.exe" "$out/trace.csv" 2>&1
  $result | Tee-Object -FilePath "$out/$test.txt"
  if($LASTEXITCODE -or -not($result -match '^PASS')){throw "Control regression failed: $test"}
 }
 $result=& "$out/test_smooth_control.exe" "$out/trace_400_600.csv" 400 600 2>&1
 $result | Tee-Object -FilePath "$out/test_smooth_control_400_600.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS')){throw 'Field profile control regression failed'}
}finally{$env:PATH=$smoothOriginalPath}
