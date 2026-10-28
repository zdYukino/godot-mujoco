# 轻量综合工作流

Linux x86_64，Godot 4.7.2 .NET、MuJoCo 3.16.0。两个固定基座单关节模型、一个普通 Godot box 和专用静态地形；无需 G1 资产。使用产品级 `WorldHandle`、`InstanceHandle`、`TerrainHandle`，区分请求 accepted 与实际 completed，等待期间禁用重复操作。

先构建仓库插件，再直接打开 `examples/light_workflow/project.godot`，正常 Build C# 后按 F5。
`Main.tscn` 已保存两个模型的完整作者层级、box、地形、相机和灯光；不需要 prepare。

```sh
./em_run.sh --exp light_workflow
# 隔离验收：导入、正常 .NET build、运行九项断言
OUT=/tmp/gmj-light-example GODOT_BIN=/path/to/godot bash examples/light_workflow/run.sh
```

OUT 必须是新目录。退出非零或 ERROR/leak 均失败，原始日志及 results.json 保留。

1. 初始暂停，两个模型、box、地形可见。拖动滑块更新两个关节的相反目标（弧度）；点“精确步进 100”，时间增加 0.2 秒，关节反向运动。
2. 连续步进或继续运行，box 落在地形上。暂停后时间停止；重复点击事务按钮时等待完成，不重复排队。
3. “重置仿真”回到初始化 checkpoint；滑块同步恢复的控制值。“记录复位点”后继续步进，再重置，应恢复新 checkpoint 时间与控制。
4. “抬高地形角点”向对应编辑器场景请求修改，可 Undo、Ctrl+S；后台重建完成后手动继续。独立运行时禁用设计按钮。重置恢复仿真状态，不撤销已提交地形设计。
5. Stop 后重新 F5、关闭编辑器重开：从已保存设计初始化。游戏请求的角点修改出现在本地场景，Ctrl+S 后持久保存；运行时掉落位置和 checkpoint 不会自动变成设计初态。


MJCF 显式使用 `compiler angle="radian"`，关节限位为 ±1 弧度，与滑块 ±0.7 弧度一致。验收检查场景作者数据中的弧度限位，并要求两个关节正向及反向跟踪 ±0.5 弧度（误差小于0.03），不能仅以运动符号判断通过。

Headless 覆盖初始化、精确步进、双模型控制、box 接触、reset、pause/resume、新 checkpoint。实际鼠标布局、F5 嵌入、保存重开 GUI 需独立验收，不能由自动结果替代。后台设计编译使用可强制取消的独立进程，详见[节点编辑指南](../../docs/node-authoring.zh-CN.md)。
