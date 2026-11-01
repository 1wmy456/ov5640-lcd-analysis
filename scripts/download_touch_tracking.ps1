param([string]$Project='build/touch_capture_v3',[string]$Workspace='build/touch_capture_v3_sw',[string]$Application='app_touch_timebase')
$ErrorActionPreference='Stop'
& "$PSScriptRoot/download_pan_tilt.ps1" -Project $Project -Workspace $Workspace -Application $Application
if($LASTEXITCODE){throw 'Touch tracking download failed'}
