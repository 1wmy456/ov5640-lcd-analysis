param([string]$Project='build/pan_tilt_tracking_release',
 [string]$Workspace='build/pan_tilt_sw_release',
 [string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if((Test-Path -LiteralPath $Project) -or (Test-Path -LiteralPath $Workspace)){throw 'Use fresh -Project and -Workspace paths; existing accepted artifacts are preserved'}
& "$PSScriptRoot/sim_pan_tilt.ps1" -VivadoBin $VivadoBin
if($LASTEXITCODE){throw 'Regression failed'}
$integrate=& "$VivadoBin/vivado.bat" -mode batch -source "$PSScriptRoot/integrate_pan_tilt.tcl" -tclargs -apply -out $Project 2>&1
$integrate | Set-Content -Encoding UTF8 "$repo/build/pan_integrate.log"
if($LASTEXITCODE -or -not($integrate -match '^PAN_INTEGRATION: PASS')){throw 'Integration failed; inspect build/pan_integrate.log'}
python "$PSScriptRoot/audit_pan_tilt.py" $Project
if($LASTEXITCODE){throw 'Preservation/calibration audit failed'}
$hardware=& "$VivadoBin/vivado.bat" -mode batch -source "$PSScriptRoot/build_blue_tracker_board.tcl" -tclargs $Project 2>&1
$hardware | Set-Content -Encoding UTF8 "$repo/build/pan_build.log"
if($LASTEXITCODE -or -not($hardware -match '^BOARD_BUILD: PASS')){throw 'Hardware/timing build failed; inspect build/pan_build.log'}
$software=& $Xsct "$PSScriptRoot/build_pan_tilt_app.tcl" "$Project/system_wrapper.xsa" $Workspace 2>&1
$software | Set-Content -Encoding UTF8 "$repo/build/pan_app.log"
if($LASTEXITCODE -or -not($software -match '^BOARD_APP: PASS application rebuilt')){throw 'Fresh BSP/application build failed; inspect build/pan_app.log'}
python "$PSScriptRoot/check_repository.py"
if($LASTEXITCODE){throw 'Repository source integrity failed'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project $Project --workspace $Workspace
if($LASTEXITCODE){throw 'Artifact/source evidence check failed'}
Write-Output "PAN_BUILD: PASS $Project $Workspace; default manual PWM OFF"
