# 双舵机版本工具验证记录

2026-10-12，Vivado/Vitis 2020.2，Zynq XC7Z020CLG400-2，基线15e98ec，新分支codex/pan-tilt-tracking。本轮实际release工程为 `build/pan_tilt_tracking_release`，软件为 `build/pan_tilt_sw_release`。构建在独立副本进行，原XPR/BD/原XDC未改变。完整原始报告在本目录tool_reports，产物路径/哈希/实际编译源见BUILD_MANIFEST.json。

## 仿真

本机使用XSim2020.2与MSYS GCC15.1，执行 `scripts/sim_pan_tilt.ps1`。不是仅静态审查。

| 项目 | 实际结果 |
|---|---|
| 纯C控制算法 | PASS PAN_CONTROL：正负误差、死区、方向反转、时间限速、限位、小数积累、重复帧、过期、丢失恢复、手动/自动切换、frame_id回绕、尺寸不符 |
| PL外设/PWM | PASS PAN_RTL checks=251 actual_100MHz_pulses=4 |
| 原蓝色/AXI视频4组回归 | 每组PASS：115886检查、36帧、0失败 |
| 原Video In颜色/异步FIFO | PASS IP_COLOR：2449检查、3帧、288像素；RGB排列R=2/G=1/B=0 |

PL自检覆盖实际100MHz下20ms周期/1500μs高电平；参数化1MHz下两轴独立宽度/统一周期提交/夹紧/关闭/单轴使能/复位；独立AW/W顺序、同时握手、WSTRB、无效地址、非法限位、B/R背压稳定；与寄存结果脉冲同周期的PS快照、快照跨多帧不变、无目标帧递增、异常清valid；邮箱禁止pending覆盖；PWM内部波形测量。原视频回归覆盖15项需求，包括AXI背压、最后蓝色像素、标志对齐和异常恢复。

首次自检暴露了测试监测器在NBA更新前读取旧生效脉宽的问题，已修复为边沿后采样；PWM输出也改为寄存器电平。最终结果为上述PASS。XSim可能在fatal后继续退出0，因此脚本同时扫描FAIL与成功标记。

## 综合/布局布线

| 项目 | 最终release实际结果 |
|---|---|
| BD Validate Design | 通过，生成新的wrapper |
| setup WNS / TNS | +0.364ns / 0；0失败端点，30810总端点 |
| hold WHS / THS | +0.015ns / 0；0失败端点，30683总端点 |
| pulse width WPWS | +2.500ns |
| 无时钟/无约束内部端点/组合环 | 均0 |
| Slice LUT | 8212 / 53200（15.44%） |
| Slice FF | 12428 / 106400（11.68%），Latch=0 |
| BRAM Tile / DSP | 10 / 2 |
| CDC | 83 Safe、0 Unsafe、0 Unknown；新增外设与tracker同域 |
| 引脚 | U5 yaw、T5 pitch，Bank13，LVCMOS33，独占；IO报告设计VCCO13=3.30V |
| DRC报告 | 0 Error，36项Warning/Advisory；原30项保留，新增6项两路常数tick乘法DSP流水建议 |

bit写出阶段默认DRC与独立report_drc规则计数不同，不将Warning/Advisory称作全清。新增DSP建议不影响本次setup/hold通过，未降级DRC或放宽时钟。原摄像头/LCD的外部IO缺少输入/输出延迟仍存在：13个输入、29个输出（含2个PWM），不能将内部时序通过说成外部接口电气时序全部验证。

## 新BSP和ELF

新XSA生成standalone BSP，自定义驱动仓库产生 `XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR=0x43C20000`、HIGHADDR=0x43C20FFF；原外设地址不变。编译器实际递归编译9个C文件，包括pan_tilt_app.c、pan_tilt_driver.c、tracking_control.c。

ELF text=109108、data=2840、bss=30416字节，`_end=0x001236F0`，低于VDMA帧缓存起点0x01100000。原链接脚本和VDMA缓冲定义保留。编译产物与当前仓库实际源哈希一致。

`scripts/audit_pan_tilt.py` 通过：55个保护文件与15e98ec逐字节相同；main.c只含3处指定修改，连原CRLF/原编码/空格保留。原BD单元参数、视频通路、地址、时钟/复位仅增加tracker及PWM外设支路；AXI interconnect在Vivado中新增M04/地址MMU，原4路coupler保留。校准值逐项核对通过。

## 上板边界

已执行临时JTAG下载与COM6读取，详见BOARD_VALIDATION.md。工具仿真和内部PWM测量不代替物理针脚示波器测量，也不代替舵机方向/限位/自动跟随的现场观察。
