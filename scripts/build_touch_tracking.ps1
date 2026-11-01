param([string]$Project='build/touch_tracking_release',[string]$Workspace='build/touch_tracking_sw',
 [string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',[string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if((Test-Path $Project) -or (Test-Path $Workspace)){throw 'Fresh hardware/software output paths required'}
foreach($test in @('test_touch','test_raw_capture','test_appearance','test_pid_control','sim_component_tracker')){
 & "$PSScriptRoot/$test.ps1" *> "build/touch_tracking_$test.txt"
 if($LASTEXITCODE){throw "$test failed"}
}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/integrate_touch_capture.tcl -tclargs -apply -out $Project *> build/touch_tracking_integration.log
if($LASTEXITCODE){throw 'Touch capture integration failed'}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/build_blue_tracker_board.tcl -tclargs $Project *> build/touch_tracking_build.log
if($LASTEXITCODE){throw 'Touch capture hardware/timing failed'}
& "$VivadoBin/vivado.bat" -mode batch -source scripts/audit_touch_tracking.tcl -tclargs $Project *> build/touch_tracking_audit.log
if($LASTEXITCODE){throw 'Touch raw frame provenance/pin audit failed'}
& $Xsct scripts/build_pan_tilt_app.tcl "$Project/system_wrapper.xsa" $Workspace *> build/touch_tracking_app.log
if($LASTEXITCODE){throw 'Touch tracking BSP/ELF failed'}
python scripts/record_touch_tracking.py --project $Project --workspace $Workspace
if($LASTEXITCODE){throw 'Touch tracking source/BSP/ELF record failed'}
Write-Output 'TOUCH_TRACKING_BUILD PASS; download is separate; startup manual/PWM OFF.'
