param([string]$Port='COM6',[switch]$EnableAuto)
$ErrorActionPreference='Stop'
# These values were tested on this mounting/wiring. Recheck direction and
# mechanical clearance after changing the fixture. Default restores PWM OFF.
$commands=@('manual','disable','dir yaw -1','dir pitch 1',
 'limits yaw 1450 1550','limits pitch 1480 1560',
 'center yaw 1500','center pitch 1520','gain yaw 0.3','gain pitch 0.3',
 'rate yaw 25','rate pitch 25','deadband 15','center')
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+='status'
$panSerialArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','2')
foreach($command in $commands){$panSerialArgs+=@('--command',$command)}
$result=& python @panSerialArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){throw 'Firmware rejected calibration or serial command failed'}
if($EnableAuto){
 if(-not($result -match '^auto on:') -or -not($result -match '^mode=auto .*en=3 ')){throw 'Automatic mode not confirmed'}
}elseif(-not($result -match '^mode=manual .*en=0 ')){throw 'Manual/PWM OFF not confirmed'}
Write-Output 'PAN_CALIBRATION: PASS; settings are volatile and must be reapplied after download/reset.'
