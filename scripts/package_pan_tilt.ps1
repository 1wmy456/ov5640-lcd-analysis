param([string]$Project='build/pan_tilt_tracking_release',
 [string]$Workspace='build/pan_tilt_sw_release',
 [string]$Output='build/pan_tilt_release.zip')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$zip=[IO.Path]::GetFullPath((Join-Path $repo $Output))
$buildRoot=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if(-not $zip.StartsWith($buildRoot,[StringComparison]::OrdinalIgnoreCase)){throw 'Package must be under build/'}
$stage=[IO.Path]::ChangeExtension($zip,$null)+'_bundle'
if((Test-Path -LiteralPath $zip) -or (Test-Path -LiteralPath $stage)){throw 'Choose a fresh package name; existing releases are preserved'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project (Join-Path $repo $Project) --workspace (Join-Path $repo $Workspace)
if($LASTEXITCODE){throw 'Artifact/source evidence check failed'}
New-Item -ItemType Directory -Path "$stage/hardware","$stage/software","$stage/scripts","$stage/docs","$stage/rollback" | Out-Null
Copy-Item -LiteralPath "$repo/$Project/ov5640_lcd.runs/impl_1/system_wrapper.bit","$repo/$Project/system_wrapper.xsa","$repo/$Workspace/board_platform/hw/ps7_init.tcl" -Destination "$stage/hardware"
Copy-Item -LiteralPath "$repo/$Workspace/app_compiled/ov5640_lcd.elf","$repo/$Workspace/app_compiled/ov5640_lcd.map","$repo/$Workspace/app_compiled/build_manifest.json" -Destination "$stage/software"
Copy-Item -LiteralPath "$repo/$Workspace/board_platform/ps7_cortexa9_0/standalone_domain/bsp" -Destination "$stage/software/bsp" -Recurse
Copy-Item -LiteralPath "$PSScriptRoot/program_blue_tracker_board.tcl","$PSScriptRoot/pan_tilt_serial.py","$PSScriptRoot/restore_pan_tilt_calibration.ps1" -Destination "$stage/scripts"
Copy-Item -LiteralPath "$repo/docs/PAN_TILT_TRACKING.md","$repo/docs/PAN_TILT_REGISTERS.md" -Destination "$stage/docs"
Copy-Item -LiteralPath "$repo/docs/evidence/pan_tilt" -Destination "$stage/docs/evidence" -Recurse
$oldBit="$repo/build/tracker_cal_mode2_final/ov5640_lcd.runs/impl_1/system_wrapper.bit"
$oldElf="$repo/build/board_mode0_sw/app_compiled/ov5640_lcd.elf"
$oldInit="$repo/build/board_mode0_sw/board_platform/hw/ps7_init.tcl"
if((Test-Path -LiteralPath $oldBit) -and (Test-Path -LiteralPath $oldElf) -and (Test-Path -LiteralPath $oldInit)){
 Copy-Item -LiteralPath $oldBit,$oldElf,$oldInit -Destination "$stage/rollback"
}
$instructions=@'
Current hardware/application: manual, PWM OFF after reset. COM6 115200 8N1.
Run from the extracted package folder:
C:/Xilinxx/Vitis/2020.2/bin/xsct.bat scripts/program_blue_tracker_board.tcl hardware/system_wrapper.bit hardware/ps7_init.tcl software/ov5640_lcd.elf
./scripts/restore_pan_tilt_calibration.ps1 -Port COM6
The restore command leaves PWM OFF. For the unchanged, verified fixture:
./scripts/restore_pan_tilt_calibration.ps1 -Port COM6 -EnableAuto
This explicitly enables both outputs and returns to configured centers.
Use `manual` to hold or `disable` to turn off. No flash programming.
Verified narrow limits: yaw1450..1550, pitch1480..1560 us. Large excursions can hit limits.
If rollback/ contains the retained previous MODE2 bit/ELF, use the same programmer with rollback/ paths. Turn off servo power when using the old version, which has no servo outputs.
See docs/evidence/BOARD_VALIDATION.md for actual field results and unresolved video freeze history.
'@
$instructions | Set-Content -Encoding UTF8 "$stage/READ_ME.txt"
Compress-Archive -Path "$stage/*" -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -LiteralPath $zip | Format-List Algorithm,Hash,Path
Write-Output "PAN_PACKAGE: PASS $zip"
