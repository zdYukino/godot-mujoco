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

1. 初始暂停，两个模型、box、地形可见。**F11 → Examples** 中的滑块更新两个关节的相反目标（弧度）；在 **F11 → Tools** 设置步数 100 后执行精确步进，时间增加 0.2 秒，关节反向运动。
2. 连续步进或继续运行，box 落在地形上。暂停后时间停止；重复点击事务按钮时等待完成，不重复排队。
3. Backspace 初始重置，与 Simulation 中的记录 / 恢复快照分开；滑块同步恢复后的控制值。旧 C# `WorldHandle.Reset()` 仍保留 checkpoint 语义，新增 `ResetInitial()` / `RestoreSnapshot()` 和 `ViewerHandle`。
4. 地形角点在 Godot 编辑器中修改，可 Undo、Ctrl+S；编辑器发起的后台重建完成后手动继续。运行界面的地形设计按钮及游戏→编辑器设计通道已经移除。
5. Stop 后重新 F5、关闭编辑器重开：从已保存设计初始化。运行时姿态、控制和快照不会回写设计。Ctrl+L 事务式读取最后保存的设计，重载后 C# 控制器重新绑定新世界。


MJCF 显式使用 `compiler angle="radian"`，关节限位为 ±1 弧度，与滑块 ±0.7 弧度一致。验收检查场景作者数据中的弧度限位，并要求两个关节正向及反向跟踪 ±0.5 弧度（误差小于0.03），不能仅以运动符号判断通过。

Headless 覆盖初始化、精确步进、双模型控制、box 接触、reset、pause/resume、新 checkpoint。实际鼠标布局、F5 嵌入、保存重开 GUI 需独立验收，不能由自动结果替代。后台设计编译使用可强制取消的独立进程，详见[节点编辑指南](../../docs/node-authoring.zh-CN.md)。
