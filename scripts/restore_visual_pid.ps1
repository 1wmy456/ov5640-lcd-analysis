param([string]$Port='COM5',[ValidateSet('p','pd','pid')][string]$Controller='pd',
 [double]$Kp=0.7,[double]$Ki=0,[double]$Kd=0.03,[switch]$EnableAuto,
 [switch]$WideExperiment,[string]$Session)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
if([double]::IsNaN($Kp) -or [double]::IsNaN($Ki) -or [double]::IsNaN($Kd) -or
   $Kp -lt 0 -or $Kp -gt 2 -or $Ki -lt 0 -or $Ki -gt 0.5 -or $Kd -lt 0 -or $Kd -gt 1){throw 'PID gains outside firmware bounds'}
$commands=@('manual','disable','dir yaw -1','dir pitch 1')
if($WideExperiment){
 Write-Output 'Wide experiment 500..2500us is not a mechanically calibrated range.'
 $commands+=@('limits yaw 500 2500','limits pitch 500 2500')
}else{$commands+=@('limits yaw 1100 1650','limits pitch 1240 1800')}
$commands+=@('center yaw 1500','center pitch 1520','smooth on','deadband 15 22',
 'accel yaw 400','accel pitch 400','decel yaw 600','decel pitch 600',
 'rate yaw 75','rate pitch 75','dtau yaw 100','dtau pitch 100',
 'dlimit yaw 1000','dlimit pitch 1000','imax yaw 10','imax pitch 10')
$ci=[System.Globalization.CultureInfo]::InvariantCulture
foreach($axis in @('yaw','pitch')){
 $commands+=@("kp $axis $($Kp.ToString($ci))","ki $axis $($Ki.ToString($ci))","kd $axis $($Kd.ToString($ci))")
}
$commands+="controller $Controller"
if($Session){
 $sessionState=Get-Content -Raw -LiteralPath (Join-Path $repo $Session) | ConvertFrom-Json
 $commands+=@("yaw $($sessionState.yaw_us)","pitch $($sessionState.pitch_us)")
}else{$commands+='center'}
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+=@('status','motion','pid')
$serialArgs=@("$PSScriptRoot/pan_tilt_serial.py",'--port',$Port,'--listen','3')
foreach($entry in $commands){$serialArgs+=@('--command',$entry)}
$result=& python @serialArgs 2>&1
$result | Write-Output
if($LASTEXITCODE -or ($result -match '^(invalid command|auto refused|AUTO DISABLED)')){throw 'PID restore failed'}
if(-not($result -match "^PID controller=$Controller ")){throw 'Controller mode not confirmed'}
if($EnableAuto -and -not($result -match '^mode=auto .*en=3 ')){throw 'Auto not confirmed'}
Write-Output "VISUAL_PID_PROFILE: PASS; controller=$Controller Kp=$Kp Ki=$Ki Kd=$Kd; volatile, restore after reset."
