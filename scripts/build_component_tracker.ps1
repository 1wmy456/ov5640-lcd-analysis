param([string]$Project='build/component_tracker_release',
 [string]$Workspace='build/component_tracker_sw',
 [string]$VivadoBin='C:/Xilinxx/Vivado/2020.2/bin',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
Set-Location $repo
if((Test-Path -LiteralPath $Project) -or (Test-Path -LiteralPath $Workspace)){throw 'Use fresh output paths; retained releases are never overwritten'}
& "$PSScriptRoot/sim_component_tracker.ps1" -VivadoBin $VivadoBin
if($LASTEXITCODE){throw 'Component/video/PWM/control regression failed'}
$result=& "$VivadoBin/vivado.bat" -mode batch -source "$PSScriptRoot/integrate_pan_tilt.tcl" -tclargs -apply -components -out $Project 2>&1
$result | Set-Content -Encoding UTF8 "$repo/build/component_integrate.log"
if($LASTEXITCODE -or -not($result -match '^PAN_INTEGRATION: PASS')){throw 'Component BD integration failed'}
$auditArgs=@("$PSScriptRoot/audit_pan_tilt.py",$Project,'--components')
if(Test-Path -LiteralPath "$repo/build/component_baseline_20261026"){$auditArgs+=@('--snapshot',"$repo/build/component_baseline_20261026")}
& python @auditArgs
if($LASTEXITCODE){throw 'Preservation and wiring audit failed'}
$result=& "$VivadoBin/vivado.bat" -mode batch -source "$PSScriptRoot/build_blue_tracker_board.tcl" -tclargs $Project 2>&1
$result | Set-Content -Encoding UTF8 "$repo/build/component_build.log"
if($LASTEXITCODE -or -not($result -match '^BOARD_BUILD: PASS')){throw 'Component implementation/timing gate failed'}
$result=& $Xsct "$PSScriptRoot/build_pan_tilt_app.tcl" "$Project/system_wrapper.xsa" $Workspace 2>&1
$result | Set-Content -Encoding UTF8 "$repo/build/component_app.log"
if($LASTEXITCODE -or -not($result -match '^BOARD_APP: PASS application rebuilt')){throw 'Fresh component BSP/ELF build failed'}
python "$PSScriptRoot/record_pan_tilt_build.py" --project $Project --workspace $Workspace --output "$repo/docs/evidence/component_tracker"
if($LASTEXITCODE){throw 'Compiled-source/artifact evidence mismatch'}
Copy-Item -LiteralPath "$repo/build/component_tracker_sim/components.txt","$repo/build/component_tracker_sim/runtime.txt","$repo/build/component_tracker_sim/video.txt","$repo/build/component_tracker_sim/mask_words.txt" -Destination "$repo/docs/evidence/component_tracker"
Write-Output "COMPONENT_BUILD: PASS $Project $Workspace; manual PWM OFF"
