# 蓝色瓶盖：连通域、椭圆筛选和目标锁定

本次开发分支为 `codex/component-cap-tracking`，起点为 `b21def1`。原先整幅图像所有蓝点共同生成一个包围盒，分散的键盘字符、导线和瓶盖会把框拉大。本版对分离的区域分别计算形状，再关联同一个目标；控制程序和 LCD 使用同一个选中区域。

## 实现位置和数据流

视频仍沿 Video In → tracker → VDMA S2MM → DDR → LCD 运行。PL 在成功握手的原始像素上检测蓝色，同时生成 200×120 二值掩码：每个单元对应 4×4 原像素，其中至少 4 个蓝像素才置位。三组 BRAM 分别用于采集、最新完整帧、PS 锁定快照；PS 读取不对视频产生背压。原有异步 Video In FIFO 保留。

裸机 PS 分块读取 750 个 32bit 字，分步执行 3×3 多数滤波、四邻域连通域、面积/填充率/二阶矩椭圆筛选、轮廓偏差筛选、目标关联。没有 Linux 或 OpenCV 依赖。处理分段运行，串口和 20ms 云台控制持续服务。算法文件在实际构建目录 `vitis/ov5640_lcd/src/pan_tilt/cap_components.*`；运行接口在 `cap_runtime.*`。

选中结果带源帧号统一提交回 PL，在视频 SOF 锁存后整帧画框。处理延迟包括帧采集、PS 处理和等待下一个 SOF，不再仅是固定上一帧延迟。`vision` 显示实际处理耗时；250ms 过期保护仍有效。

## 筛选与锁定规则

- 单域面积至少 20 个掩码单元，最多整幅的 1/4；宽高至少 3 单元，均不超过画面的 3/4。
- 填充率 0.40～0.96，二阶矩拟合椭圆长短轴比不超过 2.8，外轮廓归一化半径平均偏差不超过 0.35；明显矩形和细长导线被拒绝。
- 连续两个不同源帧匹配后建立锁定。已锁定时，候选中心移动门限为旧框最大边的 0.75 倍、限制在 32～120 原像素内；面积比须为 0.5～2。其他独立蓝色区域不会与瓶盖合成一个框。
- 匹配区域才做坐标 1/2 平滑。失配立即发布无效结果、停止自动调整；只保留最多 6 个已处理帧的关联历史用于短时恢复，第 7 次失配解除锁定。保留关联历史不表示继续画旧框或驱动舵机。
- 帧异常立即清除显示和控制有效状态；快照的错误计数与实时错误计数不同也会拒绝结果，防止异步处理把异常前的旧结果重新发布。

`valid=0`、源帧异常、数据超过 250ms 或视频停止时，自动模式保持最后安全脉宽。硬件还独立使旧显示框过期。没有自动搜索或自动回中。

这是受形状约束的单目标追踪，不是语义识别。相邻蓝物体如果在二值图中相连仍可能合并，形状筛选会尽量拒绝该域，不能保证将接触物体拆开。很小、严重遮挡或侧视过扁的瓶盖可能被拒绝；定位分辨率约 4 原像素。不能靠平滑或提高增益修复错误检测，也不能把安全限位当作检测故障；`status` 的 `limit` 位 1/2 分别表示水平/俯仰在端点。

## 构建、下载和回退

在仓库根目录 PowerShell 执行，安装路径默认 `C:/Xilinxx`。构建必须使用新的目录，不覆盖已验收工程：

```powershell
./scripts/sim_component_tracker.ps1
./scripts/build_component_tracker.ps1 -Project build/component_tracker_v3 -Workspace build/component_tracker_v3_sw
```

当前完成构建的实际路径以 `docs/evidence/component_tracker/BUILD_MANIFEST.json` 为准。本轮 v2 下载入口：

```powershell
./scripts/download_component_tracker.ps1
python scripts/pan_tilt_serial.py --port COM5 --command status --command vision --listen 4
```

复位默认 manual、PWM 关闭。现场验收 LCD 和选中目标后，保持原安装和已验证限位可恢复校准：

```powershell
./scripts/restore_component_calibration.ps1 -Port COM5
# 上一条保持 PWM 关闭；下一条显式回到中心、使能、开启自动：
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto
```

