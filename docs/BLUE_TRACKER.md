# 蓝色瓶盖检测与 LCD 画框交付说明

开发分支：`codex/blue-tracker`。基线提交：`4bccc73e8e610499f55f5d60a9b490f8221645d5`。
原 `ov5640_lcd.xpr`、`system.bd`、摄像头采集/初始化、VDMA 驱动、LCD 模式、Clock Wizard、VTC、GPIO、DDR 缓冲、XDC 均未编辑。新增工程生成到 `build/`；切回 `main` 并打开原 XPR 可回退。

## 文件与接口

| 文件 | 用途 |
|---|---|
| `rtl/blue_tracker/axis_blue_tracker.v` | AXI 单级弹性寄存器、模式选择、每帧画框快照 |
| `rtl/blue_tracker/blue_pixel_detect.v` | 原始像素阈值检测，扩展加法宽度 |
| `rtl/blue_tracker/blue_bbox_stats.v` | 像素坐标、完整帧统计、异常恢复 |
| `rtl/blue_tracker/video_box_overlay.v` | 内侧绿色边框与可选中心十字 |
| `sim/blue_tracker/tb_axis_blue_tracker.sv` | 三模式逐像素参考模型、自检、协议检查 |
| `sim/blue_tracker/tb_video_in_color_order.sv` | 本地 Xilinx Video In RTL 彩条与异步 FIFO 核验 |
| `scripts/sim_blue_tracker.ps1` | XSim 一键回归 |
| `scripts/integrate_blue_tracker.tcl` | 默认打印审查计划；显式应用时创建独立工程副本 |
| `scripts/synth_blue_tracker.tcl` | 模块独立综合、布局布线、资源/时序报告 |
| `docs/evidence/blue_tracker/` | 本轮真实工具输出与审查报告 |

顶层输入输出均为 24-bit `TDATA`、1-bit `TUSER[0]`、`TLAST`、`TVALID/TREADY`；无 TKEEP/TSTRB。`aclk=100MHz`，`aresetn` 低有效、同步采样，复位至少保持一个时钟周期。TUSER 是首像素 SOF，TLAST 是每行最后一个像素 EOL。

`s_axis_tready = aresetn && (!m_axis_tvalid || m_axis_tready)`。仅输入握手成功时统计/坐标/画框快照推进。单级寄存器在有输出待发送且下游不 ready 时完全保持 payload 与 valid；满吞吐每周期一个像素，空流水线延迟一周期。TREADY 是组合路径，完整系统必须检查从 VDMA 至 Video In 的时序。

| 检测结果输出 | 定义 |
|---|---|
| `bbox_valid` | 最近完整帧目标是否通过过滤；初始、空帧、坏帧为 0 |
| `bbox_xmin/xmax/ymin/ymax[15:0]` | 左上原点、包含两端的像素坐标 |
| `blue_pixel_count[31:0]` | 最近完整帧原始蓝色像素数量，包括最后一像素 |
| `result_pulse` | 正常完整帧最后一个输入像素被接收后的单周期脉冲；无目标完整帧也产生 |
| `frame_error` | 坏行、未同步像素、早到 SOF 等异常被接收后的单周期脉冲 |

结果输出位于输入处理时间域，可能早于最后一个输出像素被 VDMA 接收一个或多个周期；它不是 DDR 写入完成通知。画框另有 SOF 快照，因此不会在最后一行统计更新时改用当前帧结果。

## 参数和算法

默认：800×480、MODE=2、R_BYTE=2/G_BYTE=1/B_BYTE=0、BLUE_MIN=80、BR_DELTA=35、BG_DELTA=20、MIN_PIXELS=24、MIN_WIDTH=3、MIN_HEIGHT=3、BORDER_WIDTH=2、CENTER_CROSS=0。

检测条件：`B>=BLUE_MIN && B>R+BR_DELTA && B>G+BG_DELTA`，32 位无符号扩展参与加法。阈值须取 0..255；字节索引须是 0/1/2 的排列。分辨率支持 1..65535 每维，像素总数须可由 32 位计数器表示；宽高与上板实际摄像头输出一致。最小宽高按 `xmax-xmin+1` / `ymax-ymin+1` 判断。中心十字半径默认 4，限制在边界框内。

MODE0 逐像素原样输出；MODE1 蓝像素为白、其余黑；MODE2 保留原图，上一完整帧目标边框变为 RGB(0,255,0)。支持 RGB/BGR 交换 R/B 参数；当前绿色常量要求 G_BYTE=1。边框画在框的内侧、受图像范围约束，无目标不画。颜色检测始终使用未绘制的输入像素。

第一帧没有上一帧结果，不画框。完整空帧清除 valid，下一帧不画框。目标刚消失的第一帧仍会出现上一帧的框，这是明确的一帧延迟。多个独立蓝物体会合并成整体 bounding box，尚不支持准确多目标检测。

每行预期恰好 IMAGE_WIDTH 个接受像素，最后一个必须带 TLAST；第 IMAGE_HEIGHT 行尾锁存结果。提前/缺失 TLAST、超出帧高或未有 SOF 的像素清除结果并等待新的 SOF；早到 SOF 使被截断的帧无效，同时从该 SOF 正常开始新帧。新 SOF 的画框快照会禁止复用被截断帧前的陈旧结果。异常标志仍原样送 VDMA，不会伪造同步来修复坏视频。完全停止的数据流没有可识别的帧结束事件，本版没有超时计时器。

检测帧 n 的结果画入输入帧 n+1，再写入现有 DDR。云台前请区分算法一帧延迟和原 VDMA 三缓冲的显示延迟。若要同帧精确叠加，应在 DDR 输出侧设计 frame ID/缓冲地址匹配，本轮未实现。

## RGB 通道核验

