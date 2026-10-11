# 项目分析

分析日期：2026-10-11。依据：本地源码、工程 XML、Block Design JSON、生成 RTL、现有 BSP 参数及历史实现报告。以下行号指原始文件；UTF-8 阅读副本保持相同行数。

## 1. 项目做什么

OV5640 通过 8 位 DVP 输出 RGB565，每个像素占两个 PCLK 周期。`ov5640_capture_data` 将两个字节拼成 16 位像素，再补零扩展成 RGB888。Video In IP 转换为 AXI4-Stream，VDMA S2MM 经 PS HP0 写入 DDR；MM2S 从帧缓存读出，Video Out 与 VTC 合成视频时序，`rgb2lcd` 连接 24 位 RGB LCD。

软件根据 LCD RGB 引脚上的 3 位 ID 选择分辨率，利用 EMIO 软件 SCCB 配置摄像头，并启动 VDMA、动态重配像素时钟、启动 VTC。工程不是 Linux 摄像头驱动项目，没有图像算法、网络传输或用户界面。

## 2. 硬件与地址

| 项目 | 从工程中读取的值 |
| --- | --- |
| FPGA | `xc7z020clg400-2` |
| PS CPU | Cortex-A9，配置实际频率约 666.667 MHz |
| DDR | PS 配置 DDR3L `MT41K256M16 RE-125`，地址空间高地址 `0x3FFFFFFF` |
| AXI/PL 主时钟 | PS FCLK0 100 MHz |
| 摄像头时钟约束 | `cam_pclk` 周期 13.888 ns，约 72 MHz |
| 默认 LCD 像素时钟 | Clock Wizard 工程值约 33.333 MHz，软件运行时重配 |
| LCD ID GPIO | `0x41200000`，3 位 |
| AXI VDMA | `0x43000000`，3 帧，MM2S 流宽 24 位 |
| Clock Wizard | `0x43C00000`，启用动态重配 |
| VTC | `0x43C10000`，生成器模式 |
| DDR 连接 | VDMA 两个内存端口经 AXI Interconnect 接 PS HP0 |

配置依据：`ov5640_lcd.srcs/sources_1/bd/system/system.bd`。完整参数摘录在 `docs/evidence/design_summary.json`，BSP 参数快照在 `docs/evidence/xparameters.h`。实际开发板型号、LCD 型号和原理图未提供，不能从器件型号推断。

三个时钟域分别是摄像头 PCLK、100 MHz AXI 域、可重配的 LCD 像素时钟域。两个视频转换 IP 均启用了异步时钟模式；这提供了跨域结构，但仍需检查复位释放、FIFO 控制和 CDC 报告。

## 3. 软件启动顺序

入口 `vitis/ov5640_lcd/src/main.c:37`：

1. 初始化 AXI GPIO，设为输入，读取 LCD ID，再切成输出，让 LCD RGB 引脚输出视频。
2. 选择摄像头有效宽高和 HTS/VTS。
3. 初始化 EMIO，读取 `0x300A/0x300B`，要求传感器 ID 为 `0x5640`。
4. 软件复位 OV5640，写入镜头校正、色彩、曝光、RGB565 格式、输出尺寸与 PLL 参数。
5. 选择 LCD `VideoMode`，启动 VDMA 双向传输。
6. 动态重配 Clock Wizard；等待 locked。
7. 初始化 VTC、设置模式并开始输出；随后 `main()` 返回。

SCCB 的 `0x78` 是代码使用的写地址字节，读操作使用 `0x79`，不要把它与读出的芯片 ID `0x5640` 混淆。

## 4. LCD 模式与缓存

缓存实际基址为 **`0x01100000`**：BSP 的 `XPAR_PS7_DDR_0_S_AXI_BASEADDR` 为 `0x00100000`，`main.c:27` 再加 `0x01000000`。不是简单的 `0x01000000`。

`vdma_api.c:182` 用硬件 MM2S 流宽计算行字节数，目前为 `width × 3`。每个方向的缓冲地址循环均从同一基址开始，递增 `width × height × 3`，帧数来自驱动 `MaxNumFrames`，当前 BSP 为 3。`main.c` 的 `BYTES_PIXEL` 和 `FRAME_BUFFER_NUM` 宏没有参与实际配置。

