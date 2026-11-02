param([string]$Workspace='build/touch_capture_v3_sw',[switch]$EnableAuto,[switch]$WideExperiment,[switch]$Conservative,[switch]$Moderate,[switch]$Responsive,[switch]$Faster,
 [string]$Xsct='C:/Xilinxx/Vitis/2020.2/bin/xsct.bat')
$ErrorActionPreference='Stop'
if(([int]$Conservative.IsPresent+[int]$Moderate.IsPresent+[int]$Responsive.IsPresent+[int]$Faster.IsPresent) -gt 1){throw 'Choose one motion profile'}
$repo=Split-Path $PSScriptRoot -Parent
$header=Join-Path $repo "$Workspace/board_platform/ps7_cortexa9_0/standalone_domain/bsp/ps7_cortexa9_0/include/xparameters.h"
$base=[regex]::Match((Get-Content -Raw $header),'(?m)^#define XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR (0x[0-9a-fA-F]+)')
if(-not $base.Success){throw 'Fresh BSP peripheral macro missing'}
$commands=@('manual','disable','dir yaw -1','dir pitch 1')
if($WideExperiment){$commands+=@('limits yaw 500 2500','limits pitch 500 2500')}else{$commands+=@('limits yaw 1100 1650','limits pitch 1240 1800')}
$commands+=@('center yaw 1500','center pitch 1520','smooth on','deadband 15 22','accel yaw 400','accel pitch 400',
 'decel yaw 600','decel pitch 600','rate yaw 75','rate pitch 75','kp yaw 0.7','kp pitch 0.7','ki yaw 0','ki pitch 0',
 'kd yaw 0.03','kd pitch 0.03','dtau yaw 100','dtau pitch 100','controller pd')
# No center/yaw/pitch motion command: keep actual current pulse values.
if($Conservative){$commands+=@('kp yaw 0.25','kp pitch 0.25','kd yaw 0','kd pitch 0','rate yaw 25','rate pitch 25',
 'accel yaw 100','accel pitch 100','decel yaw 200','decel pitch 200')}
if($Moderate){$commands+=@('kp yaw 0.4','kp pitch 0.4','kd yaw 0','kd pitch 0','rate yaw 45','rate pitch 45',
 'accel yaw 200','accel pitch 200','decel yaw 400','decel pitch 400')}
if($Responsive){$commands+=@('kp yaw 1.5','kp pitch 1.5','kd yaw 0','kd pitch 0','rate yaw 100','rate pitch 100',
 'accel yaw 500','accel pitch 500','decel yaw 800','decel pitch 800')}
if($Faster){$commands+=@('kp yaw 2','kp pitch 2','kd yaw 0','kd pitch 0','rate yaw 150','rate pitch 150',
 'accel yaw 800','accel pitch 800','decel yaw 1200','decel pitch 1200')}
if($EnableAuto){$commands+=@('enable both','verify yaw','verify pitch','auto')}
$commands+=@('pid','appearance','status')
$file=Join-Path $repo build/restore_touch_commands.txt
[IO.File]::WriteAllLines($file,$commands,[Text.Encoding]::ASCII)
& $Xsct "$PSScriptRoot/pan_tilt_jtag_batch.tcl" $base.Groups[1].Value $file
if($LASTEXITCODE){throw 'Touch PD profile restore failed'}
