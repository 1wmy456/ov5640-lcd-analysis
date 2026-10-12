# 蓝色检测本轮验证报告

日期：2026-10-12（Asia/Shanghai）。工具：Vivado/XSim 2020.2，目标 xc7z020clg400-2。所有数字来自本轮工具运行。原工程历史报告未当作新增逻辑的验证依据。

## 结果

| 验证 | 结果 |
|---|---|
| 默认阈值（MIN=4/2/2，12×8 合成图，三模式同时比对） | PASS，99,243 检查、0 失败、31 完整帧 |
| 单像素阈值（MIN=1/1/1） | PASS，99,243 检查、0 失败、31 完整帧 |
| 中心十字启用 | PASS，99,243 检查、0 失败、31 完整帧 |
| 安装的 Xilinx Video In RTL + async FIFO + tracker 彩条 | PASS，2,449 检查、3 帧、288 像素 |
| 安全工程副本插入 tracker / Validate Design | PASS，800×480 / MODE2 配置 |
| 原文件与基线字节核对、BD 原连接/参数核对 | PASS，52 个受保护原文件无改动 |
| 独立模块综合/布局/布线 | PASS，100MHz 示例约束下时序满足 |
| 完整 OV5640/DDR/LCD 系统重新综合和布局布线 | 未运行 |
| bitstream / 新 XSA / Vitis ELF | 未生成 |
| 真实摄像头颜色、LCD 模式0/1/2、板卡验收 A-F | 未上板，待验证 |

每组主测试累计 2,994 次输入握手、2,993 次输出握手、1,161 个输出背压周期、8,392 个输入无效周期。差值 1 来自专门的复位测试：下游 ready=0 时已有一个像素存于弹性寄存器，复位清空该像素并重新同步；它不是正常运行丢像素。每个复位区间内 scoreboard 严格检查没有重复/额外输出且结束时队列清空。4 次预期坏帧事件被参考模型与 RTL 一致检测。

主 Testbench 使用 SystemVerilog immediate assertions，经统一 `check` 任务计数，并由脚本检查 PASS 标识、FAIL 行和工具返回码。参考模型独立计算颜色、包围盒、快照、三模式输出；每个输出的 24 位数据及 SOF/EOL 一起比对。没有宣称形式化证明或硬件 AXI 故障注入。

## 请求的覆盖点

| 请求项 | 自检位置/行为 |
|---|---|
| 1 全黑无目标 | kind0，count=0/valid=0/坐标清零 |
| 2 蓝色矩形 | kind1，包含首帧不画、下一帧画框 |
| 3 近似圆 | kind2，半径平方判定 |
| 4 靠近边界 | kind3 左上角、kind4 右下角 |
| 5 跨多行 | kind5，全高度两列蓝条 |
| 6 连续移动 | kind6→7→8，上一帧框逐像素对照 |
| 7 从有到无 | kind8→0→0，明确一帧延迟后清除框 |
| 8 孤立噪声 | kind9；额外 kind13/14 分别检查最小高度/宽度过滤 |
| 9 TVALID 不连续 | beat 任务插入无效周期与随机间隙 |
| 10 TREADY 随机背压 | 固定种子 LFSR，逐周期 payload/valid 稳定断言 |
| 11 连续多帧 | 两帧全蓝，无 TVALID 间隙 |
| 12 异常行长/早结束 | 提前 TLAST、缺失 TLAST、早 SOF、超高/无 SOF，随后正确帧恢复 |
| 13 末像素蓝 | kind10 单末像素；kind16 末像素扩展已有框，count/右下界验证 |
| 14 旁路逐像素一致 | MODE0 全程三位标志及像素 scoreboard |
| 15 TUSER/TLAST 严格对齐 | 三模式统一 26 位 payload scoreboard，含随机背压 |