固定接线：水平 J4-3/U5，俯仰 J4-4/T5；外部 5V 与板卡共地。已按5μs小步、逐段现场确认：yaw=1100～1650μs、中心1500、方向−1；pitch=1390～1650μs、中心1520、方向+1。水平下限在重新上电后的右侧目标复测中从1350逐段扩展至1100μs，记录见 `docs/evidence/component_tracker/YAW_RIGHT_RANGE.md`；水平上限和俯仰范围保持原标定值。增益0.3μs/(pixel·s)，限速25μs/s，死区±15px。未新增 PID。旧 `restore_pan_tilt_calibration.ps1` 保留原窄范围供回退使用。范围仍有限，不能保证从任意云台姿态覆盖整个摄像头视野。

串口 115200 8N1、ASCII，每条命令以 CR/LF 结束：

```text
status
vision
manual
disable
enable yaw
step yaw 5
enable both
auto
```

`manual` 保持当前脉宽和输出使能；`disable` 关闭 PWM。`vision` 输出源帧、源异常计数、域数、通过形状的候选数、锁定状态、原因、处理时间、最大原始域的单元面积/宽/高。`auto` 仍要求两轴中心/方向/限位已验证。

原版本回退，无需重新综合：

```powershell
./scripts/download_component_tracker.ps1 -Rollback
```

回退使用保留的 `build/pan_tilt_stable_box_v2` 与 `build/pan_tilt_stable_box_v2_sw` 匹配 bit/XSA/ELF；同样默认 PWM 关闭。本轮开始时的所有已跟踪文件及旧 bit/XSA/ELF/PS 初始化还完整备份在 `build/component_baseline_20261026`。原根工程、旧构建副本和用户既有未提交修改保留。

## AXI-Lite 增量寄存器表

基址由新 XSA 的 BSP 宏 `XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR` 获取，当前地址分配为 0x43C20000/4KB。原 PWM/快照寄存器见 `PAN_TILT_REGISTERS.md`，地址不变。组件模式版本 0x00010100；旧模式为 0x00010000。

|偏移|权限|含义|
|---|---|---|
|0xD0|RW|写1锁定最新掩码及元数据，写0释放；读bit0为锁定状态|
|0xD4|R|锁定快照源帧号，完整无目标帧也推进|
|0xD8|R|快照状态：bit2初始化完成、bit1异常、bit0有效；5为可处理帧|
|0xDC|R|锁定时源帧年龄，μs|
|0xE0|R|高16bit掩码高120，低16bit宽200|
|0xE4|R|单元边长4原像素|
|0xE8|R|掩码32bit字数750|
|0xEC|R|实时完整帧号|
|0xF0|R|实时帧异常标志|
|0xF4|R|实时最新完整帧年龄，μs|
|0xF8|R|实时源帧异常累计次数|
|0xFC|R|组件功能标识0x43434C31|
|0x100|RW|待提交xmax[31:16]、xmin[15:0]|
|0x104|RW|待提交ymax[31:16]、ymin[15:0]|
|0x108|RW|待提交选中域面积估计：单元数×16|
|0x10C|RW|写源帧号；读实际生效源帧号|
|0x110|RW|待提交有效位bit0|
|0x114|W|写bit0=1统一提交；错误epoch/过期/非法坐标结果强制无效|
|0x118|R|实际显示有效状态|
|0x11C|RW|软件记录处理耗时μs，仅诊断|
|0x120|RW|软件记录reason[31:16]、locked[8]、候选数[7:0]，仅诊断|
|0x124|R|锁定快照的源异常累计次数，必须与实时0xF8一致才可发布|
|0x200～0xDB7|R|锁定掩码，逐行、低bit先，每32单元一个字；未锁定读取SLVERR|

AW/W 独立握手，WSTRB 有效；B/R 背压保持响应。掩码 BRAM 同步读增加响应等待周期。组件模式下旧全局 bbox 统计值为0，不用于控制；不要让旧 ELF 与新硬件混用，下载入口校验 XSA/ELF 匹配。

## 验证范围

自检覆盖分离圆形/椭圆、矩形键盘/细线/噪声排除、大异物不抢锁、移动/失配/恢复/边界、重复帧与帧号回绕、不可变快照/错误epoch/过期；RTL 覆盖最后像素、跨32bit字、多帧三缓冲、随机视频背压、SOF/EOL逐像素对齐、AW/W独立、WSTRB及响应背压、帧边界显示更新。原 PWM/控制和五组蓝色 AXIS 回归保留。

仿真和综合不替代现场跟踪验收。实际时序、资源、构建及上板观察记录在 `docs/evidence/component_tracker/`，未完成的现场项目明确标注。
