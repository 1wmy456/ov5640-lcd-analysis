param([string]$Project='build/touch_stage_a_v4',[string]$Workspace='build/touch_stage_a_v4_sw',[string]$Application='app_gt1158')
$ErrorActionPreference='Stop'
& "$PSScriptRoot/download_pan_tilt.ps1" -Project $Project -Workspace $Workspace -Application $Application
if($LASTEXITCODE){throw 'Touch stage A download failed'}
