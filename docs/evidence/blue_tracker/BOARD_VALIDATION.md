# Zynq-7020 / 800×480 上板记录

2026-10-12，Vivado/Vitis 2020.2；开发分支 `codex/blue-tracker`。此文件记录真实工具操作与用户现场观察，不能用离线仿真替代 LCD 验收。

## 硬件与原工程

JTAG-HS1 `210512180081` 已连接，识别 arm_dap 与 xc7z020，器件ID `0x23727093`。用户确认板卡上电、LCD 800×480。原应用仍通过 LCD ID 自动配置摄像头和LCD，未编辑GPIO/驱动/模式/XDC。tracker 的尺寸是静态 RTL 参数，因此本板匹配800×480。

初次读取PL地址失败，不能说明相机故障；后来通过原XSA的bit与原源码重建ELF启动，用户确认原图正常实时更新。原启动状态S2MM曾有错误位 `0x00015910`，记录为基线现象，未无依据归因于tracker。

原XSA内bit/ps7_init提取到 `build/board_baseline_artifacts/`；原源码和链接脚本用生成的standalone BSP和Vitis GCC编译，ELF在 `build/board_baseline_app/`。程序 `_end=0x0011a570`，低于帧缓存 `0x01100000`。从MODE0新XSA再次生成BSP，`xparameters.h` 与原XSA生成文件逐字节一致；正式测试使用 `build/board_mode0_sw/app_compiled/ov5640_lcd.elf`。

Vitis模板服务在创建Empty Application时停滞，本轮改用其已生成BSP和安装自带GCC直接编译原C，源码/链接脚本逐字节保留。脚本 `build_blue_tracker_app.tcl` 已包含此可复现路径。XSCT可能在Tcl报错后仍退出0，下载脚本以明确成功标记验收，不能仅看退出码。

## 初版现场结果与改进依据

| 项目 | 实际结果 |
|---|---|
| 原基线摄像头实时显示 | 用户确认正常 |
| 初版MODE0旁路 | 用户确认与原工程一致、实时更新，无明显错行闪烁 |
| 初版MODE1掩码 | 用户确认瓶盖白色、背景基本黑色、可跟随 |
| 初版MODE2静止/移动框 | **未通过**：框过大/偏移 |
| 初版MODE2无目标清框 | **未通过**：目标移走仍有大框 |

初版现场照片和DDR采样显示，整帧包围盒把少数远处蓝色杂点也合并了。无瓶盖DDR快照仍有120个颜色候选点，超过原MIN_PIXELS=24，分散范围覆盖大半画面。单纯提高最小数量只能解决部分无目标误报，有瓶盖时杂点仍会扩大框。

用户放置单个静止瓶盖后，校准快照的默认条件产生13,013候选像素。使用 `B>2R`、BR差值60、BG差值35后，瓶盖连续区域有11,837像素，范围 x=322..465/y=190..296，另有两个相邻杂点及两个孤立点。要求行内至少3个连续蓝像素后，此快照统计为11,831像素、框范围 x=322..465/y=190..296；无目标参考快照通过该颜色条件的点为0。

这些是对真实DDR诊断数据的离线校准证据；快照采集可能跨VDMA写入，并非原子锁帧，不用它证明无撕裂或逐帧跟随。相机图像保留在被Git忽略的build目录，不把用户现场人物照片提交仓库。

现场校准参数：BLUE_MIN=80、BR_DELTA=60、BG_DELTA=35、MIN_B_R_RATIO=2、MIN_BLUE_RUN=3、MIN_PIXELS=256，边框2、无十字。默认参数仍保留最初三条件算法与整体蓝框；新增选项默认关闭，不引入连通域、舵机、Sobel或Linux。

改进后的四组XSim（默认、单像素、十字、校准）每组115,886检查、36完整帧、0失败；真实Video In async FIFO彩条2,449检查/3帧/288像素通过。新增覆盖孤立远处点、两点短段、短段跨行不能拼接、连续蓝段在末像素才合格、比例比较溢出反例。报告原文另存 `calibration_sim_*.txt`。

## 完整系统构建

初版三模式均生成bit和XSA，保持原约束，完整布局布线结果：

| 模式 | LUT | FF | BRAM tile | DSP | WNS/ns | WHS/ns |
|---|---:|---:|---:|---:|---:|---:|
| MODE0 | 6202 | 10346 | 10 | 0 | +3.257 | +0.042 |
| 初版MODE1 | 6221 | 10323 | 10 | 0 | +2.300 | +0.029 |
| 初版MODE2 | 6758 | 10605 | 10 | 0 | +0.715 | +0.029 |

