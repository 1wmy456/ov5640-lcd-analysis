# LCD触摸选目标：分阶段开发

基线`codex/visual-pid` / `019c0ee`，新分支`codex/touch-target-selection`。本阶段只推进A：真实触摸驱动、事件、坐标和十字叠加。B～E在A完成现场验证后继续，不将蓝色阈值复用为通用选目标条件。

## 固定回退版本lost

Git标签`lost`固定源码`019c0ee`；本机`build/releases/lost`冻结已验收的component_tracker_v2 bit/XSA、visual_pid_sw ELF/PS初始化、实际编译源码、源码zip、设置及SHA256清单。原有未提交修改另存working_tree.patch，不隐式混入已验收二进制。公开可审查清单在`docs/releases/lost.json`，大型产物留本机。

今后“烧录lost”对应：

```powershell
./scripts/download_lost.ps1
```

该入口先核对二进制哈希，再临时JTAG下载，启动manual/PWM关闭。恢复运行参数仍使用`restore_visual_pid.ps1`；是否启用自动和是否使用宽范围实验是独立选项。

## 硬件核验依据

- 已验收LCD ID为`0x4384`、800×480。
- 用户指定参考工程`D:/2026.test/zynq_lvgl/vitis/zynq_lvgl/src/TOUCH/touch.c`将0x4384分配GT9147；`gt9147.c/h`给出复位时序、0x8140产品ID、0x814E状态、0x814F起始点记录、0x8047配置与分辨率。
- 对照底板原理图V3.9的CORE_IO和RGB LCD页（PDF第5/1页），以及参考工程LCD.xdc：JC2-38 IIC2_SCL→R19，JC2-36 IIC2_SDA→P20，JC2-35 CT_RST→M19，JC2-39 CT_INT→U19。
- 新工程用独立AXI GPIO，不复制参考工程PS GPIO编号54～57；本工程摄像头SCCB已占PS GPIO54/55，实际T10/T11。LCD ID AXI GPIO及PWM U5/T5均保留。
- **实际上板读回ASCII产品ID为`1158`，地址0x14，即GT1158**，与参考工程按LCD ID选择的GT9147不同。复位/INT采用明确输出电平，I2C仍开漏；GT1158按GT1x配置地址0x8050读取，原始分辨率读回800×480。
- 已核对Linux上游v6.6 [goodix.c](https://github.com/torvalds/linux/blob/v6.6/drivers/input/touchscreen/goodix.c)的1158型号分配、8字节点记录与分辨率字段，以及[goodix.h](https://github.com/torvalds/linux/blob/v6.6/drivers/input/touchscreen/goodix.h)的GT1x/GT9x配置地址。仅按协议事实编写裸机驱动，没有移植Linux驱动或写控制器Flash。当前仅接受明确支持的1158/9147 ID，未知ID不启用。

## 阶段A接口

新增AXI GPIO `touch_gpio`，脚本检查空闲后分配0x43C30000/64KB；软件只使用新BSP的`XPAR_TOUCH_GPIO_*`宏。

|通道|定义|
|---|---|
|CH1 bits0..3|SCL、SDA、CT_RST、CT_INT；SCL/SDA开漏模拟，只驱动低电平，高电平释放；有界时钟等待和ACK检查|
|CH2 bit31|十字有效|
|CH2 bits9..0|视频x，0..799|
|CH2 bits18..10|视频y，0..479|

I2C探测0x14/0x5d，读取产品ID和对应型号的原配置分辨率，不更改存储配置。轮询间隔10ms，20ms稳定按下去抖；重复按下不重复DOWN，多指及150ms通信失联产生CANCEL，明确无触点报告产生UP。未就绪状态不被误读成释放。

读到触摸分辨率后按端点映射到视频尺寸，支持核心映射函数的交换XY及反转。当前默认不交换不反转，是否正确须通过现场四角与中央点击确认，不能仅用代码测试宣称已校准。

`axis_touch_cross`位于tracker→VDMA写入之间，绘制紫色十字，不改变蓝色识别原始输入。CH2一次32位写入，模块在成功传输SOF锁存整帧坐标，背压保持数据/标志，边界裁剪；初始化标记无效。它不修改DDR，不具备原始RGB帧快照能力。

阶段A的点击不会改变目标或控制器，原蓝色跟随代码保留；下载后仍PWM关闭。请先点中央和四角，观察串口`TOUCH DOWN/UP x=... y=...`与十字是否对齐。

## 构建、下载与测试

```powershell
./scripts/test_touch.ps1
./scripts/build_touch_stage_a.ps1 -Project build/touch_stage_a_fresh -Workspace build/touch_stage_a_fresh_sw
./scripts/download_pan_tilt.ps1 -Project build/touch_stage_a_fresh -Workspace build/touch_stage_a_fresh_sw
python scripts/pan_tilt_serial.py --port COM5 --listen 30
```

每次构建使用新目录，自动保留已验收产物；脚本显式沿用800×480/MODE2和80/60/35、ratio2、run3、count256等校准参数。生成新wrapper、新bit/XSA/BSP/ELF，检查setup/hold，保留DRC/CDC/IO报告。新增触摸管脚另核对约束、Bank及冲突。

自动测试：坐标全像素映射、反转/交换/越界、去抖/重复/多指/释放/超时；XSim随机TVALID/TREADY、像素/标志逐项对比、背压稳定、跨帧锁存、旁路及边缘十字。测试不代替现场触摸校准。

## 后续B～E的实现约束

1. 首先实现RGB原始帧的所有权和帧ID：VDMA完整帧、显示帧与点击事件匹配，独立保留读帧期间不会覆盖的缓冲。不能读取含绿色框/十字的DDR图像当作原始训练样本，也不能仅凭两次帧号相同宣称读取原子一致。
2. 点击释放后等待无遮挡完整帧，从点击邻域学习颜色分布并局部连通分割，以形状/边界/面积置信度拒绝背景。失败选择保留旧目标，目标切换保持脉宽、清PD历史；SELECT/TRACK/LOST显式管理。
3. 后续采用PS自适应颜色直方图及轻量外观关联，不以固定蓝色阈值决定可选颜色；高置信度才更新模板，LOST禁止背景更新。
4. A通过后先做蓝色点击，再红/白、不同颜色多目标切换；每阶段新产物与现场记录。
5. 只有测得PS处理耗时、带宽和准确性后评估PL迁移。阶段A尚未新增通用目标学习，也未完成B～E。
