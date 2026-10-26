param([string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',[string]$HostGcc='D:/msys64/ucrt64/bin/gcc.exe',[switch]$SkipLegacy)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$out=Join-Path $repo 'build/component_tracker_sim'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$capOriginalPath=$env:PATH
try{
 $env:PATH=(Split-Path $HostGcc -Parent)+';'+$env:PATH
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/pan_tilt/test_cap_components.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -I "$repo/vitis/ov5640_lcd/src/pan_tilt" -lm -o "$out/test_components.exe"
 if($LASTEXITCODE){throw 'Component C compile failed'}
 $result=& "$out/test_components.exe" 2>&1
 $result | Tee-Object -FilePath "$out/components.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS CAP_COMPONENTS')){throw 'Component C test failed'}
 & $HostGcc -std=c11 -O2 -Wall -Wextra -Werror "$repo/sim/pan_tilt/test_cap_runtime.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_runtime.c" "$repo/vitis/ov5640_lcd/src/pan_tilt/cap_components.c" -I "$repo/sim/pan_tilt/host_include" -I "$repo/vitis/ov5640_lcd/src/pan_tilt" -lm -o "$out/test_runtime.exe"
 if($LASTEXITCODE){throw 'Component runtime C compile failed'}
 $result=& "$out/test_runtime.exe" 2>&1
 $result | Tee-Object -FilePath "$out/runtime.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS CAP_RUNTIME')){throw 'Component runtime test failed'}
}finally{$env:PATH=$capOriginalPath}
Push-Location $out
try{
 $rtl=@(Get-ChildItem "$repo/rtl/blue_tracker/*.v","$repo/rtl/pan_tilt/*.v" | ForEach-Object FullName)
 & "$VivadoBin/xvlog.bat" --sv @rtl "$repo/sim/pan_tilt/tb_component_video.sv"
 if($LASTEXITCODE){throw 'Component RTL compilation failed'}
 & "$VivadoBin/xelab.bat" tb_component_video -s component_video -timescale 1ns/1ps
 if($LASTEXITCODE){throw 'Component RTL elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" component_video -runall 2>&1
 $result | Tee-Object -FilePath "$out/video.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS COMPONENT_VIDEO') -or ($result -match '^FAIL')){throw 'Component RTL simulation failed'}
 & "$VivadoBin/xvlog.bat" --sv "$repo/sim/pan_tilt/tb_mask_words.sv"
 if($LASTEXITCODE){throw 'Mask packing test compile failed'}
 & "$VivadoBin/xelab.bat" tb_mask_words -s mask_words -timescale 1ns/1ps
 if($LASTEXITCODE){throw 'Mask packing test elaboration failed'}
 $result=& "$VivadoBin/xsim.bat" mask_words -runall 2>&1
 $result | Tee-Object -FilePath "$out/mask_words.txt"
 if($LASTEXITCODE -or -not($result -match '^PASS MASK_WORDS') -or ($result -match '^FAIL')){throw 'Mask packing test failed'}
}finally{Pop-Location}
if(-not $SkipLegacy){& "$PSScriptRoot/sim_pan_tilt.ps1" -VivadoBin $VivadoBin -HostGcc $HostGcc}
