param([switch]$Rollback,[string]$Project='build/component_tracker_v2',[string]$Workspace='build/component_tracker_v2_sw')
$ErrorActionPreference='Stop'
if($Rollback){
 & "$PSScriptRoot/download_pan_tilt.ps1" -Project 'build/pan_tilt_stable_box_v2' -Workspace 'build/pan_tilt_stable_box_v2_sw'
}else{
 & "$PSScriptRoot/download_pan_tilt.ps1" -Project $Project -Workspace $Workspace
}
if($LASTEXITCODE){throw 'Component download/rollback failed'}
