param([string]$Project='build/touch_stage_a',[string]$Workspace='build/touch_stage_a_sw',
 [string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',[string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if((Test-Path $Project) -or (Test-Path $Workspace)){throw 'Fresh build and workspace paths required'}
& "$PSScriptRoot/test_touch.ps1"
if($LASTEXITCODE){throw 'Touch tests failed'}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/integrate_touch_selection.tcl -tclargs -apply -out $Project *> build/touch_integration.log
if($LASTEXITCODE){throw 'Touch integration failed; see build/touch_integration.log'}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/build_blue_tracker_board.tcl -tclargs $Project *> build/touch_build.log
if($LASTEXITCODE){throw 'Hardware build/timing gates failed; see build/touch_build.log'}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/audit_touch_stage_a.tcl -tclargs $Project *> build/touch_audit.log
if($LASTEXITCODE){throw 'Touch pin/address/calibration audit failed; see build/touch_audit.log'}
& $Xsct scripts/build_pan_tilt_app.tcl "$Project/system_wrapper.xsa" $Workspace *> build/touch_app.log
if($LASTEXITCODE){throw 'Fresh touch BSP/ELF failed; see build/touch_app.log'}
python scripts/record_touch_stage_a.py --project $Project --workspace $Workspace
if($LASTEXITCODE){throw 'Touch compiled-source/BSP/artifact check failed'}
Write-Output 'TOUCH_STAGE_A_BUILD PASS; manual/PWM OFF; touch probe required on board.'
