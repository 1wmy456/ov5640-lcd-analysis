param([string]$Port='COM5',
 [string]$Session='build/smooth_baseline_20261026/session.json',
 [switch]$EnableAuto,[switch]$LegacyFirmware)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$state=Get-Content -Raw -LiteralPath (Join-Path $repo $Session) | ConvertFrom-Json
$commands=@('manual','disable')
if($state.wide_experiment){
 Write-Output 'Restoring previously requested wide-range EXPERIMENT; not a mechanical calibration.'
 $commands+=@('limits yaw 500 2500','limits pitch 500 2500')
}else{$commands+=@('limits yaw 1100 1650','limits pitch 1240 1800')}
$commands+=@('dir yaw -1','dir pitch 1','center yaw 1500','center pitch 1520',
 'gain yaw 0.7','gain pitch 0.7','rate yaw 75','rate pitch 75')
if(-not $LegacyFirmware){$commands+=@('smooth on','deadband 15 22','accel yaw 400','accel pitch 400','decel yaw 600','decel pitch 600')}
$commands+=@("yaw $($state.yaw_us)","pitch $($state.pitch_us)")
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+='status'
if(-not $LegacyFirmware){$commands+='motion'}
$resumeArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','3')
foreach($command in $commands){$resumeArgs+=@('--command',$command)}
$result=& python @resumeArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){throw 'Session resume command failed'}
if($EnableAuto -and -not($result -match '^mode=auto .*en=3 ')){throw 'Automatic mode not confirmed'}
if(-not $LegacyFirmware -and -not($result -match '^MOTION smooth=1 deadband=15/22')){throw 'Smooth firmware/configuration not confirmed'}
