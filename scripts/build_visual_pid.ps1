param([string]$Workspace='build/visual_pid_sw',
 [string]$Project='build/component_tracker_v2',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if(Test-Path -LiteralPath $Workspace){throw 'Use a fresh workspace; previous binaries are preserved'}
$evidence=Join-Path $repo 'docs/evidence/visual_pid'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
& "$PSScriptRoot/test_pid_control.ps1" | Tee-Object -FilePath "$evidence/control_regression.txt"
if($LASTEXITCODE){throw 'PID/legacy/smooth tests failed'}
& "$PSScriptRoot/sim_component_tracker.ps1" | Tee-Object -FilePath "$evidence/video_regression.txt"
if($LASTEXITCODE){throw 'Component/video/PWM regression failed'}
$result=& $Xsct "$PSScriptRoot/build_pan_tilt_app.tcl" "$Project/system_wrapper.xsa" $Workspace 2>&1
$result | Tee-Object -FilePath "$evidence/app_build.txt"
if($LASTEXITCODE -or -not($result -match '^BOARD_APP: PASS application rebuilt')){throw 'PID BSP/ELF build failed'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project $Project --workspace $Workspace --output $evidence
if($LASTEXITCODE){throw 'Build evidence verification failed'}
Copy-Item -LiteralPath "$repo/build/visual_pid_sim/synthetic_plant_trace.csv" -Destination "$evidence/synthetic_plant_trace.csv"
python "$PSScriptRoot/record_visual_pid.py"
if($LASTEXITCODE){throw 'PID provenance verification failed'}
Write-Output 'VISUAL_PID_BUILD: PASS; same video hardware, fresh BSP/ELF; startup P/manual/PWM OFF.'
