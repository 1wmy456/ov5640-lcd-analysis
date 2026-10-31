param([string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$release=Join-Path $repo 'build/releases/lost'
$manifest=Get-Content -Raw "$release/release.json" | ConvertFrom-Json
foreach($name in @('system_wrapper.bit','system_wrapper.xsa','bsp_system_wrapper.xsa','ps7_init.tcl','ov5640_lcd.elf')){
 if((Get-FileHash -LiteralPath "$release/$name").Hash.ToLowerInvariant() -ne $manifest.files.$name){throw "lost hash mismatch: $name"}
}
& $Xsct "$PSScriptRoot/program_blue_tracker_board.tcl" "$release/system_wrapper.bit" "$release/ps7_init.tcl" "$release/ov5640_lcd.elf"
if($LASTEXITCODE){throw 'lost download failed'}
Write-Output 'lost restored: accepted visual PD-capable firmware, startup MANUAL/PWM OFF. Use restore_visual_pid.ps1 for runtime settings.'
