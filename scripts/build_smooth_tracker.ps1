param([string]$Workspace='build/smooth_tracker_sw',
 [string]$Project='build/component_tracker_v2',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if(Test-Path -LiteralPath $Workspace){throw 'Use a fresh workspace; previous binaries are preserved'}
& "$PSScriptRoot/test_smooth_control.ps1"
if($LASTEXITCODE){throw 'Smooth controller tests failed'}
& "$PSScriptRoot/sim_component_tracker.ps1"
if($LASTEXITCODE){throw 'Component/video/PWM regression failed'}
$result=& $Xsct "$PSScriptRoot/build_pan_tilt_app.tcl" "$Project/system_wrapper.xsa" $Workspace 2>&1
$result | Tee-Object -FilePath "$repo/build/smooth_app_build.txt"
if($LASTEXITCODE -or -not($result -match '^BOARD_APP: PASS application rebuilt')){throw 'Smooth BSP/ELF build failed'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project $Project --workspace $Workspace --output "$repo/docs/evidence/smooth_tracker"
if($LASTEXITCODE){throw 'Build evidence verification failed'}
Write-Output 'SMOOTH_BUILD: PASS; unchanged video hardware, fresh software, startup manual PWM OFF.'
