param([Parameter(Mandatory=$true)][string]$Command,
 [string]$Workspace='build/pan_tilt_sw_release',
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$header=Join-Path $repo "$Workspace/board_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include/xparameters.h"
$match=[regex]::Match((Get-Content -Raw -LiteralPath $header),'(?m)^#define XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR (0x[0-9A-Fa-f]+)')
if(-not $match.Success){throw 'Fresh BSP peripheral address macro missing'}
$result=& $Xsct "$PSScriptRoot/pan_tilt_jtag_command.tcl" $match.Groups[1].Value $Command 2>&1
$result | Write-Output
if($LASTEXITCODE -or -not($result -match '^PAN_COMMAND: PASS')){throw 'Command not acknowledged successfully'}
