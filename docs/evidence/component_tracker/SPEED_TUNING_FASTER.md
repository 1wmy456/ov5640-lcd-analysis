# 再次提高跟随速度：0.7 / 75（2026-10-26）

用户在0.5/50档已验收的基础上要求再次提速。通过UART实际应用并获得指令应答：

```text
gain yaw 0.7
gain pitch 0.7
rate yaw 75
rate pitch 75
```

增益单位μs/(pixel·s)，变化率单位μs/s。相对上一档，变化率上限提高50%，增益提高40%；不声称整体跟随耗时按相同比例缩短。限位yaw1100～1650、pitch1240～1800μs、±15px死区、新帧/目标有效性、250ms过期保护和目标丢失保持不变。

现场操作员确认：“更快且停稳正常”。随后串口采集frame181854～182161约8秒，持续valid=1、err=0、limit=0，ex约+6/ey+13～14px，yaw1377/pitch1631μs保持不变，处理耗时约7720μs。该窗口记录停稳状态；速度提升的动态现场判断来自操作员反馈，不伪造定量动态测试数据。原有源视频间歇异常限制继续保留。

恢复脚本默认保存新档，保留已验收的两个旧档：

```powershell
# 默认更快档，或显式 -Speed faster
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto
# 上一档
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto -Speed fast
# 原保守档；-Conservative 是兼容别名
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto -Speed conservative
```

这些恢复命令会重新设置中心；当前运行中的速度已直接调好，无需为了提速再次执行恢复脚本。不加EnableAuto仍保持manual、PWM关闭。

RTL、裸机C及bit/XSA/BSP/ELF未变，无需重新烧录或综合。本次验证包括UART参数应答、现场运动与停稳确认、静止状态串口记录、恢复脚本语法以及打包产物/编译输入哈希检查。新包 `build/component_tracker_faster.zip`，旧包和提交88f34c2保留。
