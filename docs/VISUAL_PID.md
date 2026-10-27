# 视觉PD/PID与原平滑P控制对照

分支`codex/visual-pid`，基线`c7b9d02`。新增逻辑位于实际构建输入`vitis/ov5640_lcd/src/pan_tilt/tracking_control.c/h`、`pan_tilt_app.c`。不修改RTL、BD、XDC、摄像头/LCD初始化、VDMA及掩码算法；硬件沿用`build/component_tracker_v2`的匹配bit/XSA。旧平滑软件在`build/smooth_tracker_sw`，完整会话与源码备份在`build/visual_pid_baseline_20261026`。

## 控制定义与单位

保留原双轴符号、目标包围盒中心、20ms服务及新帧去重。对每轴：

```
e = bbox_center - image_center              # pixel
P = direction * Kp * e                       # us/s
D_filtered += dt/(tau+dt) * (clip(de/dt) - D_filtered)
D = direction * Kd * D_filtered              # us/s
I_candidate = clip(I + direction*Ki*e*dt, -Imax, Imax)
v_requested = P + I_candidate + D            # us/s
v_goal = clip(v_requested, -rate, rate)
v_next = acceleration/deceleration/reversal_limit(v_goal)
u_next = mechanical_limit(u + (v + v_next)*dt/2)  # us
```

Kp为`us/(pixel*s)`，Ki为`us/(pixel*s^2)`，Kd为`us/pixel`；D滤波状态为`pixel/s`，tau以秒参与计算（命令使用毫秒）。这里PID输出的是脉宽变化率，随后积分得到位置，不能套用另一种直接输出位置的PID增益。仍由MG90S自身执行脉宽对应的位置控制。

- `controller p`：原平滑P路径，原控制自检逐项保留。
- `controller pd`：增加D；不使用I，即使保存的Ki非零也不积分。
- `controller pid`：P+I+D；Ki默认为0，初次上板先不加积分。
- `smooth off`：明确返回旧P模式并取消平滑/滞回；`controller pd/pid`自动恢复平滑。

所有模式默认启动manual、PWM OFF、controller=p。切换控制器、修改PID增益或滤波设置时保持脉宽和使能，清速度/I/D，下一新帧只建立基准。auto仍需匹配800×480、双轴使能、方向和限位确认。

## 微分与积分约束

D使用不同有效帧的实际更新时间，不用截断后的运动dt做分母。先把斜率限制在默认±1000pixel/s，再经一阶低通（默认tau=100ms）。首次采样、恢复及超过50ms间隔重新建立D基准，避免目标重新出现产生微分冲击。重复帧不更新任何控制状态。

运动与积分dt仍不超过50ms。积分以输出单位us/s存储，默认Imax=10us/s。速率饱和和加减速限幅均参与条件积分：拒绝继续朝饱和方向增加的积分，允许已有积分向零回退。到机械端点清除朝外积分/速度；进入死区清I/D，避免静止时积累隐蔽运动。

目标无效、frame_error、数据/帧停止超过250ms、manual、disable、尺寸不符时立即清速度与PID历史，保持当前脉宽，不平滑滑行、搜索或回中。丢失处理与保护优先于控制轨迹。

## 首次PD配置与命令

沿用已验收Kp=0.7、rate=75us/s、accel=400/decel=600us/s²，内/外死区15/22px。首次PD尝试Kd=0.03us/pixel、Ki=0、tau=100ms，属于待现场对照的控制参数，不预先宣称优于P。

115200/8N1，ASCII命令加CR/LF，依次发送：

```text
manual
controller pd
kp yaw 0.7
kp pitch 0.7
ki yaw 0
ki pitch 0
kd yaw 0.03
kd pitch 0.03
dtau yaw 100
dtau pitch 100
pid
motion
status
```

完成原有机械配置、使能和确认后才`auto`。`pid`读出两轴Kp/Ki/Kd、tau、Imax、斜率限幅，以及P/I/D和请求速度。后缀`_milli`是所述单位乘1000。status新增`ctrl=p/pd/pid`，其他原字段不变。`gain`仍是Kp别名。

支持范围：Kp 0..2，Ki 0..0.5，Kd 0..1，dtau 10..1000ms，dlimit 10..10000pixel/s，imax 0..75us/s；拒绝NaN/Infinity/非法轴与越界值。软件上界不代表建议使用最大参数。

若PD的静止与换向已改善，通常不需要I。确需评估持续偏差时，可以手动保持后设置`ki yaw 0.01`、`ki pitch 0.01`及`controller pid`，先用小积分对照。框偏离源于识别、机械限位或死区时，不用积分抵消这些条件。

在线对照及返回当前平滑P：

```text
manual
controller p
auto
```

保持姿态对照PD同理把p改pd。`manual`保持使能和位置，`disable`关闭PWM。

## 可复现构建、下载、回退

```powershell
./scripts/test_pid_control.ps1
# 重新构建必须选择新的软件目录，不能覆盖原产物
./scripts/build_visual_pid.ps1 -Workspace build/visual_pid_sw
./scripts/download_visual_pid.ps1
# 默认已标定范围，恢复中心与现场参数，PWM仍关闭：
./scripts/restore_visual_pid.ps1 -Port COM5
# 下条显式启用自动，会设置中心，应先确认目标与安装姿态：
./scripts/restore_visual_pid.ps1 -Port COM5 -EnableAuto
# 本轮固定会话起点1331/1386us，匹配原宽范围实验，不发送回中：
./scripts/restore_visual_pid.ps1 -Port COM5 -Session build/visual_pid_baseline_20261026/session.json -WideExperiment
```

正常机械范围yaw1100..1650、pitch1240..1800us；用户此前选定的宽范围500..2500us仅通过`-WideExperiment`明确恢复，不把它写成已完成全段机械标定。两轴方向沿用yaw−1/pitch+1。J4-3/U5水平、J4-4/T5俯仰，外部5V共地，不改变接线。

回退同一硬件上的旧平滑ELF，无需重新编译：

```powershell
./scripts/download_visual_pid.ps1 -Rollback
# 旧程序启动manual/PWM OFF；此脚本用本轮保存的姿态恢复旧设置：
./scripts/resume_smooth_session.ps1 -Port COM5 -Session build/visual_pid_baseline_20261026/session.json
```

resume命令默认不会启用运动，复验后可加`-EnableAuto`。完整备份的源码与产物哈希见baseline/manifest.json；原分支不改写。

## 验证与现场顺序

控制自检覆盖D滤波精确数值、斜率限幅、实际dt、正负方向、零附加增益与旧P等价、积分累加/限幅/反向回退、速率与加速度抗饱和、两端机械限位、滞回、全部保持原因、重复帧、恢复、切换和帧号回绕。测试还包含P/PD/PID×两种方向×三种假设像素比例的18组闭环模型；模型的80ms视觉延迟和120ms舵机时间常数是假设，不是实测辨识，不用模型结果宣称实际性能。

构建先执行旧平滑与完整组件/AXI视频/PWM回归，再用新XSA生成standalone BSP、编译真实C输入并检查链接边界0x01100000。没有RTL变动，不重新生成或虚构新时序结果；复用bit的原WNS+0.953ns、WHS+0.045ns仅作为该硬件已有证据。

现场先下载PWM关闭版本，确认LCD和绿框；保持本轮姿态设置PD（Ki=0），再观察中央附近移动、换向、停稳，比较P/PD。接着移走目标、短遮挡恢复、模式切换。物理效果必须由现场观察记录；仅软件测试通过不表示舵机验收通过。执行结果见`docs/evidence/visual_pid/`。