额外：kind15 两个独立蓝块，预期一个合并框，确认第一版算法限制；RGB/BGR detector 对照、B=80 包含边界、严格差值等号、R/G 高值的加法溢出反例；输出阻塞时主动复位；每个周期核对结果有效性、count、坐标、完成和错误脉冲，包含无输入握手时的稳定性。

## RTL 审查结论

- 单级弹性寄存器更新条件是空槽或当前输出被接收；输入 ready 与其一致。背压时数据、标志、valid 均不变，输入成功握手才改变统计。
- 原始输入用于 blue 检测，painted 数据只进入输出寄存器。MODE0 数据位完全原样传递。
- 当前像素参与 next_count/next_bbox 再锁存，覆盖最后一个蓝像素。坐标遇 SOF 立即从 (0,0) 开始；早 SOF 既报告中断又从新帧继续。
- 画框在 SOF 接收时锁存上一结果，SOF 像素直接使用同一结果，多周期背压不会改变已注册输出。当前帧最终统计只影响下一帧。
- 边框在 bounding box 内，17 位扩展处理坐标差和中心求和；无效结果不画框。帧统计不具备连通域分离或噪声聚类能力。

## 模块资源与时序

默认 RTL 配置：800×480，MODE2，MIN=24/3/3，边框2，无中心十字。OOC routing 后资源：565 LUT（1.06%）、320 FF（0.30%）、0 BRAM、0 DSP；无锁存器、无黑盒。时钟 10ns，示例输入/输出延迟均 1ns，aresetn 设 false path。报告 WNS=+1.084ns、TNS=0、WHS=+0.159ns、THS=0；0 无时钟寄存器、0 未约束内部端点。

这是独立模块估计。Vivado 提示 OOC aclk 没有 HD.CLK_SRC，因此不估计顶层真实时钟延迟/偏斜；示例端口延迟并非 VDMA/Video In 的最终接口预算。完整系统尤其组合 ready 路径仍需重新实现确认。

OOC DRC 有一条 ZPS7-1 Warning（独立模块不包含 Zynq PS7），没有 DRC Error；这不等于完整系统 DRC 通过。

## 集成审查及警告

最终验证工程：`build/blue_tracker_final/ov5640_lcd.xpr`。脚本用 module reference 推断 S_AXIS/M_AXIS，在原100MHz域接入 VDMA active-low reset，原 native video CDC/所有其余接口不变。

原有 PS、VDMA、VTC、Clock Wizard、GPIO、LCD 和捕获 cell 的已显式配置值均保留。Vivado 保存 BD 时为 PS 展开了304个默认参数，审计确认原已存在的参数值没有改变。所有原 native nets 保留，仅AXI clock/reset 增加 tracker 接收端；唯一视频修改是原直连被 tracker 替代。

Validate Design 成功，但存在 BD 41-926 tracker S_AXIS 的 TDATA_WIDTH/TDATA 字段元数据传播警告，以及原 rgb2lcd pixel_clk 的 BD 41-927 PHASE=0 警告。24位/1pixel/100MHz 连接检查通过，真实 IP 字节彩条仿真通过；警告完整原文见 `integration.txt`。打开复制的原 XPR 时还会报告旧 generated run/wrapper 文件缺失，脚本使用仓库自带 wrapper 替换引用；未把缺失历史 run 当作已执行。

安全重跑：默认只打印计划，`-apply` 只写新建 build 子目录；相同目录已存在即拒绝，另选 `-out` 即可复现。原工程52个受保护文件与基线字节一致。测试/集成报告来自最终脚本，原摄像头与 LCD 驱动和 XDC 没有为仿真修改。

## 仍需硬件确认

当前测试证明合成像素条件下的模块行为、AXI 稳定性和 Video In 通道顺序。它没有测量瓶盖真实色彩在不同光照下的识别率、DVP FIFO 的极限背压容忍时间、原 VDMA 三缓冲显示延迟或所有 LCD 模式。按 `docs/BLUE_TRACKER.md` 顺序完成 MODE0→MODE1→MODE2 上板验收，记录 A-F；不得根据本报告称已上板成功。
