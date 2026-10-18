# 模型资源、场景和搬迁

[返回中文索引](README.zh-CN.md)

## 模型包

Save project model 发布 `res://mujoco_models/model_<内容哈希>/`：

- `model.tres`：MjModelResource、规范化 MJCF、保存的初始状态与来源信息。
- `model.xml`：可读的规范化 MJCF；include 已展开。
- `assets/<sha256>.<扩展名>`：网格/纹理的字节相同副本。
- `sources/<sha256>.xml`：原始 XML/include 的溯源副本。

包内运行依赖是相对路径；原路径只作为来源信息，不能成为搬迁后的隐式依赖。保存先验证完整候选，再原子发布；失败保留旧文档和已发布包。同内容去重，同名不同内容使用不同哈希。已发布包不可变；编辑后保存新包，再明确更新场景引用。

旧 `.gmj.json` 编辑文档仍可能依赖原绝对路径，改文件名不能让它自动变 portable；必须先成功 Save project model。

## 场景结构

`MjRuntimeWorld` 持有 world_model 资源来确定全局 MuJoCo options；它的后代 `MjModelInstance` 各自持有 model 资源、实例 RID、独立状态和 property revision。多个实例可共享不可变资源，但不会共享正在推进的 mjData 状态。普通支持的 Godot 刚体与这些模型处于同一 PhysicsServer space，可发生真实接触。

同一 World3D 只能有一个 MjRuntimeWorld。第二个世界使用 own_world_3d 的 SubViewport。world/model options 冲突、缺失资源、损坏依赖或不支持的全局 userdata/mocap/keyframe 会明确拒绝；不要通过删除参数让模型“看起来加载成功”。

Create runtime scene 生成基础世界和实例。Create simulation playground 在游戏 UI 外层加入 MjEnvironmentHost、MjSimulationControls 和相机，初始暂停。环境 host 使用独立 World3D，使重建候选能与旧环境隔离。

模型实例节点的初始 transform 必须是无缩放的刚体变换。自由 G1 运行后根节点跟随真实 pelvis；编辑器里修改 scale 不是修改物理尺寸的受支持方式，应编辑模型几何并保存新资源。

## 搬迁验证

复制整个项目，包括 addon bin、模型包及 assets；先让原路径不可用，再导入/运行新位置，检查两实例、普通刚体接触和 C#。本仓库 `tests/portable_runtime/run_runtime.sh` 自动覆盖该流程，并把缺模型/重复 world owner 的故意错误放入隔离子进程。

文件系统项目是当前支持路径；PCK/ZIP 内依赖提取未验证。详见 [英文资源格式细节](portable-models.md) 和 [最新报告](freebase-clock-validation.zh-CN.md)。