TNS/THS均0。原有DRC仍有30条Warning/Advisory（BUFC-1、PLCK-12、REQP-1839、RTSTAT-10、REQP-165/181），未降级DRC，也未编辑原XDC。CDC报告列出的跨域端点均为Safe，Unsafe/Unknown均0；只覆盖当前已有约束和本800×480配置，不宣称所有LCD模式外部接口时序完善。

校准MODE1：6228 LUT、10323 FF、10 BRAM tile、0 DSP，WNS=+2.758ns、WHS=+0.048ns，TNS/THS=0。

校准MODE2首次实现 WNS=-0.427ns，脚本停止于bitstream生成之前，没有下载该时序失败版本；报告保留在 `board_cal_mode2_failed_timing.rpt`。将内部run长度与有效数量门槛改为饱和计数后，完整原始蓝色计数仍为32位，四组功能回归再次全部通过。最终MODE2资源：6707 LUT、10610 FF、10 BRAM tile、0 DSP；WNS=+0.069ns、WHS=+0.047ns，TNS/THS=0。最终bit/XSA生成并通过JTAG启动，未放宽时钟约束。

最终MODE2工程副本在 `build/tracker_cal_mode2_final/`；已验证的校准MODE1副本在 `build/tracker_cal_mode1/`。每份副本保留其实际构建RTL；MODE1未使用的框统计逻辑不影响掩码显示，最终饱和计数优化应用于MODE2。位流/XSA/软件及RTL快照哈希见 `board_artifacts.json`。

## 最终现场验收

| 验收 | 结果及证据 |
|---|---|
| A MODE0与旧工程一致 | 用户确认原图一致、实时更新正常，无明显错行闪烁 |
| B MODE1蓝瓶盖白/背景黑 | 初版与校准版均由用户确认；校准版无目标近全黑是预期掩码。初版DDR全384,000像素均为黑/白 |
| C MODE2静止定位 | 校准版用户确认绿色框正常包围瓶盖 |
| D 移动与边缘跟随 | 校准版用户确认定位、移动、边缘跟随正常 |
| E 无目标清框 | 校准版用户确认移走蓝目标后框消失；随后DDR诊断快照绿色像素为0 |
| F AXI与同步完整性 | 四组随机背压/断续valid/标志对齐自检通过；现场正常运行未报告新错行，最终VDMA读写均`0x00011000`、错误掩码`0x00000FF0`读取为0。未执行硬件随机背压注入或ILA逐像素验收 |

这些现场视觉结论由用户观察提供，工具结果由本机JTAG和Vivado/XSim记录提供。初版C/E失败没有被删除或写成成功。当前板卡留在最终校准MODE2，仍为上一完整帧目标框写入下一帧DDR的方案，未测量精确端到端显示延迟。

快照JSON的 `blue_threshold_pixels` 是诊断脚本按最初80/35/20条件统计的像素数，不是板上校准后的统计端口读数；`green` 是实际DDR中的RGB(0,255,0)像素数。最终无目标快照 `green=0`，读写VDMA状态仍为`0x00011000`。

运行目标含蓝标签或其他独立蓝物体时仍会合并整体框；细于3个连续像素或有效蓝色面积不足256的远小目标可能不出框。阈值只在本次光照/瓶盖场景校准，未宣称通用颜色、多目标准确率或长时间稳定性测试完成。最终时序满足当前约束但裕量较小；外部DVP/LCD约束缺口、其他分辨率模式的完整验证保持原报告边界。

## 下载与回退

```powershell
# 本机已生成的校准版本（默认Profile=calibrated）
./scripts/download_blue_tracker.ps1 -Mode 1
./scripts/download_blue_tracker.ps1 -Mode 2
# 原图旁路
./scripts/download_blue_tracker.ps1 -Mode 0
# 本轮已现场确认可实时显示的原工程基线
./scripts/download_blue_tracker.ps1 -Mode baseline
```

以上只通过JTAG临时配置PL并初始化PS/下载ELF，不写QSPI、SD或Flash。掉电后需按原启动方式或再次JTAG下载，不宣称已制作BOOT.BIN。

重新构建校准工程示例（输出目录必须是新的）：

```powershell
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/integrate_blue_tracker.tcl -tclargs -apply -width 800 -height 480 -mode 2 -br_delta 60 -bg_delta 35 -red_ratio 2 -min_run 3 -min_pixels 256 -out build/tracker_cal_mode2_rebuild
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/build_blue_tracker_board.tcl -tclargs build/tracker_cal_mode2_rebuild
```

需要重建软件时：`xsct scripts/build_blue_tracker_app.tcl <新XSA> <新的build工作区>`。原模式软件地址一致才可复用本轮ELF；以后改变AXI地址、PS配置或驱动相关IP应更新BSP。
