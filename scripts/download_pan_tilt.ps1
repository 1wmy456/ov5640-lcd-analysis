param([string]$Project='build/pan_tilt_tracking_release',
 [string]$Workspace='build/pan_tilt_sw_release',
 [switch]$Rollback,
 [string]$Application='app_compiled',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
if($Rollback){& "$PSScriptRoot/download_blue_tracker.ps1" -Mode 2 -Profile calibrated -Xsct $Xsct;return}
$repo=Split-Path $PSScriptRoot -Parent
$bit=Join-Path $repo "$Project/ov5640_lcd.runs/impl_1/system_wrapper.bit"
$init=Join-Path $repo "$Workspace/board_platform/hw/ps7_init.tcl"
$elf=Join-Path $repo "$Workspace/$Application/ov5640_lcd.elf"
$xsa=Join-Path $repo "$Project/system_wrapper.xsa"
$platformXsa=Join-Path $repo "$Workspace/board_platform/hw/system_wrapper.xsa"
foreach($artifact in @($bit,$init,$elf,$xsa,$platformXsa)){if(-not(Test-Path -LiteralPath $artifact -PathType Leaf)){throw "Missing artifact $artifact"}}
if((Get-FileHash -LiteralPath $xsa).Hash -ne (Get-FileHash -LiteralPath $platformXsa).Hash){throw 'Hardware XSA and application BSP do not match; refusing mixed-version download'}
$manifest=Get-Content -Raw -LiteralPath (Join-Path $repo "$Workspace/$Application/build_manifest.json") | ConvertFrom-Json
if((Get-FileHash -LiteralPath $elf).Hash.ToLowerInvariant() -ne $manifest.elf_sha256){throw 'ELF differs from recorded compilation'}
$result=& $Xsct "$PSScriptRoot/program_blue_tracker_board.tcl" $bit $init $elf 2>&1
$result | Set-Content -Encoding UTF8 "$repo/build/download_pan_tilt.txt"
$result | Write-Output
if($LASTEXITCODE -or -not($result -match '^BOARD_PROGRAM: JTAG download and application start completed')){throw 'JTAG program/start failed'}
Write-Output 'New firmware starts MANUAL, PWM OFF. No nonvolatile programming performed.'
