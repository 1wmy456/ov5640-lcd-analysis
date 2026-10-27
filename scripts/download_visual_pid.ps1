param([switch]$Rollback,[string]$Workspace='build/visual_pid_sw')
$ErrorActionPreference='Stop'
if($Rollback){$Workspace='build/smooth_tracker_sw'}
& "$PSScriptRoot/download_pan_tilt.ps1" -Project 'build/component_tracker_v2' -Workspace $Workspace
if($LASTEXITCODE){throw 'Visual PID download/rollback failed'}
# No implicit motion or persistent storage writes. Original smooth ELF retained.
