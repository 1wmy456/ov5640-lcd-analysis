param([string]$VivadoBin = 'C:\Xilinxx\Vivado\2020.2\bin')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$out = Join-Path $repo 'build/blue_tracker_sim'
New-Item -ItemType Directory -Force $out | Out-Null
Push-Location $out
try {
    $rtl = @(Get-ChildItem "$repo/rtl/blue_tracker/*.v" | ForEach-Object FullName)
    & "$VivadoBin/xvlog.bat" --sv @rtl "$repo/sim/blue_tracker/tb_axis_blue_tracker.sv"
    if ($LASTEXITCODE) { throw 'xvlog failed' }
    foreach ($variant in @('default','single_pixel','cross')) {
        $top = 'tb_axis_blue_tracker'
        if ($variant -eq 'single_pixel') { $top = 'tb_single_pixel' }
        if ($variant -eq 'cross') { $top = 'tb_cross' }
        $argsList = @($top,'-s',"tracker_$variant",'-timescale','1ns/1ps')
        & "$VivadoBin/xelab.bat" @argsList
        if ($LASTEXITCODE) { throw "xelab $variant failed" }
        $result = & "$VivadoBin/xsim.bat" "tracker_$variant" -runall 2>&1
        $result | Set-Content -Encoding UTF8 "$variant.txt"
        $result | Write-Output
        if ($LASTEXITCODE -or -not ($result -match '^PASS checks=') -or ($result -match '^FAIL')) { throw "simulation $variant failed" }
    }
    $vendorRtl = Join-Path (Split-Path $VivadoBin -Parent) 'data/ip/xilinx/v_vid_in_axi4s_v4_0/hdl/v_vid_in_axi4s_v4_0_vl_rfs.v'
    $glbl = Join-Path (Split-Path $VivadoBin -Parent) 'data/verilog/src/glbl.v'
    & "$VivadoBin/xvlog.bat" --sv $vendorRtl $glbl "$repo/sim/blue_tracker/tb_video_in_color_order.sv"
    if ($LASTEXITCODE) { throw 'Video In color test compilation failed' }
    & "$VivadoBin/xelab.bat" tb_video_in_color_order glbl -L xpm -s tracker_ip_color -timescale 1ns/1ps
    if ($LASTEXITCODE) { throw 'Video In color test elaboration failed' }
    $result = & "$VivadoBin/xsim.bat" tracker_ip_color -runall 2>&1
    $result | Set-Content -Encoding UTF8 'ip_color.txt'
    $result | Write-Output
    if ($LASTEXITCODE -or -not ($result -match '^PASS IP_COLOR') -or ($result -match '^FAIL')) { throw 'Video In color test failed' }
} finally { Pop-Location }
