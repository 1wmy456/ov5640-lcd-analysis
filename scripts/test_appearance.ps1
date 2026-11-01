param([string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo build/appearance_sim
New-Item -ItemType Directory -Force $out | Out-Null
$oldPath=$env:PATH
try{
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_appearance.c" "$repo/vitis/ov5640_lcd/src/touch/appearance_tracker.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -lm -o "$out/test.exe"
 if($LASTEXITCODE){throw 'Appearance compile failed'}
 & "$out/test.exe" | Tee-Object "$out/result.txt"
 if($LASTEXITCODE){throw 'Appearance tests failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror -I "$repo/sim/touch/host_include" -I "$repo/sim/pan_tilt/host_include" "$repo/sim/touch/test_appearance_runtime.c" "$repo/vitis/ov5640_lcd/src/touch/appearance_tracker.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -lm -o "$out/runtime.exe"
 if($LASTEXITCODE){throw 'Appearance runtime compile failed'}
 & "$out/runtime.exe" | Tee-Object "$out/runtime.txt"
 if($LASTEXITCODE){throw 'Appearance runtime tests failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_touch_pd.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -lm -o "$out/touch_pd.exe"
 if($LASTEXITCODE){throw 'Touch PD cadence test compile failed'}
 & "$out/touch_pd.exe" | Tee-Object "$out/touch_pd.txt"
 if($LASTEXITCODE){throw 'Touch PD cadence test failed'}
}finally{$env:PATH=$oldPath}
