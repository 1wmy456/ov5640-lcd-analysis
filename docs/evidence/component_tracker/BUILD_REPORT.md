# 构建与仿真记录（2026-10-26）

分支 `codex/component-cap-tracking`，原分支起点 `b21def1`。构建为独立副本 `build/component_tracker_v2`，软件为 `build/component_tracker_v2_sw`。原工程和旧构建保留；53 个保护文件经逐字节核验，与开始工作时的本地快照一致。用户先前未提交的 XPR/SCCB 改动没有被覆盖。

## 实际执行结果

|项目|结果|
|---|---|
|C 连通域、椭圆、目标关联自检|PASS，12,348 检查，34 帧；主机耗时6ms不代表板卡性能|
|C 运行接口与硬件快照仿真|PASS，7,267 检查、6,750 掩码读、9 次统一提交|
|集成视频/AXI/三缓冲/显示反馈 XSim|PASS，4,569 检查，1,730 输入与1,730 输出、803 次停顿、144 绿像素|
|掩码多字/最后部分字/最后蓝像素 XSim|PASS，25 检查、4帧|
|原双轴PWM/AXI-Lite XSim|PASS，251 检查，实际100MHz默认参数脉冲4次|
|原控制算法 C 回归|PASS，符号/死区/反向/限速/限位/小数/重复帧/过期/恢复/模式切换|
|原蓝色AXIS五配置回归|每组115,886检查、36帧、0失败|
|原Video In颜色/异步FIFO回归|PASS，2,449检查、3帧、288像素，R/G/B字节2/1/0|
|Vivado BD Validate/保护审查|PASS，原cells/nets/地址保持，新支路接入；校准参数记录见manifest|
|综合/布局/布线/bit/XSA|完成，Vivado2020.2，XC7Z020CLG400-2|
|setup/hold|WNS +0.953ns / WHS +0.045ns，TNS/THS 0，原100MHz约束保留|
|CDC|已报告跨域端点全部Safe；Unsafe=0、Unknown=0，无新增跨时钟统计支路|
|DRC|36条：32 Warning、4 Advisory，无Error；保留完整报告，不声称零告警|
|资源|LUT8494(15.97%)，FF12755(11.99%)，BRAM14(10%)，DSP2(0.91%)|
|新standalone BSP/ELF|完成，11个实际C文件包含新检测与运行接口，BSP宏0x43C20000|
|程序与VDMA缓存布局|`_end=0x00134c10`，低于帧缓存起点`0x01100000`|

第一次独立构建 `build/component_tracker_release` 的 setup WNS 为 −0.413ns，被构建门禁拒绝，没有下载。长路径来自组件模式不再需要的全局bbox统计；新模式改用轻量坐标/帧校验模块，旧模式仍保留原统计模块。第二次构建为上述v2并通过时序，未降低频率或放宽约束。

DRC包括原摄像头/LCD输入缓冲、原异步RAM复位和时钟检查告警，以及PWM脉宽换算DSP流水建议。实际U5/T5无冲突，均LVCMOS33、Bank13。原跨域FIFO保持不变；CDC报告不能代替传感器端输入时序的实测。

逐文件源代码/产物/报告SHA256及实际构建参数见 `BUILD_MANIFEST.json`。新模块实测耗时和现场观察另见 `BOARD_VALIDATION.md`。

组件模式保留原蓝色阈值 BLUE_MIN80、BR_DELTA60、BG_DELTA35、MIN_B_R_RATIO2，MODE2、2px绿色框、关闭中心十字。旧模式的水平MIN_BLUE_RUN3和全局MIN_PIXELS256参数仍在配置记录中；新模式用4×4单元阈值、多数滤波及单域面积/形状筛选替代这两项全局统计条件。选中域面积为单元面积估计，不等于逐个原像素的精确蓝色计数。
