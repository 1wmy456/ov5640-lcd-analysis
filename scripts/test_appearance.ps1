param([string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe',[string]$CapturedFrame,[string]$CapturedModel)
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
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror -I "$repo/sim/touch/host_include" -I "$repo/sim/pan_tilt/host_include" "$repo/sim/touch/test_appearance_runtime.c" "$repo/vitis/ov5640_lcd/src/touch/appearance_tracker.c" "$repo/vitis/ov5640_lcd/src/touch/box_shape_filter.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -lm -o "$out/runtime.exe"
 if($LASTEXITCODE){throw 'Appearance runtime compile failed'}
 & "$out/runtime.exe" | Tee-Object "$out/runtime.txt"
 if($LASTEXITCODE){throw 'Appearance runtime tests failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_touch_pd.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -lm -o "$out/touch_pd.exe"
 if($LASTEXITCODE){throw 'Touch PD cadence test compile failed'}
 & "$out/touch_pd.exe" | Tee-Object "$out/touch_pd.txt"
 if($LASTEXITCODE){throw 'Touch PD cadence test failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_box_shape.c" "$repo/vitis/ov5640_lcd/src/touch/box_shape_filter.c" -o "$out/box_shape.exe"
 if($LASTEXITCODE){throw 'Box shape compile failed'}
 & "$out/box_shape.exe" | Tee-Object "$out/box_shape.txt"
 if($LASTEXITCODE){throw 'Box shape stabilization test failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_position_trajectory.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/position_trajectory.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/tracking_control.c" -lm -o "$out/trajectory.exe"
 if($LASTEXITCODE){throw 'Position trajectory compile failed'}
 & "$out/trajectory.exe" | Tee-Object "$out/trajectory.txt"
 if($LASTEXITCODE){throw 'Position trajectory test failed'}
 if($CapturedFrame -or $CapturedModel){
  if(-not $CapturedFrame -or -not $CapturedModel){throw 'Both captured frame and matching model are required'}
  & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/touch/test_capture_stability.c" "$repo/vitis/ov5640_lcd/src/touch/appearance_tracker.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -lm -o "$out/capture.exe"
  if($LASTEXITCODE){throw 'Captured-frame test compile failed'}
  & "$out/capture.exe" $CapturedFrame $CapturedModel | Tee-Object "$out/capture.txt"
  if($LASTEXITCODE){throw 'Captured-frame stability failed'}
 }
}finally{$env:PATH=$oldPath}
