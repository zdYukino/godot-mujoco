# G1 自由基座验收

固定 Linux、Godot4.7.2.NET、MuJoCo3.16.0；原始36份Unitree资产只读。自由基座显式选择relaxed模式，不提供站立或行走控制。

- `OUT=/新目录 bash tests/freebase/run.sh`：44项无界面回归，含free root、动态生命周期、脚底接触、摩擦对比及普通Godot障碍物碰撞。
- `DISPLAY=:91 OUT=/新目录 bash tests/freebase/run_gui.sh`：先跑44项，再打开实际游戏窗口，通过XTEST真实鼠标和键盘操作产品控件。需要python-xlib、ImageMagick及1600×1000 X11桌面；无GPU宿主需配置正常图形驱动，不能忽略Vulkan ERROR。

GUI覆盖暂停时UI计时继续、Step9精确0.018秒、继续/暂停、快照/状态重置、候选失败回滚和成功重建。低摩擦、高摩擦、障碍物三个夹具仅派生模型资源，不改上游文件；通过真实Step N控件分段执行1000个物理步（2秒仿真时间），采集脚底接触、位置、采样穿透深度、有限数值和警告计数。低摩擦位移应比高摩擦多0.05米，障碍物场景必须观察到G1与普通StaticBody3D的接触对。

`gui_probe.gd` 的Fixture按钮只选择候选已保存场景；实际重建仍由产品按钮和安全边界事务完成。观测脚本不直接写正在step的model/data。截图、JSON状态、测量值、原始日志与严格结果保存在OUT。任何ERROR/泄漏、非零退出、超时或脚本异常均失败。此云端GUI不能替代dot独立验收，也不证明已知cold import139消失。
