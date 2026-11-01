# 原始检测框跳变对照（2026-11-01）

用户反馈：点击后框跳动、云台跟随卡顿。对比`touch-blue-pd`与`b48aff9`确认仅加入显示尺寸滤波，未改变PD、搜索或原始目标坐标。上一轮仅在显示端平滑，未解决原始搜索的尺度不稳定。

现场日志源帧持续推进、err=0；目标valid频繁0/1切换，原始框也有明显位置/尺寸变化。失效时控制器清运动状态并保持位置，因此会产生断续调整。不能仅归因于PWM或PID参数。

在manual/PWM关闭时读取完整原始帧（尾标记0）与552字节目标模型，私有图像保存在忽略的build目录。相同帧重复回放，旧搜索器宽度在136/160像素间循环，中心也有4像素网格相位变化；这证明算法内部可以在输入不变时产生跳动。它不能证明所有现场丢失都由同一原因造成。

修正：候选尺度变化正则项`600*(|sw|+|sh|)+400*|sw-sh|`（sw/sh为相对上一框宽高的变化，代码用1024定点比例）；网格步长由2改为1降采样像素。保留外观阈值、失效保持、PD及显示尺寸滤波。没有增加无效目标外推驱动。

对照输入SHA256：

- RGBx：`6962555ddea0680b44cfe6c7eda48d69ad908684f09c95db064c46fd6812185f`
- 模型：`81c977950002a5fb866a03aa28f07b7a8b759a967d8b49eb39db89e03adf955f`

旧版`touch-blue-pd`在新增回放检查第33行失败（宽度稳定检查）。新版30次同图回放通过1699项检查，原始框固定为x428..563、y168..279。该测试不经过显示滤波。

合成外观检查54878项、运行时381项、PD采样12项、显示尺寸809项通过。ARM实际编译16个C文件，text164400、data2857、bss1918288，`_end=0x00300590`，未进入VDMA帧缓存。相同v3硬件bit/XSA，无RTL或时钟变化。

复现命令（需要本地私有输入）：

```powershell
./scripts/test_appearance.ps1 -CapturedFrame build/touch_shape_scene.bin -CapturedModel build/touch_shape_model.bin
```

已通过JTAG下载`app_search_stable`，PWM关闭时恢复原2187/1430μs，再恢复PD自动。静态回放通过不代替现场移动验证；现场效果及新增搜索开销待测试记录。

回退：`./scripts/download_touch_tracking.ps1 -Application app_fast`（尺寸稳定前）或`-Application app_shape`（只做显示滤波）。下载后默认manual/PWM关闭。