| LCD ID | 分辨率 | 相机 HTS/VTS | LCD 时钟 MHz | 每帧字节 | 三帧字节 | 按当前 VTC 代码计算的刷新率 Hz |
| --- | --- | --- | --- | --- | --- | --- |
| `0x4342` | 480×272 | 1800/1000 | 9 | 391680 | 1175040 | 59.618 |
| `0x4384` / `0x7084` | 800×480 | 1800/1000 | 33 | 1152000 | 3456000 | 59.354 |
| `0x7016` | 1024×600 | 2200/1000 | 50 | 1843200 | 5529600 | 58.451 |
| `0x1018` | 1280×800 | 2570/980 | 70 | 3072000 | 9216000 | 58.953 |

未知 ID 默认使用 800×480，但会打印 ID 0，可能掩盖识别失败。另有其他 `VideoMode` 常量，本项目的主函数没有选择它们。

刷新率计算依据 `display_ctrl.c:149,154`：后肩额外加 1，因此总行长度为 `hmax+1`，总帧行数为 `vmax+1`，使用 `freq×10^6/((hmax+1)(vmax+1))`。表中是软件目标值计算结果，不是示波器实测；Clock Wizard 分频量化还会产生小偏差。

在 1280×800、约 60 fps 的简化估算下，单方向有效像素流量约 184.32 MB/s，读写合计约 368.64 MB/s，不包括总线开销。摄像头帧率未实测，不能直接用 PCLK 除以 HTS/VTS 当作最终事实，应核实 RGB565 双字节时序及各分频寄存器。

## 5. 已确认的问题

### P1：外部接口时序未完整约束，且最高像素时钟模式没有实现证据

`lcd.xdc` 定义了 PCLK 并配置引脚，但没有输入/输出 delay。历史 routed timing report 明确记录 **13 个输入无 input delay、27 个输出无 output delay**。这是确认的约束缺口，不能根据内部 WNS 为正推断板级采样一定正确。

历史报告仅列出 LCD 33.333 MHz；软件会设置 9/33/50/70 MHz。现有静态时序结果不能直接证明 50/70 MHz 模式也收敛。后续需要根据板卡和器件时序补齐外部约束，并覆盖最高运行频率。

### P1：PCLK 采用非专用时钟路由豁免

`lcd.xdc:4`：`CLOCK_DEDICATED_ROUTE FALSE`。历史 DRC 的 PLCK-12 和实现日志 `[Place 30-574]` 直接确认 IO 到 BUFG 的放置问题被降级。需结合板卡原理图判断 PCLK 引脚是否可改、是否需要不同采样结构；目前只能确认工程采用豁免，不能据此断言已出现黑屏。

### P1：时钟配置存在空指针和无限等待路径

`clk_wiz.c:42-43` 查找配置后直接解引用，没有 NULL 检查，初始化返回值也未检查。`clk_wiz.c:59-63` 无限等待 locked，没有超时、错误码或故障日志。IP ID 错误或重配失败时可异常退出或挂住；当前 IP ID 配置正常不代表故障路径安全。

### P1：初始化失败后仍继续启动

`main.c:45` 忽略 GPIO 初始化返回值；摄像头初始化失败只打印信息，仍继续后续启动。`main.c:114-123` 未检查 VDMA、DisplayInitialize、DisplaySetMode、DisplayStart 返回值。应逐层返回具体错误并停止依赖失败步骤的启动，便于区分摄像头、时钟、DMA 和显示故障。

### P2：帧缓存未在链接脚本中保留

`lscript.ld:26` 允许应用使用 `0x00100000` 起的整个 DDR 区域，没有为 `0x01100000` 起的帧缓存单独保留区域或链接期边界检查。当前小程序是否实际重叠要看 map/ELF；随着应用或堆增长存在覆盖风险。建议明确划分应用与 framebuffer MEMORY 区域并检查总大小。

### P2：SCCB ACK 周期没有采样应答

`emio_sccb_cfg.c:134-152` 切换 SDA 为输入并生成第 9 个时钟，但没有读取 SDA；写寄存器函数也没有返回通信状态。芯片 ID 检查能发现部分通信失败，但后续大量写配置无法确认成功。SCCB 的应答处理需要结合 OV5640 协议说明判断，不应机械套用所有 I²C 规则。

### P2：时钟日志格式与数据类型不匹配

