# 轻量综合工作流

Linux x86_64，Godot 4.7.2 .NET、MuJoCo 3.16.0。两个固定基座单关节模型、一个普通 Godot box 和专用静态地形；无需 G1 资产。使用产品级 `WorldHandle`、`InstanceHandle`、`TerrainHandle`，区分请求 accepted 与实际 completed，等待期间禁用重复操作。

先按仓库说明构建 native 扩展并放入 `demo/addons/godot_mujoco/bin`，确保 `godot` 指向固定 .NET 版本，`dotnet` 可用：

```sh
OUT=/tmp/gmj-light-example GODOT_BIN=/path/to/godot bash examples/light_workflow/run.sh
```

OUT 必须是新目录。入口复制插件、导入、生成便携模型及 Environment.tscn、编译 C#，再运行七项 headless 闭环断言；每步真实退出码见 executions.tsv，原始日志及 results.json 保留。退出非零或 ERROR/leak 均失败。冷导入 139 仍是独立已知限制，失败时不执行后续阶段，不用缓存重试冒充 fresh pass。

GUI：用同一 Godot 打开 `$OUT/project/project.godot`，F5，或 `godot --path "$OUT/project" --audio-driver Dummy`。独立窗口可用于环境对照，不能视为嵌入显示修复。

1. 初始暂停，两个模型、box、地形可见。拖动滑块更新两个关节的相反目标（弧度）；点“精确步进 100”，时间增加 0.2 秒，关节反向运动。
2. 连续步进或继续运行，box 落在地形上。暂停后时间停止；重复点击事务按钮时等待完成，不重复排队。
3. “重置仿真”回到初始化 checkpoint；滑块同步恢复的控制值。“记录复位点”后继续步进，再重置，应恢复新 checkpoint 时间与控制。
4. “抬高地形角点”通过 revision 安全事务更新。观察 accepted/completed；错误显示在状态栏。重置恢复仿真状态，不撤销已提交地形设计。
5. Stop 后重新 F5、关闭编辑器重开项目：初始模型/地形配置重新生成运行状态；运行时角点和 checkpoint **不保存为设计资源**。持久设计编辑使用地形编辑面板的保存工作流。

Headless 覆盖初始化、精确步进、双模型控制、box 接触、reset、pause/resume、新 checkpoint。实际鼠标布局、F5 嵌入、保存重开 GUI 需独立验收，不能由自动结果替代。本例不新增后台线程、站立行走、地形雕刻或打包。
