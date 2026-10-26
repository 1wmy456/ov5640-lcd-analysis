param([string]$Workspace='build/smooth_tracker_sw',[string]$Output='build/smooth_tracker_release.zip')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$project="$repo/build/component_tracker_v2"
$zip=[IO.Path]::GetFullPath((Join-Path $repo $Output))
$root=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $zip.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must be under build/'}
$stage=[IO.Path]::ChangeExtension($zip,$null)+'_bundle'
if((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $stage)){throw 'Choose a fresh output; old releases are retained'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project $project --workspace "$repo/$Workspace" --output "$repo/docs/evidence/smooth_tracker"
if($LASTEXITCODE){throw 'Source/ELF evidence check failed'}
New-Item -ItemType Directory -Path "$stage/hardware","$stage/software","$stage/rollback","$stage/scripts","$stage/docs" | Out-Null
Copy-Item -LiteralPath "$project/ov5640_lcd.runs/impl_1/system_wrapper.bit","$project/system_wrapper.xsa","$repo/$Workspace/board_platform/hw/ps7_init.tcl" -Destination "$stage/hardware"
Copy-Item -LiteralPath "$repo/$Workspace/app_compiled/ov5640_lcd.elf","$repo/$Workspace/app_compiled/ov5640_lcd.map","$repo/$Workspace/app_compiled/build_manifest.json" -Destination "$stage/software"
Copy-Item -LiteralPath "$repo/$Workspace/app_compiled/src" -Destination "$stage/software/src" -Recurse
Copy-Item -LiteralPath "$repo/$Workspace/board_platform/ps7_cortexa9_0/standalone_domain/bsp" -Destination "$stage/software/bsp" -Recurse
Copy-Item -LiteralPath "$repo/build/smooth_baseline_20261026/system_wrapper.bit","$repo/build/smooth_baseline_20261026/system_wrapper.xsa","$repo/build/smooth_baseline_20261026/ov5640_lcd.elf","$repo/build/smooth_baseline_20261026/ps7_init.tcl","$repo/build/smooth_baseline_20261026/session.json" -Destination "$stage/rollback"
Copy-Item -LiteralPath "$repo/build/smooth_baseline_20261026/src" -Destination "$stage/rollback/src" -Recurse
Copy-Item -LiteralPath "$PSScriptRoot/program_blue_tracker_board.tcl","$PSScriptRoot/pan_tilt_serial.py","$PSScriptRoot/restore_component_calibration.ps1","$PSScriptRoot/restore_smooth_tracker.ps1","$PSScriptRoot/resume_smooth_session.ps1" -Destination "$stage/scripts"
Copy-Item -LiteralPath "$repo/docs/SMOOTH_TRACKING.md" -Destination "$stage/docs"
Copy-Item -LiteralPath "$repo/docs/evidence/smooth_tracker" -Destination "$stage/docs/evidence" -Recurse
@'
New ELF, original video hardware. Starts MANUAL, PWM OFF.
Run from the extracted folder:
C:/Xilinxx/Vitis/2020.2/bin/xsct.bat scripts/program_blue_tracker_board.tcl hardware/system_wrapper.bit hardware/ps7_init.tcl software/ov5640_lcd.elf
./scripts/restore_smooth_tracker.ps1 -Port COM5 -EnableAuto
The above uses calibrated bounds. For the user's ongoing uncalibrated wide-range experiment, append -WideExperiment.
UART: motion | smooth off | smooth on | accel yaw 400 | decel yaw 600 | deadband 15 22
manual holds immediately; disable turns PWM off.
Full rollback to the previous ELF:
C:/Xilinxx/Vitis/2020.2/bin/xsct.bat scripts/program_blue_tracker_board.tcl rollback/system_wrapper.bit rollback/ps7_init.tcl rollback/ov5640_lcd.elf
./scripts/resume_smooth_session.ps1 -Port COM5 -Session rollback/session.json -EnableAuto -LegacyFirmware
The rollback session restores the previous wide-range experiment and pre-change pulse positions.
See docs/evidence for actual tests and field observations. No flash programming.
'@ | Set-Content -Encoding UTF8 "$stage/READ_ME.txt"
Compress-Archive -Path "$stage/*" -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -LiteralPath $zip | Format-List Algorithm,Hash,Path
Write-Output "SMOOTH_PACKAGE: PASS $zip"
