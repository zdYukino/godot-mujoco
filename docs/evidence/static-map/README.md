# 静态地图 P0–P3 开发自测（非最终 dot 验收）

基线：main 文档 dc8ff7c4b78be40fc605bf44a2f64d7039fd1561 + PR #17 精确 310d2a425b131e6a0c25cb0204f3f8d322b264bd，仅在功能分支组合；不合并远端 main / PR #17。

阶段证据：

- P0/P1：未知单位拒绝；1 m GLB/OBJ/二进制 STL 与 mm ASCII STL；非对称 glTF 层级；坏输入/缺依赖保留旧文档；缺贴图诊断；main/include/mesh/texture 内容变化，mtime 不变仍检测；dirty 冲突；规范化 MJCF 副本重导入。
- P2：显式基础体和多 Box 组合。门洞球 z=-1.032，墙前球 z=-3.534；5 级台阶射线；非方形负高度斜坡 HeightField 实际碰撞。未生成凸/凹 Shape，未自动凸分解。
- P3：核心 65/0；独立进程重开 8/0；移动地图目录且移除原输入后 8/0；缺包文件/哈希损坏/原包保留 3/0。迁移包含纹理、地形、.42 地形摩擦、层掩码、单位与来源。普通摩擦实际滑动：0 摩擦 0.722988 m、.8 摩擦 0.143446 m，并检查最终 contact friction。
- 编辑器集成 24/0：GLB ImporterMesh 转换、选择/拾取/显隐/聚焦、线框、碰撞/摩擦 Undo/Redo、包保存重开、场景 Apply/替换/Undo/Redo、来源失败回滚。**headless 编辑器测试不等于实际 dot GUI 验收。**
- 既有地形面板 67/0，运行材质 6/0，含共享材质身份 Undo 回归；`tests/portable_runtime/run_assets.sh` 通过，覆盖已有资产包迁移。未运行含 G1 的 run_runtime.sh、G1 或多机器人。

工具版本：Godot 4.7.2.stable.mono.official.ed1daf0bf；MuJoCo 3.16.0。本次重建扩展 SHA256 `126c77f18cf11e7f981ff30225a52e6b1726c0c3930d78277d9812a813f5c0ba`。

SDF 研究作为后续，不是本轮 Godot 功能：官方 cow 与无插件房间 SDF 探针通过；普通 convex mesh 对照退出 3（按预期封门）。CPU/内存、实际位置见 sdf-results.json 和日志。Godot 编辑器仍拒绝 SDF，UI 禁用该选项；默认策略仍是 visual，不静默退回凸包。全面原生碰撞属性接入已经列入 HTML 后续计划。

开发中实际发现并修复：未配置运行世界导致 HeightField 失败；编辑器 ImporterMesh 与运行 MeshInstance 类型差异；debug mesh 无 index 数组；UndoRedo Object 未释放；BUNDLE_RESOURCES 内联 class_name 脚本导致混合包重开失败。另发现 Dummy renderer 无法生成含相机的编辑器保存缩略图；headless runner 改用 PackedScene 保存，GUI runner 保留实际 EditorInterface.save_scene 路径。失败轮次没有作为通过证据。

当前限制与验收命令见 ../../static-map.zh-CN.md。整图普通对象运行热替换未实现，设计 Apply 后显式重新运行；地形与 MJCF 仍使用各自已有运行 Apply 事务。非 1 m 高度间距、自动凸分解、任意凹 Shape、SDF 产品接入、P4 UE 不在已实现范围。
