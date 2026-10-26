param([string]$Port='COM5',[switch]$EnableAuto,[switch]$DisableOutputs)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if($DisableOutputs){
 & python "$PSScriptRoot/pan_tilt_serial.py" --port $Port --command disable --command status --listen 1
 if($LASTEXITCODE){throw 'PWM disable command failed'}
 return
}
Write-Output 'EXPERIMENT: calibrated mechanical limits removed; 500..2500us firmware bounds remain. This range is NOT mechanically calibrated.'
# No center or position command: retain the current pulse/pose when opening bounds.
# The user explicitly requested overriding mechanical calibration for this test.
# Existing firmware requires its operator-acknowledgement bits for auto; using
# verify below is an experimental override, NOT evidence of mechanical validation.
$commands=@('manual','limits yaw 500 2500','limits pitch 500 2500',
 'gain yaw 0.7','gain pitch 0.7','rate yaw 75','rate pitch 75')
if($EnableAuto){$commands+=@('verify yaw','verify pitch','auto')}
$commands+=@('status','pwm')
$wideSerialArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','3',
 '--log',"$repo/build/component_wide_range_experiment_20261026.txt")
foreach($command in $commands){$wideSerialArgs+=@('--command',$command)}
$result=& python @wideSerialArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){
 & python "$PSScriptRoot/pan_tilt_serial.py" --port $Port --command manual --listen 1
 throw 'Experimental configuration failed; requested manual hold. Restore normal profile before further operation.'
}
if($EnableAuto -and -not($result -match '^mode=auto .*en=3 ')){throw 'Both axes must already be enabled; no enable/center command was issued'}
if(-not($result -match '^yaw limits=500\.\.2500') -or -not($result -match '^pitch limits=500\.\.2500')){throw 'Wide bounds not acknowledged'}
Write-Output 'WIDE_RANGE_EXPERIMENT: CONFIG_APPLIED, MECHANICALLY_UNCALIBRATED; normal profile unchanged.'
