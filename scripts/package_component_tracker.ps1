param([string]$Project='build/component_tracker_v2',
 [string]$Workspace='build/component_tracker_v2_sw',
 [string]$Output='build/component_tracker_release.zip')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$zip=[IO.Path]::GetFullPath((Join-Path $repo $Output))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $zip.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Package must be under build/'}
$stage=[IO.Path]::ChangeExtension($zip,$null)+'_bundle'
if((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $stage)){throw 'Choose a fresh package name'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project "$repo/$Project" --workspace "$repo/$Workspace" --output "$repo/docs/evidence/component_tracker"
if($LASTEXITCODE){throw 'Compiled-source/artifact evidence failed'}
New-Item -ItemType Directory -Path "$stage/hardware","$stage/software","$stage/scripts","$stage/docs","$stage/rollback" | Out-Null
Copy-Item -LiteralPath "$repo/$Project/ov5640_lcd.runs/impl_1/system_wrapper.bit","$repo/$Project/system_wrapper.xsa","$repo/$Workspace/board_platform/hw/ps7_init.tcl" -Destination "$stage/hardware"
Copy-Item -LiteralPath "$repo/$Workspace/app_compiled/ov5640_lcd.elf","$repo/$Workspace/app_compiled/ov5640_lcd.map","$repo/$Workspace/app_compiled/build_manifest.json" -Destination "$stage/software"
Copy-Item -LiteralPath "$repo/$Workspace/board_platform/ps7_cortexa9_0/standalone_domain/bsp" -Destination "$stage/software/bsp" -Recurse
Copy-Item -LiteralPath "$PSScriptRoot/program_blue_tracker_board.tcl","$PSScriptRoot/pan_tilt_serial.py","$PSScriptRoot/restore_pan_tilt_calibration.ps1","$PSScriptRoot/restore_component_calibration.ps1","$PSScriptRoot/test_pan_tilt_range.py" -Destination "$stage/scripts"
Copy-Item -LiteralPath "$repo/docs/COMPONENT_TRACKER.md","$repo/docs/PAN_TILT_REGISTERS.md" -Destination "$stage/docs"
New-Item -ItemType Directory -Path "$stage/docs/evidence" | Out-Null
Copy-Item -LiteralPath "$repo/docs/evidence/component_tracker" -Destination "$stage/docs/evidence/component_tracker" -Recurse
Copy-Item -LiteralPath "$repo/build/component_baseline_20261026/rollback/system_wrapper.bit","$repo/build/component_baseline_20261026/rollback/system_wrapper.xsa","$repo/build/component_baseline_20261026/rollback/ov5640_lcd.elf","$repo/build/component_baseline_20261026/rollback/ps7_init.tcl" -Destination "$stage/rollback"
@'
Temporary JTAG download, no flash programming. Starts MANUAL, PWM OFF.
Run in this extracted folder:
C:/Xilinxx/Vitis/2020.2/bin/xsct.bat scripts/program_blue_tracker_board.tcl hardware/system_wrapper.bit hardware/ps7_init.tcl software/ov5640_lcd.elf
python scripts/pan_tilt_serial.py --port COM5 --command status --command vision --listen 4
For the previously verified, unchanged mounting/wiring only:
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto
manual = hold position; disable = turn PWM off.
Rollback to the preserved previous dual-servo firmware:
C:/Xilinxx/Vitis/2020.2/bin/xsct.bat scripts/program_blue_tracker_board.tcl rollback/system_wrapper.bit rollback/ps7_init.tcl rollback/ov5640_lcd.elf
See docs/evidence for actual timing and field verification, and pending observations.
'@ | Set-Content -Encoding UTF8 "$stage/READ_ME.txt"
Compress-Archive -Path "$stage/*" -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -LiteralPath $zip | Format-List Algorithm,Hash,Path
Write-Output "COMPONENT_PACKAGE: PASS $zip"
