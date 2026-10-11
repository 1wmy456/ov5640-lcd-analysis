# 网页端分析提示词

将下面内容复制到能够访问本私有仓库的网页端分析会话。仓库名和 URL 见根目录 README 所在的 GitHub 页面。

---

请深入分析这个 Zynq-7020 OV5640→DDR→RGB LCD 项目，用中文输出有代码证据的审查报告。

首先阅读 README.md、docs/PROJECT_ANALYSIS.md、docs/REPRODUCTION.md 和 docs/source_manifest.json，再阅读实际源码及 Block Design。现有报告仅作为初步线索，请独立核实每个结论。

重点入口：

- vitis/ov5640_lcd/src/main.c
- vitis/ov5640_lcd/src/ov5640/ov5640_init.c
- vitis/ov5640_lcd/src/emio_sccb_cfg/emio_sccb_cfg.c
- vitis/ov5640_lcd/src/vdma_api/vdma_api.c
- vitis/ov5640_lcd/src/clk_wiz/clk_wiz.c
- vitis/ov5640_lcd/src/display_ctrl/display_ctrl.c 和 lcd_modes.h
- vitis/ov5640_lcd/src/lscript.ld
- ip_repo/ov5640_capture_data/src/ov5640_capture_data.v
- ip_repo/rgb2lcd/ip/src/rgb2lcd.v
- ov5640_lcd.srcs/sources_1/bd/system/system.bd
- ov5640_lcd.srcs/constrs_1/new/lcd.xdc
- docs/evidence/ 中的历史报告、BSP 参数和设计摘录

原源码包含 GB18030 可解码中文注释；docs/source_utf8/ 下有保持行数的 UTF-8 阅读副本。原始文件才是构建来源，阅读副本不可当成额外编译单元。

请完成：

1. 还原完整数据通路、控制通路、时钟/复位域和启动顺序，解释关键端口与 IP 配置。
2. 核实 RGB565 双字节拼接、HREF/VSYNC/vid_ce 对齐、RGB/BGR 映射、WAIT_FRAME 行为，给出能暴露错位的具体波形或测试向量。
3. 核实 VDMA 24 位流宽、三帧地址、内部 genlock 各模式、FrameDelay=0、读写避让及潜在撕裂。缓存基址应以 BSP 宏为准，不要忽略 0x00100000。
4. 审查 Clock Wizard 动态重配、locked 超时、VTC porch 总数、各 LCD 刷新率、相机参考时钟来源和 PCLK 假设。
5. 审查外部时序约束、CLOCK_DEDICATED_ROUTE FALSE、动态高频模式覆盖、CDC/复位及 REQP-1839。历史 33.333 MHz 实现结果不能证明 70 MHz 运行模式已收敛。
6. 审查错误传播、SCCB 应答、日志格式、链接脚本帧缓存保留、DMA 错误监测与 main 返回。
7. 按 P1/P2/P3 输出问题，附文件:行号、触发条件、证据、影响与最小修复建议；将“确认问题”“条件风险”“缺少资料”分开。
8. 提供分层验证方案：RTL 小仿真、Vivado 时序/CDC、Vitis 日志/状态、上板彩条/示波器/ILA。缺少板卡原理图或实际波形时明确写出，不要虚构实测。

首轮以分析和建议为主。若提出代码修改，请先给出可审查的最小补丁与验证方法，避免大范围重写。可以运行 python scripts/check_repository.py 检查材料，但它不是综合、仿真或硬件功能测试。
