param([string]$Port='COM5',[switch]$EnableAuto,[switch]$WideExperiment)
$ErrorActionPreference='Stop'
# Original restoration remains unchanged; it leaves PWM OFF and sets the center.
& "$PSScriptRoot/restore_component_calibration.ps1" -Port $Port
if($LASTEXITCODE){throw 'Baseline calibration restore failed'}
$commands=@('smooth on','deadband 15 22','accel yaw 400','accel pitch 400','decel yaw 600','decel pitch 600')
if($WideExperiment){
 Write-Output 'Restoring user-selected WIDE EXPERIMENT, 500..2500us is not mechanically calibrated.'
 $commands+=@('limits yaw 500 2500','limits pitch 500 2500')
}
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+=@('status','motion')
$smoothRestoreArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','2')
foreach($command in $commands){$smoothRestoreArgs+=@('--command',$command)}
$result=& python @smoothRestoreArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){throw 'Smooth profile restore failed'}
if(-not($result -match '^MOTION smooth=1 deadband=15/22 accel=400,400 decel=600,600')){throw 'Smooth profile not confirmed'}
if($EnableAuto -and -not($result -match '^mode=auto .*en=3 ')){throw 'Auto not confirmed'}
