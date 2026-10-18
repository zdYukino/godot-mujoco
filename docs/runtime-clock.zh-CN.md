# 独立仿真时钟、快照和重置

游戏 UI/渲染/输入继续运行，MuJoCo 按每个 MjRuntimeWorld 独立暂停。不改变 SceneTree.paused 或 Engine.time_scale。相机可以在暂停时继续操作。

## API

| MjRuntimeWorld 方法 | 语义 |
|---|---|
| `request_pause(true/false)` | 在物理边界暂停/恢复，清空时间余数；不补算暂停时的墙钟时间 |
| `step_simulation(N=1)` | 仅暂停时，执行 1..1000 个 MuJoCo timestep，执行后仍暂停 |
| `capture_snapshot()` | 捕获当前兼容状态和仿真 time；运行时内存快照，不写资源 |
| `reset_simulation()` | 保留当前拓扑与模型修改，恢复快照状态并清力、暖启动、重算接触 |
| `info()` | 返回 time、paused、timestep、has_checkpoint、接触和诊断信息 |

方法返回 bool 表示是否排队成功，不是事务已完成。完成信号为 `command_finished(result)`，字段包括 request、command、success、error、time、paused。pending id 为 `command_request`，最近结果/错误为 `last_command_result` / `last_error`。重复请求要等前一次完成；失败可修正后重试。

世界 `_ready` 自动请求初始快照，因此刚加入树时先等其完成再发用户命令。单步的时间增量为 `N * info().timestep`，不是 N 个渲染帧或 Godot 固定 tick。

```gdscript
if world.command_request != 0:
    await world.command_finished
if world.request_pause(true):
    await world.command_finished
if world.step_simulation(10):
    var result: Dictionary = await world.command_finished
    status.text = "%.6f" % world.info().time if result.success else result.error
if world.reset_simulation():
    await world.command_finished
```

C# 使用同一个 GDScript 节点 API：

```csharp
if (world.Get("command_request").AsInt64() != 0)
    await ToSignal(world, "command_finished");
if (world.Call("request_pause", true).AsBool())
    await ToSignal(world, "command_finished");
if (world.Call("step_simulation", 10).AsBool()) {
    await ToSignal(world, "command_finished");
    var result = world.Get("last_command_result").AsGodotDictionary();
    GD.Print(result["success"], " ", result["error"]);
}
```

原生入口为 PhysicsServer3D 的 `scene_request_world_command(space, command, count)`、`scene_world_command_result(request)` 和 `scene_cancel_world_command(request)`。普通应用优先使用 MjRuntimeWorld 包装，避免忘记取消或消费结果。

## 状态重置保留当前环境

快照保存同名/同类型的 qpos、qvel、act、ctrl 和 time。快照之后新增实例仍保留，动态状态回到其首次装入值；已删除实例不会复活。模型惯量/几何的已提交修改保留。候选状态通过验证后才替换原 mjData；失败保留原状态。

重置清除 qfrc_applied、xfrc_applied、普通 Godot 刚体单次/常量力和力矩、暖启动，重算接触并同步普通刚体缓存。原暂停/运行状态保留，提交这一 tick 不额外推进。快照不存储外部游戏脚本的任意变量；这些游戏系统需要自己的重置逻辑。

## 环境重建明确丢弃运行时改动

`MjEnvironmentHost.request_rebuild_environment(true)` 先验证并实例化保存环境到独立 World3D，成功后替换旧环境。失败不删除旧世界。传 false 会拒绝，避免把“保留增删”误解为环境重建。

外部 PackedScene 重新读取保存路径；嵌入 PackedScene 使用本次加载的保存设计，读取父场景新版本需要重启。游戏 UI、控制面板和游戏时钟位于 host 外，不随环境被删除。环境根节点要求 MjRuntimeWorld；任意外部游戏场景或单例不属于自动重建范围。

`MjSimulationControls` 提供上述按钮，Step N 点击时先提交 SpinBox 输入文本。Create simulation playground 生成 host+controls+camera；没有自动地面，需在环境设计中明确添加。

## 验证

`bash tests/runtime_clock/run.sh` 创建新 OUT 项目，执行 GDScript 与 C#。覆盖精确步数、错误请求、重复点击、paused 编辑、状态连续性、力/activation/暖启动、普通刚体缓存、重复增删、多世界、候选失败、保存重开和实际控件信号。完整结果和 dot 操作步骤见 [报告](freebase-clock-validation.zh-CN.md)。
