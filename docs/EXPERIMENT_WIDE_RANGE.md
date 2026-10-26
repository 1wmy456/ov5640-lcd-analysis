# 临时放开机械软限位（2026-10-26）

用户明确要求取消上下左右的已标定限位观察效果，并保留原代码。本实验只通过原固件串口接口修改运行时边界；没有修改RTL、裸机C、bit/ELF、检测算法或原恢复脚本。

## 原版保留

- 正常版本：分支 `codex/component-cap-tracking`，提交 `b8b87f6`。
- 实验分支：`codex/wide-range-experiment`。
- 原恢复入口：`scripts/restore_component_calibration.ps1`，内容不变；正常范围yaw1100～1650、pitch1240～1800μs，默认速度0.7/75。
- 额外副本：`build/wide_range_original_20261026/` 保存原恢复脚本、CALIBRATION.json及原C/RTL/脚本文件哈希。用户既有未提交文件保留。

## 实验实际含义

两轴运行时边界均设为500～2500μs，替代已标定的机械软限位。PS控制限幅和PL限幅都使用这组宽边界；并非数学上完全无界。

500～2500μs仅为现有固件允许的脉宽范围，不代表舵机、支架或排线在整个范围内都经过机械验收。原PWM周期20ms、速度限制75μs/s、增益0.7、±15px死区、方向、图像有效性、250ms过期保护、失目标保持均不变。

现有固件在auto前要求`verify`标记。实验脚本基于用户本次明确授权写入该软件放行标记；这是对机械校验门槛的显式实验覆盖，不能将日志中的“marked verified”当作500～2500μs已通过物理标定的证据。因此脚本结果标为`MECHANICALLY_UNCALIBRATED`，未将宽范围写入正常CALIBRATION.json。

## 执行与恢复

在原固件、已启用双轴PWM、方向与图像尺寸配置正确的当前会话中：

```powershell
./scripts/experiment_wide_range.ps1 -Port COM5 -EnableAuto
```

不发回中、指定位置或扫动指令，从当前脉宽继续。未带EnableAuto时只设置宽边界并进入manual保持，原输出使能不变；脚本不会自行启用原来关闭的PWM。

立即停止输出：串口ASCII发送`disable`加换行，或：

```powershell
./scripts/experiment_wide_range.ps1 -Port COM5 -DisableOutputs
```

恢复原已标定范围并关闭PWM：

```powershell
./scripts/restore_component_calibration.ps1 -Port COM5
```

若之后要恢复正常自动跟随，可按原流程加EnableAuto；恢复脚本会先关闭输出、重新设置中心，再按选项启用。实验配置仅本次会话有效，复位/重新下载后原固件仍默认manual/PWM关闭，不会自动进入宽范围。

## 实际观察

应用前manual：yaw1234/pitch1383μs、en=3。宽边界应答为两轴500..2500；开始时无目标，auto保持相同脉宽，没有强制回中。后续串口有有效移动目标，源帧继续更新，PWM内部周期2,000,000tick/100MHz正常。

用户现场反馈：“范围改善，跟随正常，暂时保持实验模式”。交付时按该要求保留宽范围auto。该反馈只覆盖实际观察到的轨迹，没有对500或2500端点做完整扫动或机械验收，也不宣称已经解决历史源视频异常。

验证范围为：串口参数应答、auto状态、现场观察、原文件哈希一致性和新脚本语法；本次未重新综合或编译，未改变已有时序报告。
