# 跟随速度调整（2026-10-26）

用户要求提高跟随速度。已通过UART同时调整两轴，不重新烧录或改RTL/C：

```text
gain yaw 0.5
gain pitch 0.5
rate yaw 50
rate pitch 50
```

增益单位μs/(pixel·s)，变化率单位μs/s。原值0.3/25，新值0.5/50：变化率上限为原来的2倍，不能据此断言整个跟随过程耗时缩短一半。yaw1100～1650、pitch1390～1650μs限位、±15px死区、帧有效性和250ms过期保护不变。

现场用户确认：“更快且停稳正常”。串口 `component_speed_tuning_20261026.txt` 中一段有效目标过程ex −57→−13px，yaw1293→1327μs后保持；另一段ex+184→+24px，yaw1304→1197μs，未触限位。50μs/s饱和阶段每0.5秒脉宽变化约25μs。现场尚有目标姿态导致短时无候选的情况，仍执行保持，没有取消检测保护来追求速度。

`restore_component_calibration.ps1` 默认保存新速度；`-Conservative` 保留旧速度，限位相同：

```powershell
# 默认快速档（会重新设置中心并开启自动）
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto
# 原保守速度档
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto -Conservative
```

新包为 `build/component_tracker_fast.zip`；旧下载包和提交af90cd5保留。bit/XSA/BSP/ELF沿用已验证版本，本次仅参数与恢复配置变化，不声称重新综合或完成新的时序测试。

后续再次提速至0.7/75并经现场确认；当前默认值及上一档恢复命令以 `SPEED_TUNING_FASTER.md` 为准。本文件保留最初0.5/50档的验收历史。
