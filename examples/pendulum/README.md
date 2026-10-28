# 可编辑摆杆 / Editable pendulums

```bash
./boostup.sh
./em_run.sh --exp pendulum
```

F5 运行 Main.tscn；打开 ChaosPendulum.tscn、VisualDebug.tscn 后按 F6。三个演示均使用
共享 MjRuntimeWorld，已保存 body / geom / joint 作者层级。fromto 胶囊已规范化为等价
位姿与尺寸，保留材质、相机和灯光。混沌双摆的初始关节位置随场景保存；仿真按世界
时钟推进，不再每帧手动调用 MjWorld.step。

VisualDebug 显示接触点、世界坐标下的接触力、body 坐标系、关节锚点/轴和质心。
在本地场景树或 Inspector 编辑设计，后台验证后 F5；运行中编辑会自动暂停并重建，
完成后手动继续。Ctrl+D、Undo/Redo、Ctrl+S 使用 Godot 原生操作。

HeadlessTest、ChaosPendulumTest、VisualDebugTest 等诊断场景和独立 MjWorld API 继续保留。
它们验证独立接口，不承担图形演示的物理推进。

All three visual demos now use the shared backend and persistent editable author nodes.
Independent MjWorld diagnostic scenes remain available. Keep the repository addon and asset links intact.
