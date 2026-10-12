# 双 MG90S 二维云台与蓝色瓶盖追踪

基线为 `codex/blue-tracker` / `15e98ec`，新分支 `codex/pan-tilt-tracking`。实际 C 输入为 `vitis/ov5640_lcd/src`。原 XPR、BD、摄像头初始化、LCD GPIO/模式、VDMA/DDR/链接脚本、原 XDC 和蓝色检测 RTL 保留；main.c 仅增加头文件、控制循环调用，并修复原像素频率日志的参数类型。集成在独立 `build/` 副本执行。原已验收 bit/XSA/ELF 保留。

## 视频与 PL 连接

Video In → axis_blue_tracker → VDMA S2MM 视频通路不变。新增 pan_tilt_ctrl_0 接 ps7_0_axi_periph/M04_AXI，统计信号直接从 tracker 接入，均使用原 100MHz FCLK0 和 peripheral_aresetn。原摄像头像素域的异步 FIFO 不变。脚本检查地址冲突后分配 `0x43C20000..0x43C20FFF`，软件地址来自新 BSP 的 `XPAR_PAN_TILT_CTRL_0_S_AXI_BASEADDR`。

新增构建明确指定 MODE2、800×480、BLUE_MIN=80、BR_DELTA=60、BG_DELTA=35、MIN_B_R_RATIO=2、MIN_BLUE_RUN=3、MIN_PIXELS=256、BORDER_WIDTH=2、CENTER_CROSS=0。LCD ID 仍自动选择原摄像头/显示模式；显示尺寸不是 800×480 或摄像头初始化失败时，软件禁止自动追踪并打印原因。

框仍为上一完整帧的整体蓝色包围盒，在当前帧写入 DDR。运动有一帧偏差；多个蓝色物体会合并为一个框，不是多目标识别。

## 接线

| 用途 | 板上接口 | FPGA 引脚/约束 |
|---|---|---|
| 水平信号 | J4-3 | U5，servo_yaw_pwm，LVCMOS33 |
| 俯仰信号 | J4-4 | T5，servo_pitch_pwm，LVCMOS33 |
| 公共地 | J4-37 或 J4-39 | 与外部舵机电源负极、两舵机地相连 |
| 两舵机电源 | 外部匹配舵机的电源 | 不接 FPGA 信号脚 |