1. 原采集 RTL `rgb888_data={rgb565_data[15:11],3'b0,rgb565_data[10:5],2'b0,rgb565_data[4:0],3'b0}`，所以物理 native bus 为 R[23:16]、G[15:8]、B[7:0]。
2. Video In XCI：RGB format=2、native/component width=8、components=3、pixels_per_clock=1、TDATA_NUM_BYTES=3、TUSER_WIDTH=1、100MHz、C_HAS_ASYNC_CLK=1；像素 drop 和 YUV420 remap 均关闭。Video Out 同为 24 位/单像素/异步配置，VDMA S2MM/MM2S 均 3 bytes。
3. 核对安装的 Vivado 2020.2 `v_vid_in_axi4s_v4_0_9` HDL：formatter 直接寄存 VID_DATA，等分量位宽的 coupler 原样传递字节，关闭 drop/remap 时直接透传。该工程的物理字节排列并没有被重排。
4. 自检提供红/绿/蓝/白/黑/紫彩条、RGB/BGR detector 对照、阈值边界和溢出检查；额外用实际 Xilinx Video In RTL 和异步 FIFO 接到 tracker 验证彩条逐像素与 SOF/EOL。vendor RTL 来自本地安装，不复制进仓库。
5. 注意 Vivado 的 RGB AXI 接口元数据以低字节 G、中字节 B、高字节 R 命名；这是格式字段说明，不能覆盖本工程 native 输入的实际连接与 RTL 数据路径。MODULE reference 验证时可能给出 TDATA 接口元数据传播警告。tracker 不做字节重排，实测依据是彩条测试。真正的摄像头 RGB565 设置、镜头颜色与 LCD 引脚仍须上板核验。

上板先保持 MODE0，用红绿蓝实物或摄像头已有彩条能力核对屏幕颜色；不在本轮改写初始化寄存器。必要时使用 ILA 在 `v_vid_in_axi4s_0/video_out` 采样原始像素：纯蓝应低字节高、纯红应高字节高。若仅 R/B 对调，改变 R_BYTE/B_BYTE 后重新生成；不要随意交换整条视频数据。

## 复现和集成

PowerShell（工具路径可传 `-VivadoBin`）：

```powershell
./scripts/sim_blue_tracker.ps1
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/integrate_blue_tracker.tcl
# 以下 800x480 只是本轮验证配置，上板须替换成当前实际分辨率。
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/integrate_blue_tracker.tcl -tclargs -apply -width 800 -height 480 -mode 2 -out build/tracker_mode2
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/synth_blue_tracker.tcl
```

脚本复制 XPR、sources 与原 IP repository，并在副本加入新 RTL module reference（不是已封装 IP）。断开且只断开原 Video In→S2MM 链路的 VDMA 端，插入 tracker；新模块使用已有 stream clock 和 VDMA axi_resetn 网络。原 Video In 的 native clock/异步 FIFO 均不改变。

默认模式只打印计划；应用前检查原直连、位宽、SOF 位宽、100MHz 和 CDC。只允许新建 `build/` 子目录，目录已存在则拒绝覆盖。重复执行可选新的 `-out`，避免不透明覆盖或重复插入。副本保留原 XDC，并用仓库自带 wrapper 替换 XPR 的缺失生成 wrapper 引用。生成 `system_with_blue_tracker.tcl` 供连接审查。

打开生成的副本 XPR 后，检查参数、Validate Design、Generate Output Products；必要时重新生成 managed wrapper，再运行原 synth/impl 流程，检查整个系统 timing/CDC/DRC，导出带 bitstream 的新 XSA 给现有裸机工程。当前未构建完整系统 bitstream，未替换原 XSA、ELF、摄像头驱动。

## 上板验收

1. 留存当前已稳定显示的 bitstream/ELF/XSA，记录实际 LCD ID 和摄像头宽高。用 MODE0 新工程先验证画面颜色、分辨率与原链路一致，持续观察是否错行/掉帧。
2. 用 MODE1，固定光照和单个蓝瓶盖、尽量避免蓝背景，检查白区域对应瓶盖。必要时调整 BLUE_MIN/BR_DELTA/BG_DELTA，随后检查 MIN_PIXELS/最小宽高过滤噪声。
3. MODE2 先静止瓶盖确认绿色 2 像素框，再测试四边、跨行、缓慢移动、快速移动和移走目标。一帧跟随滞后是本轮预期；移走后的下一完整空帧结果生效后框应消失。
4. ILA（可选、仅在副本增加）观察 tracker 两侧握手、SOF/EOL、Video In overflow、VDMA 状态/错误寄存器及 frame_error。随机背压的 RTL 自检通过不等于无限背压下 DVP 摄像头不会溢出；原 Video In FIFO 仍有容量上限。
5. 分别记录验收 A-F 的真实观察。尚未连接板卡，不能把仿真/Validate Design 当作 LCD 上板成功。

## 后续 MG90S 坐标接口建议

使用 `result_pulse` 原子锁存 valid、四边坐标、count，再加 frame_sequence；17 位求和计算中心 `cx=(xmin+xmax)>>1`、`cy=(ymin+ymax)>>1`，误差为中心减画面中心。以后可增加 AXI-Lite 只读快照寄存器（sequence/valid/count/cx/cy/四边）和坏帧计数，不复用 LCD-ID GPIO。PS 若跨时钟读取，使用握手快照或异步 FIFO，避免多位 CDC 撕裂。完整帧无目标事件也需通知控制端。本轮未实现舵机 PWM、Kalman、PID、YOLO、Sobel、Linux。

参考 [CNN_FPGA](https://github.com/n111116/CNN_FPGA) 的视频检测/overlay 工程组织；本轮没有移植其 YOLO、DDR 同帧延迟或非 AXI 流握手逻辑。
