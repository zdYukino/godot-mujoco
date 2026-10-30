# 可编辑摆杆 / Editable pendulums

```bash
./boostup.sh
./em_run.sh --exp pendulum
```

F5 运行 Main.tscn；打开 ChaosPendulum.tscn、VisualDebug.tscn 后按 F6。三个演示均使用
共享 MjRuntimeWorld，已保存 body / geom / joint 作者层级。fromto 胶囊已规范化为等价
位姿与尺寸，保留材质、相机和灯光。混沌双摆的初始关节位置随场景保存；仿真按世界
时钟推进，不再每帧手动调用 MjWorld.step。

三个场景均采用共享 MuJoCo 相机、拾取和扰动逻辑。Tab / Shift+Tab 原版左右面板，F1 帮助、F2 MuJoCo Info，Space 暂停，Backspace 初始重置；F11 仅为 Godot 渲染选择、独立性能和扩展。VisualDebug 改用官方诊断图元；在原版 Rendering 中打开接触、坐标系、关节及质心选项；在 F11 → Renderer 切换 Godot / MuJoCo 原生后端。
在本地场景树或 Inspector 编辑设计，后台验证后 F5；运行中编辑会自动暂停并重建，
完成后手动继续。Ctrl+D、Undo/Redo、Ctrl+S 使用 Godot 原生操作。

HeadlessTest、ChaosPendulumTest、VisualDebugTest 等诊断场景和独立 MjWorld API 继续保留。
它们验证独立接口，不承担图形演示的物理推进。

All three visual demos now use the shared backend and persistent editable author nodes.
Independent MjWorld diagnostic scenes remain available. Keep the repository addon and asset links intact.
