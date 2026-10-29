# 日常编辑验收

当前流程使用 MJCF XML → body / joint / geom 层级节点。旧模型包、Apply 面板与升级路径已移除。

节点、Inspector、保存与实时同步验收：

```bash
python3 tests/node_authoring/run.py --out /absolute/new/output
```

可见编辑器的碰撞设置、提示、撤销、导出与独立重开：

```bash
DISPLAY=:0 python3 tests/node_authoring/collision_gui.py --out /absolute/new/gui-output
```

界面驱动在隔离工程中使用 Godot Window 输入与定向 X11/XTEST 输入，输出截图、观察状态与结果，不修改现有例程。