独立约束为 `constraints/pan_tilt.xdc`。实现报告检查两个端口唯一占用 U5/T5、Bank 13、LVCMOS33，并报告该 Bank 的设计 VCCO=3.30V；工具报告不能测量实际板上电压。现场用户确认外部5V供电与共地。MG90S 官方页面列出 4.8V 工作电压，具体供电适配应核对实际舵机：[TowerPro MG90S](https://towerpro.com.tw/product/mg90s-3/)。

## PWM 和快照语义

20ms/50Hz、100MHz 下周期 2,000,000 tick、1500μs 高电平 150,000 tick。影子脉宽统一提交，在周期边界同时生效；周期边界恰好来的新提交排到下个边界。待处理提交可被后续完整提交替换。复位默认关闭，两轴中心 1500μs、初始范围 1400..1600μs，这不是已标定机械角度。硬件在接收提交时按限位夹紧；修改限位后软件提交新的安全脉宽。启用在周期边界开始，关闭立即拉低且保留位置。输出为寄存器电平，避免计数比较器输出毛刺。

AXI-Lite AW/W 分开保存，任意顺序都只执行一次写入；支持 WSTRB，B/R 背压稳定，未定义、未对齐、非法限位/中心、只读写入返回 SLVERR。允许一笔未完成写和一笔读。

tracker 在一个边沿同时寄存结果与 result_pulse；外设在下个边沿消费已更新的数据。所有完整帧（包括无目标帧）递增 frame_id，frame_error 使最新 valid 清零。软件写 SNAPSHOT 后，帧号、flags、坐标、数量、年龄一次锁存；PS 多次读取期间保持不变，视频统计继续。与快照执行同周期到来的结果/异常也纳入快照。仅软件拥有快照触发权；JTAG 命令不会直接覆盖 PS 正在读取的快照。

PWM_NET 监视器统计内部实际输出网的完整高电平宽度、相邻上升沿周期和累计上升沿数，用于诊断；不能证明连接器或舵机端的电压正确。关闭中途会产生一条截短脉冲测量值；诊断值不代替机械验收。

## 自动控制

xc=(xmin+xmax)/2，yc=(ymin+ymax)/2，ex=xc−400，ey=yc−240。控制每20ms非阻塞运行，只消费新的有效 frame_id：

`position_us += direction * K * error_pixels * dt_seconds`

K 初始0.1μs/(pixel·second)，最大变化率25μs/s，两轴死区含 ±15 像素。状态保留 double 小数，误差有符号，最后四舍五入为微秒后统一提交。dt 使用实际更新间隔，最多50ms；失去目标后恢复的第一帧只建立时间基准，不累积丢失期间的时间。

无目标、异常、硬件快照年龄>250ms、或同一帧号超过250ms没有更新时停止位置增量，继续最后安全 PWM。不会自动搜索或回中。manual/hold 只停止自动调整；disable 才关闭输出。切换 auto 从已生效脉宽继续。启动默认 manual/off。必须启用两轴、尺寸正确，且通过现场方向/中心/限位验证并执行 verify 后才允许 auto；改 dir/limits/center 会撤销该轴验证标记。

## 构建、下载和回退

PowerShell，在仓库根目录执行。安装路径参数可覆盖；默认本机 Vivado/Vitis 为 C:/Xilinxx。

```powershell
# 查看集成计划；不覆盖原 BD
& 'C:/Xilinxx/Vivado/2020.2/bin/vivado.bat' -mode batch -source scripts/integrate_pan_tilt.tcl
# 仿真 + 独立集成 + 布局布线/时序门禁 + 新 XSA/BSP/ELF
# 已存在的目录会拒绝覆盖，复建时使用新名称
./scripts/build_pan_tilt.ps1 -Project build/pan_rebuild -Workspace build/pan_rebuild_sw
# 本轮实际 release，下载后默认 PWM OFF、manual
./scripts/download_pan_tilt.ps1
# 指定新复建目录
./scripts/download_pan_tilt.ps1 -Project build/pan_rebuild -Workspace build/pan_rebuild_sw
# 回退已验收蓝色框版本（旧 bit 与旧 ELF）
./scripts/download_pan_tilt.ps1 -Rollback
```

仅临时 JTAG 下载，不写 QSPI/SD。BD wrapper 每次由 make_wrapper 重新生成；没有手工修改可覆盖的生成 wrapper。脚本以明确成功标记核对 XSCT，因为 XSCT2020.2 在 Tcl 出错时可能返回0。编译递归加入全部 C 文件，检查3个新增源确实编译，检查 `_end < 0x01100000`，输出源哈希和 ELF 哈希。

## COM6 串口命令

115200、8N1、不使用流控。关闭其他占用 COM6 的串口软件。可用终端输入下面的命令，或直接复制 Python 示例：

```powershell
python scripts/pan_tilt_serial.py --port COM6 --command status --listen 2
python scripts/pan_tilt_serial.py --port COM6 --command 'enable yaw' --listen 1
python scripts/pan_tilt_serial.py --port COM6 --command 'step yaw +5' --listen 2
python scripts/pan_tilt_serial.py --port COM6 --command pwm --listen 2
python scripts/pan_tilt_serial.py --port COM6 --command disable --listen 2
# UART 不可用时：相同 C 解析器与验证条件，最多31字符/命令
./scripts/pan_tilt_jtag_command.ps1 -Command status
```

| 命令例子 | 含义 |
|---|---|
| enable yaw / enable pitch / enable both | 启用指定轴，不清除另一个轴的使能 |
| disable | 关闭两轴并进入手动，保存位置 |
| yaw 1505 / pitch 1495 | 指定绝对脉宽μs；进入手动 |
| step yaw +5 / step pitch -5 | 当前脉宽的有符号增量μs；进入手动 |
| center | 统一提交两个已配置中心，不改变使能 |
| center yaw 1500 / center pitch 1500 | 配置中心，不立即运动；需重新验证 |
| limits yaw 1400 1600 / limits pitch 1400 1600 | 设置限位μs，夹紧当前位置并提交；需重新验证 |
| dir yaw -1 / dir pitch 1 | 设置独立方向符号；进入手动并撤销验证 |
| gain yaw 0.1 / gain pitch 0.1 | μs/(pixel·second)，可实时调整 |
| rate yaw 25 / rate pitch 25 | 最大脉宽变化率μs/s |
| deadband 15 | 两轴共同死区像素 |
| verify yaw / verify pitch | 操作员确认该轴方向、中心、机械安全限位已验证 |
| manual / hold | 停止自动增量，保持脉宽与使能 |
| auto | 从当前位置进入自动，需要两轴启用、验证、尺寸正确且没有待提交脉宽 |
| status | 帧号、有效/异常、年龄、坐标、误差、生效脉宽、模式、hold 原因 |
| pwm | 内部输出高电平/周期 tick 与上升沿计数；100MHz 下100tick=1μs |

初次仅单轴、每步5μs，不做未经标定的全行程扫动。方向必须现场确认：镜头随增加脉宽向右时 yaw direction=+1，向左则−1；镜头随增加脉宽向下时 pitch direction=+1，向上则−1。如果画面翻转导致像素运动方向相反，按实际固定目标的像素误差是否下降确认，不直接用舵机标签推断。

单轴有正常运动后，在窄范围内逐步确认中心和限位，再设置 dir 与安全 limits，并 verify。之后 enable both、auto。验证左右/上下跟随、停止稳定、移走保持、短遮挡恢复、manual/auto 切换。未看到真实转动、卡住或方向不明时不要 verify/auto。操作员现场结果记录于 `docs/evidence/pan_tilt/BOARD_VALIDATION.md`。

本轮暂定现场参数：yaw方向−1、限位1500..1520μs、中心1510μs；pitch方向+1、限位1500..1540μs、中心1520μs。范围很窄，大幅移动会触及限位。默认启动仍是手动/PWM关闭、1500μs/1400..1600μs；现场参数不写非易失存储，重新下载后需重新输入并验证。

## 寄存器

完整表见 [PAN_TILT_REGISTERS.md](PAN_TILT_REGISTERS.md)。实现与测试见 `rtl/pan_tilt/`、`sim/pan_tilt/` 和 `vitis/ov5640_lcd/src/pan_tilt/`。RTL/软件仿真与原 AXI 视频回归通过不能替代现场舵机验收。
