param([string]$Port='COM5',[switch]$EnableAuto,[switch]$Conservative,
 [ValidateSet('conservative','fast','faster')][string]$Speed='faster')
$ErrorActionPreference='Stop'
# Confirmed on 2026-10-26 in docs/evidence/component_tracker/BOARD_VALIDATION.md.
# Keep the legacy restore script unchanged for rollback. Recheck after remounting.
if($Conservative){$Speed='conservative'}
switch($Speed){
 'conservative' {$speedGain='0.3';$speedRate='25'}
 'fast' {$speedGain='0.5';$speedRate='50'}
 'faster' {$speedGain='0.7';$speedRate='75'}
}
$speedLabel=$Speed
$commands=@('manual','disable','vision','dir yaw -1','dir pitch 1',
 'limits yaw 1100 1650','limits pitch 1240 1800',
 'center yaw 1500','center pitch 1520',"gain yaw $speedGain","gain pitch $speedGain",
 "rate yaw $speedRate","rate pitch $speedRate",'deadband 15','center')
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
Write-Output "COMPONENT_CALIBRATION: PASS; volatile yaw1100..1650 pitch1240..1800 speed=$speedLabel gain=$speedGain rate=$speedRate; reapply after reset."