`main.c:112` 用 `%d` 打印 `vd_mode.freq`，而 `lcd_modes.h:36` 定义该字段为 `double`。可变参数类型不匹配会导致错误日志，不能依赖该输出判断实际时钟。可用明确的整数 Hz/kHz 转换打印，或使用确实支持浮点的输出函数。

### P2：VDMA 错误中断启用，但应用没有处理路径

`vdma_api.c` 即使关闭帧计数中断也启用 error interrupt；`main.c` 中没有建立 GIC/ISR 或持续轮询。软件启动后无法持续报告 DMA 错误。应选择配置完整中断，或增加状态轮询及错误寄存器输出。

## 6. 需要进一步验证的疑点

| 疑点 | 已有证据 | 下一步验证 |
| --- | --- | --- |
| RGB/BGR 顺序 | 采集 RTL 形成 `{R,G,B}`；RGB LCD ID 使用位 23/15/7 | 查看两个视频 IP 的字节/分量映射，使用相机彩条验证红蓝 |
| 帧首行首数据对齐 | HREF/VSYNC 延迟两级，RGB565 在每两字节更新，`vid_ce` 由延迟 byte_flag 控制 | 用连续不同色像素建立波形，检查首尾像素、奇数行字节和帧间消隐 |
| 启动等待帧数 | frame_cnt 满 WAIT_FRAME 后，下一个 VSYNC 才置 wait_done | 默认 10 在第 11 次检测上升沿开放输出，需确认设计意图；不是未经分析的 off-by-one 定论 |
| 撕裂与帧同步 | 同地址三缓冲，读写均 EnableSync=1，FrameDelay=0；BSP 有内部 genlock、MM2S mode=3、S2MM mode=2 | 对照具体版本 VDMA 定义、park pointer 和帧完成观测，确认读写避让；不能只因共用缓冲判定必然撕裂 |
| FIFO 复位与动态时钟 | capture rst_n 接 Clock Wizard locked；历史 REQP-1839 指向异步复位寄存器驱动 RAM 控制 | 审查 locked 跌落、重新等待帧、视频 FIFO reset 的全过程，执行 CDC/复位检查 |
| 摄像头参考时钟来源 | wrapper 没有输出 cam_xclk，初始化注释假定输入 24 MHz | 查看摄像头模块原理图或示波器，确认模块自带振荡器或外部时钟 |
| CPU cache 一致性 | 当前路径由 VDMA 写/读，CPU 没有访问帧像素 | 当前不能直接判为缺失 flush 的 bug；若以后 CPU 处理帧，必须设计 invalidate/flush 和帧所有权 |
| main 返回后的运行 | main 启动外设后 return 0 | 结合 BSP exit 实现、调试器行为和长期运行验证，考虑保留诊断主循环 |

RGB565 补零扩展损失部分 8 位动态范围是实现选择，不是必然功能错误。LCD RGB 三态输入未使用的 21 路产生 BUFC-1，与仅使用三个 ID 位的结构相符，应与严重时钟告警区别看待。

## 7. 历史报告与验证边界

`docs/evidence/system_wrapper_timing_summary_routed.rpt` 日期为 **2026-07-31**，工具 Vivado 2020.2。WNS=3.680 ns、TNS=0、WHS=0.047 ns；已设置约束下无失败端点。输入/输出约束缺口见上。

`docs/evidence/system_wrapper_drc_routed.rpt` 有 30 项：BUFC-1 21 个 Warning、PLCK-12 1 个 Warning、REQP-1839 3 个 Warning、RTSTAT-10 1 个 Warning，以及 REQP-165/181 共 4 个 Advisory。不是“零告警通过”。完整报告和 methodology 报告保留供复查。

本次执行了文件读取、JSON/XML 解析、原 IP 与生成 RTL 一致性检查、仓库材料整理和仓库静态自检。没有运行 Vivado 实现、HDL 功能仿真或上板测试。PATH 中未找到 Vivado、iverilog 或 verilator，不代表磁盘上绝对没有安装。

## 8. 建议网页端优先分析顺序

先根据原理图和时序补齐 PCLK/LCD 约束并覆盖最高频模式；再审查数据排列、首尾像素和复位波形；随后确认内部 genlock 与帧地址；最后设计初始化错误处理、锁定超时、帧缓存保留和运行时诊断。应先产出有证据的问题清单与小范围修复方案，保留当前基线便于回归。
