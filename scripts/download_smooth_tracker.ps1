param([switch]$Rollback,[string]$Workspace='build/smooth_tracker_sw')
$ErrorActionPreference='Stop'
if($Rollback){$Workspace='build/component_tracker_v2_sw'}
& "$PSScriptRoot/download_pan_tilt.ps1" -Project 'build/component_tracker_v2' -Workspace $Workspace
if($LASTEXITCODE){throw 'Smooth download/rollback failed'}
# Download only. Session restoration is separate; both versions start PWM OFF.
