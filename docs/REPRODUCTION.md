# 复现与验证

## 仓库整理范围

保留 Vivado 2020.2 原工程、BD、XCI、XDC、wrapper、Vitis 应用源码与项目元数据、原硬件交接 XSA。将原外部路径中 `rgb2lcd` 与 `ov5640_capture_data` IP 包完整复制到仓库内 `ip_repo/`，包括 component.xml、xgui 和 LCD 自定义接口定义。两个包的 RTL 与工作区生成目录副本字节一致。

`ov5640_lcd.xpr` 的两个 `IPRepoPath` 改为 `$PPRDIR/ip_repo/rgb2lcd` 和 `$PPRDIR/ip_repo/ov5640_capture_data`；其余原工程配置保持不变。缓存和旧 run 状态没有纳入仓库，打开后工具可能需要重新生成输出及重置旧 run 状态。分析阅读副本存放 docs/source_utf8/，没有改写原始 GBK/GB18030 注释文件。

XSA 和历史报告是既有快照，未重新生成，不能保证与将来修改后的硬件一致。原第三方源码保留版权声明；本仓库未额外赋予其新的开源许可。

## Vivado

优先使用 2020.2，并安装 Zynq-7000 器件支持。在 Vivado Tcl Console 中执行：

```tcl
source scripts/open_project.tcl
```

该脚本打开工程、注册仓库内 IP 路径和更新目录，不会自动综合、实现或生成 bitstream。检查 IP Status 和 Block Design 后，按工具流程重新生成 output products、综合、实现。使用新工具版本时先评估 IP 升级，不要把升级后的结果当成 2020.2 原基线。

需要重新出具至少：check_timing、report_timing_summary、report_drc、report_methodology、report_cdc、report_bus_skew。动态像素时钟各模式需要显式覆盖，至少最高 70 MHz 不能只沿用默认 33.333 MHz 的通过结论。

## Vitis

使用 Vitis 2020.2 从 `vitis/system_wrapper.xsa` 创建 standalone 平台，处理器选择 ps7_cortexa9_0，再创建应用并导入 `vitis/ov5640_lcd/src/`。完整生成平台、BSP 和 Debug 目录没有入库，已有 Eclipse 元数据可能含本地路径，必要时重建平台/应用比直接复用工作区更可靠。

核对新 BSP 的地址、VDMA 流宽/帧数/genlock、GPIO 和 VTC/Clock Wizard ID。摄像头和 LCD 需要与 XDC 对应的实际板卡；应使用对应硬件生成的 bitstream。若修改了硬件，则重新导出 XSA 并更新平台后编译。

## 最小上板定位路径

1. 读取并打印 LCD ID、GPIO/VDMA/VTC/Clock Wizard 初始化状态、OV5640 ID。
2. 读取摄像头关键配置并观测 PCLK、HREF、VSYNC；確認参考时钟来源。
3. 启用摄像头测试彩条，检查 RGB/BGR、首尾像素和尺寸。
4. 观测 S2MM/MM2S 状态、帧指针、FIFO underflow/overflow、Video Out locked。
5. 示波器检查实际 LCD 像素时钟与 HS/VS/DE 总周期，并覆盖各 LCD 模式。
6. 长时间运行、重启与模拟摄像头缺失，验证错误处理和恢复路径。

## 本仓库可运行的静态材料检查

```text
python scripts/check_repository.py
```

此检查验证清单文件、原源码与 UTF-8 阅读副本、IP XML 文件引用、BD JSON 和 XPR 仓库路径。不会测试芯片功能或运行商业工具。
