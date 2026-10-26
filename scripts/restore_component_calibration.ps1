param([string]$Port='COM5',[switch]$EnableAuto)
$ErrorActionPreference='Stop'
# Confirmed on 2026-10-26 in docs/evidence/component_tracker/BOARD_VALIDATION.md.
# Keep the legacy restore script unchanged for rollback. Recheck after remounting.
$commands=@('manual','disable','vision','dir yaw -1','dir pitch 1',
 'limits yaw 1350 1650','limits pitch 1390 1650',
 'center yaw 1500','center pitch 1520','gain yaw 0.3','gain pitch 0.3',
 'rate yaw 25','rate pitch 25','deadband 15','center')
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+='status'
$componentSerialArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','2')
foreach($command in $commands){$componentSerialArgs+=@('--command',$command)}
$result=& python @componentSerialArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){throw 'Component calibration/firmware command failed'}
if(-not($result -match '^VISION mask_frame=')){throw 'Component firmware not confirmed'}
if($EnableAuto){
 if(-not($result -match '^auto on:') -or -not($result -match '^mode=auto .*en=3 ')){throw 'Auto mode not confirmed'}
}elseif(-not($result -match '^mode=manual .*en=0 ')){throw 'Manual/PWM OFF not confirmed'}
Write-Output 'COMPONENT_CALIBRATION: PASS; volatile yaw1350..1650 pitch1390..1650; reapply after reset.'
