param(
    [ValidateSet('baseline','0','1','2')][string]$Mode = '2',
    [ValidateSet('calibrated','initial')][string]$Profile = 'calibrated',
    [string]$Xsct = 'C:/Xilinxx/Vitis/2020.2/bin/xsct.bat'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if ($Mode -eq 'baseline') {
    $bit = Join-Path $repo 'build/board_baseline_artifacts/system_wrapper.bit'
    $init = Join-Path $repo 'build/board_baseline_artifacts/ps7_init.tcl'
    $elf = Join-Path $repo 'build/board_baseline_app/ov5640_lcd.elf'
} else {
    $projectName = "tracker_board_mode$Mode"
    if ($Profile -eq 'calibrated' -and $Mode -ne '0') { $projectName = "tracker_cal_mode$Mode" }
    if ($Profile -eq 'calibrated' -and $Mode -eq '2') { $projectName = 'tracker_cal_mode2_final' }
    $bit = Join-Path $repo "build/$projectName/ov5640_lcd.runs/impl_1/system_wrapper.bit"
    $init = Join-Path $repo 'build/board_mode0_sw/board_platform/hw/ps7_init.tcl'
    $elf = Join-Path $repo 'build/board_mode0_sw/app_compiled/ov5640_lcd.elf'
}
foreach ($artifact in @($bit,$init,$elf)) {
    if (-not (Test-Path -LiteralPath $artifact -PathType Leaf)) { throw "Artifact missing: $artifact" }
}
$result = & $Xsct "$PSScriptRoot/program_blue_tracker_board.tcl" $bit $init $elf 2>&1
$result | Set-Content -Encoding UTF8 "$repo/build/download_$Mode.txt"
$result | Write-Output
# XSCT 2020.2 may exit 0 even after a Tcl error; require our success marker.
if ($LASTEXITCODE -or -not ($result -match '^BOARD_PROGRAM: JTAG download and application start completed')) {
    throw 'Download/start failed. Read the log; do not treat exit code 0 as success.'
}
