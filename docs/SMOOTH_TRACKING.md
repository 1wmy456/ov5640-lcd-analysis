# 平滑云台跟随：加减速限制与死区滞回

开发分支 `codex/smooth-pan-tilt`，从已验收旧控制的 `4d48de5` 分出。保留正常版本 `b8b87f6`、宽范围实验 `4d48de5`、旧bit/XSA/ELF及源代码副本 `build/smooth_baseline_20261026`，用户原有未提交改动保留。实际构建输入仍为 `vitis/ov5640_lcd/src`。

## 控制变化

原控制将误差乘增益、按速度限幅后直接累计位置。新控制在目标速度与位置之间加入速度状态：

1. 速度目标仍为 `direction × gain × error`，按原rate限幅。
2. 根据实际新帧更新时间限制速度变化；起步按acceleration，减速/反向按deceleration。
3. 反向先减到零，下一有效更新再向相反方向加速，避免瞬间翻转速度。
4. 以新旧速度平均值累计位置，保留小数，最后按整数微秒提交PWM。

死区内圈默认±15px，外圈±22px。运行中进入内圈请求减速到零，停住后只有超过外圈才重新启动；处于15～22px之间时可能保持残余误差，以减少阈值附近反复动作。两个轴分别维护状态。

仅新的有效frame_id更新速度和位置，同一帧不重复积分；实际dt最大50ms。失目标、frame_error、超过250ms/停帧、manual/disable时，立即清速度和运动状态并保持位置，不继续平滑滑行。机械限幅优先于加减速限制，触限位清除朝外速度，不积累隐藏运动。

这不是完整PID；没有添加积分误差项或微分项。整数微秒指令、50Hz PWM、目标丢失及MG90S机械间隙仍可能限制实际平顺度。

## 参数与串口

固件初始保守值accel200/decel400μs/s²，启动仍manual、PWM关闭。现场用户反馈该值起停平顺但偏慢，已调成 **accel400/decel600μs/s²** 并确认更及时、平顺、停稳正常；新的恢复/会话脚本采用这组现场值。原增益0.7、速率75μs/s不变。

```text
motion
smooth on
smooth off
accel yaw 400
accel pitch 400
decel yaw 600
decel pitch 600
deadband 15 22
manual
disable
```

`smooth off`同时关闭加减速与死区滞回，使用旧版限速P速度控制，作为对比入口；切换时保留脉宽并清速度状态。`deadband 15`旧格式也支持，默认将外圈设为内圈+7。accel/decel允许10～2000μs/s²。`motion`显示参数，`status`显示smooth、db、vel_milli（μs/s×1000）和active（运动请求状态）；减速时active可以为0、velocity仍非0。

## 构建、下载、回退

控制自检与旧模式回归：

```powershell
./scripts/test_smooth_control.ps1
```

完整组件/视频/PWM回归并构建新的独立软件工作区，必须用新目录：

```powershell
./scripts/build_smooth_tracker.ps1 -Workspace build/smooth_tracker_sw_v2
```

本轮已构建工作区是 `build/smooth_tracker_sw`，匹配硬件 `build/component_tracker_v2/system_wrapper.xsa`。使用新standalone BSP、编译11个C文件；视频RTL和bit不变，没有放宽时钟约束。原FPGA时序报告仅作为相同bit的已有证据，不声称本轮重新综合。

```powershell
./scripts/download_smooth_tracker.ps1
# 默认恢复机械已标定范围并启用自动；此操作会设置中心
./scripts/restore_smooth_tracker.ps1 -Port COM5 -EnableAuto
# 继续此前用户明确选择的宽范围实验，可加-WideExperiment
./scripts/restore_smooth_tracker.ps1 -Port COM5 -EnableAuto -WideExperiment
```

宽范围仍为固件允许500～2500μs，未完成机械行程标定；正常范围仍yaw1100～1650、pitch1240～1800μs。当前现场验证沿用用户先前选择的宽范围、保持此前姿态进行比较，没有把更改限位当作平滑效果。

完整回退不需要重新编译：

```powershell
./scripts/download_smooth_tracker.ps1 -Rollback
# 原ELF启动manual/PWM关闭。按测试前快照恢复姿态和宽范围：
./scripts/resume_smooth_session.ps1 -Port COM5 -LegacyFirmware -EnableAuto
```

`resume_smooth_session.ps1`读取本轮测试前会话快照（yaw1373/pitch1481μs），在PWM关闭时设置脉宽后启用，避免强制回到1500/1520；它不是自动读取当前姿态的通用工具。正常下载后亦可用它恢复本轮固定起点。

## 验证记录

自检覆盖速度/加减速度上界、反向先过零、滞回内外边界、整数输出前的小数累计、重复帧、错误/过期/停帧、恢复时间基准、manual/auto、限位、禁用、模式切换和帧号回绕。200/400及现场400/600两组均测试，并与旧控制在合成阈值噪声下比较指令变化；该噪声试验不当作物理舵机抖动测量。

原蓝色组件C/运行接口、AXI视频、掩码、PWM和五组蓝色视频模式回归均已执行。实际检查数、ELF布局、源代码/产物哈希及现场结果见 `docs/evidence/smooth_tracker/`。失目标与遮挡、不同模式切换的现场观察以BOARD_VALIDATION记录为准，未完成项明确标注。
