# 阶段A构建与自检（2026-10-31）

|项目|结果|
|---|---|
|触摸映射/去抖/事件自检|PASS 768,019检查|
|十字叠加XSim|PASS 4,130检查，3,072像素，1,058背压停顿；随机valid/ready、逐像素/标志、帧内坐标保持、边界和旁路|
|PD/PID与原控制回归|PASS 新增PID115,169检查；旧P、平滑1913/1907检查通过|
|Vivado|2020.2，Validate Design及完整综合、布局布线通过|
|Setup/Hold|WNS +1.133ns、WHS +0.019ns，TNS/THS=0，无放宽原时钟约束|
|CDC|报告所有列出通路Safe；Unsafe/Unknown=0；保留原相机与视频IP跨域|
|DRC|36项Warning/Advisory，无Error；包含输入缓冲、DSP流水、相机时钟及RAM异步控制类告警，报告保留|
|资源|LUT8749、FF13030、BRAM14、DSP2|
|触摸管脚|R19/P20/U19 Bank34，M19 Bank35，LVCMOS33/PULLUP；无同包脚冲突|
|AXI地址|新BSP XPAR_TOUCH_GPIO_BASEADDR=0x43C30000，DEVICE_ID=1；原LCD ID GPIO保留|
|软件|新standalone BSP，13个实际C输入，包括touch_driver.c/touch_events.c；编译输入及XSA一致性核验通过|
|链接布局|当前GT1158 ELF _end=0x0013CD70，小于VDMA缓存0x01100000|
|产物|新bit/XSA及独立ELF路径和哈希见BUILD_MANIFEST.json；旧lost二进制未覆盖|

驱动采用新AXI GPIO，未复制参考工程54/55的PS GPIO编号；其编号在当前工程属于摄像头SCCB。复位/INT选择电平主动输出，I2C使用开漏模拟，有界等待、ACK检查，不更新控制器Flash。

真实型号并非参考GT9147，而是板上读取GT1158；寄存器差异按上游Linux v6.6 Goodix协议核对。映射数学自检通过不代表实物校准通过，现场记录单列，不把本报告当作阶段A已完成。
