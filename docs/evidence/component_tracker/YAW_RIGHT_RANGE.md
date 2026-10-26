# 重新上电后右侧目标停转：范围标定与闭环复测

日期：2026-10-26。使用原组件追踪bit/ELF，COM5，安装和接线未变。

## 故障复现

用户反馈上下跟随可用，但瓶盖在画面右侧时水平停止。固定故障场景后实际读取：

```text
mode=auto frame=8083 valid=1 err=0 bbox=683,751,197,248
ex=317 yaw=1350 pitch=1477 en=3 hold=0 limit=1 det=ready
```

目标检测和锁定有效、水平误差很大、输出已到旧软件下限1350μs；本次停止由限位造成。PWM内部实测脉宽与设定一致、周期2,000,000tick。未通过改变颜色或形状条件绕过此问题。

## 逐段现场机械标定

进入manual，俯仰保持1477μs，水平每步−5μs。以下各段均由用户明确确认动作正常，无碰撞、卡住、持续异响或明显抖动后才继续：

|区间μs|现场结果|
|---|---|
|1350→1300|重复一次后确认正常|
|1300→1250|重复、放慢至1.5秒/步后确认正常|
|1250→1200|正常|
|1200→1150|正常|
|1150→1100|正常|

未继续测试低于1100μs的区域。未扩大水平上限1650μs或俯仰1390～1650μs。相对中心1500μs，向屏幕右侧跟随可用的减脉宽余量从150扩为400μs；这不是对机械角度的线性标定。

经已验证范围按5μs回到yaw1500，并恢复pitch1520。固定底座，将瓶盖固定在画面右侧，再启用自动；测试期间不跟着镜头移动瓶盖。

## 闭环结果

`component_yaw_closed_loop_20261026.txt`记录：

|状态|水平脉宽μs|ex像素|limit|
|---|---:|---:|---:|
|起点manual，frame46744|1500|+312|0|
|自动越过旧下限，frame47000|1346|+120|0|
|继续收敛，frame47180|1274|+26|0|
|进入死区，frame47260|1265|+12|0|
|随后保持，frame47280～47460|1265|约+12～15|0|

用户确认：“已回到中央附近，跟随与停稳正常”。本场景证明原来在1350μs停止的目标，现在可以继续收敛；不代表任意姿态、全视野都在机械范围内。

新范围已保存至 `scripts/restore_component_calibration.ps1` 和 `CALIBRATION.json`：

```powershell
./scripts/restore_component_calibration.ps1 -Port COM5 -EnableAuto
```

默认不加EnableAuto仍为manual、PWM关闭。旧的1350μs配置另存 `build/restore_component_before_yaw_extension_20261026.ps1`，旧下载包及Git提交7f7d4e8均保留。

## 构建与回归范围

本次只改运行时校准配置和记录，无RTL或裸机C变更，不需重新烧录、综合或生成ELF。沿用 `build/component_tracker_v2` / `build/component_tracker_v2_sw` 已验证bit/XSA/BSP/ELF；原WNS+0.953ns、WHS+0.045ns报告仍对应同一产物。本次重新执行校准脚本、逐步指令应答/实际脉宽检查和现场闭环测试；产物/编译输入哈希由打包审查再次核验。

新包 `build/component_tracker_yaw_extended.zip` 包含更新配置及记录，旧 `component_tracker_release.zip` 不覆盖。源视频偶发异常的历史限制仍保留，本次未更改摄像头/VDMA链路或声称修复该项。
