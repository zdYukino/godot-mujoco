# 地形类型化 C# 接口

插件内 `GodotMuJoCo.TerrainDesign` 和 `TerrainHandle` 复用专用静态地形节点和同一安全事务。
Linux x86_64、Godot 4.7.2 .NET / MuJoCo 3.16；没有增加原生 shape 或后台编译范围。

```csharp
using GodotMuJoCo;
var design = TerrainDesign.Create(2, 2, new float[] { 0, 0.2f, 0, 0.1f });
if (!design.Success) { GD.PrintErr(design.Error); return; }
// parent 是已配置 MjRuntimeWorld 内的 live Node3D，调用在 Godot 主线程。
var created = TerrainHandle.Create(parent, "Terrain", design.Value);
if (!created.Success) { GD.PrintErr(created.Error); return; }
using var terrain = created.Value;
var result = await terrain.InitialRequest!.Finished;
if (!result.Success) { GD.PrintErr(result.Error); return; }
var state = terrain.Read();
if (state.Success) {
    var update = terrain.Update(design.Value, state.Value.Revision);
    if (update.Accepted) GD.Print((await update.Finished).Success);
}
```

`TerrainDesign.Create` 校验并复制高度数据，返回只读数组、宽深、刚性世界姿态和掩码。
一米间距，X/Z 行序；2..256 的固定分辨率，有限 ±10000 米。后续修改调用方数组不影响
已创建设计。姿态禁止缩放/剪切。设计对象本身不持有 live Godot 节点。

`TerrainHandle.Create` 创建有场景 owner 的节点并入队初始设计；`Success` 仅表示创建节点
及请求被接受。`InitialRequest.Finished` 才是实际物理提交结果。失败可读错误并重试 Update。
创建时启用后续保存/重开的 auto_apply；不会自动写磁盘。

`Bind` 支持继承脚本。已有节点的 `InitialRequest` 为 null。`Read` 返回 identity、generation、
revision、active、pending、error 和已提交设计（未提交时为 null）。读取会先获取已完成
的 native 结果并可能派发完成信号，确保设计与版本一致。它不直接修改 model/data。

`Update(design, expectedRevision)` 要求显式非负版本，队列接受与实际成功分开。
相同节点的不同句柄共享 pending 门槛；两个地形实例互不串扰。分辨率变化需先移除。
`Remove()` 成功后旧句柄失效；若继续使用同一节点，显式 Bind 后以 revision 0 添加新代。
删除节点、World3D 释放、退出/重入同一节点也会使旧句柄失效。Dispose 只结束观察，
不删除节点，也不承诺取消已接受的物理事务；节点生命周期由场景树管理。

保存使用普通 Godot PackedScene/ResourceSaver，保存的是节点导出设计属性，不包含
live RID、revision、仿真速度或检查点。重开会重新应用设计并从新 revision 开始。
所有 live 句柄操作在 Godot 主线程；不要阻塞主线程等待 Task。数值设计可以在其他线程
准备，随后在主线程提交。直接 GDScript、调试器和 C# 使用同一 owner/revision 边界。

## 验证

```sh
OUT=/tmp/typed-terrain-new bash tests/typed_terrain/run.sh
```

先配置固定 Godot/.NET 环境并提供已构建 native 库。本阶段无 C++ 改动。
包含两个地形、两个轻量滑动关节模型、普通 box，验证接触、两模型状态保持、并发与隔离、
过期版本和分辨率错误、完成前读取、继承、删除/重加/重入及保存重开。
每阶段退出码和日志保留；ERROR/leak 即失败。负例失败日志与正向结果分别存放。

dot：运行此入口，再用固定 .NET 编辑器打开生成项目，构建并 F6 运行 TypedControl.tscn，
确认结构化结果、停止/重开后复跑；它是日志验收场景，不是地形编辑面板的鼠标验收。
面板流程见 [地形编辑器](heightfield-editor.zh-CN.md)。强制候选编译/分配失败未注入，
未跑重 G1、迁移压力，冷导入 139 保持既有限制。
