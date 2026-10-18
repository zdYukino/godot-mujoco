# godot-mujoco

最新验证：[真实鼠标Tree修复、G1 GUI与图形宿主配置](docs/mouse-gui-fix.zh-CN.md)（开发候选，尚非稳定基线）。

在 Godot 中使用 MuJoCo 物理、编辑 MJCF，并将可搬迁模型放入普通 Godot 场景。

**本分支范围：Linux x86_64，Godot 4.7.2 .NET 官方二进制，MuJoCo 3.16.0。** 不把其他平台或历史版本的记录视为当前验证结果。原生扩展无需修改 Godot 引擎。

[English](README.en.md) · [中文文档索引](docs/README.zh-CN.md) · [最新功能与验证报告](docs/freebase-clock-validation.zh-CN.md)

## 当前能力

- 原生 `MjPhysicsServer3D`：普通 Godot box、sphere、plane、cylinder 刚体和 ray 查询，与导入模型共享同一物理空间。
- 真正的 EditorPlugin MuJoCo 工作区：模型树、视口选择/移动/旋转/尺寸、关节参数、质量/惯量、适用 PD 参数、撤销/重做和保存重开。
- `MjModelResource` 不可变模型包；`MjRuntimeWorld` 管理空间，`MjModelInstance` 管理独立模型实例。资源及网格依赖可随整个项目搬迁。
- G1 固定基座默认流程，以及显式自由基座/松弛关节导入。自由 G1 无重力补偿，会在重力和碰撞下倒伏；没有站立/步行控制器。
- 物理步边界的运行模型修改、失败回滚和 revision；独立仿真暂停、1/N 单步、内存快照重置与保存环境重建。
- GDScript 与 C# API。原有 `MjWorld` 独立模型演示继续保留，不能将它与共享 PhysicsServer 世界混同。

## 快速开始

需要 CMake ≥3.24、C++17 编译器、网络连接及上述固定 Godot 二进制；C# 构建还需要 .NET SDK 8。

```bash
cmake -S . -B build -DMUJOCO_VERSION=3.16.0
cmake --build build -j4
export GODOT_BIN=/实际路径/Godot_v4.7.2-stable_mono_linux.x86_64
"$GODOT_BIN" --version
GODOT_BIN="$GODOT_BIN" scripts/import_headless.sh demo
"$GODOT_BIN" --editor --path demo
```

构建会下载固定 MuJoCo 运行库并放入 `demo/addons/godot_mujoco/bin/`。godot-cpp 的兼容 API 目标仍为 `godot-4.5-stable`，这不是本分支的验收引擎版本。不要复用其他 MuJoCo 版本的 CMake cache。

项目中选择 MuJoCo 作为 3D Physics Engine，重启编辑器，启用 `mujoco_editor` 插件。顶部进入 MuJoCo 工作区，导入模型，**Save project model** 后生成 runtime scene 或 simulation playground。详见 [安装](docs/linux-install.zh-CN.md)、[编辑器](docs/mjcf-editor.zh-CN.md)、[模型资源](docs/portable-models.zh-CN.md)。

## 运行控制的两个重置按钮

| 操作 | 保留什么 | 恢复什么 |
|---|---|---|
| 重置仿真：保留增删 | 当前实例、运行时增删、已提交模型修改 | 内存快照中的 time/qpos/qvel/act/ctrl；清除力与暖启动、重算接触 |
| 重建已保存环境：丢弃运行时增删 | 游戏 UI/输入/游戏时钟 | 保存的环境场景；运行时新增对象被丢弃、删除对象重新出现 |

两者都保持原暂停/运行状态。环境候选失败时保留原世界。运行快照不自动写入设计文件。API 和例子见 [时钟及重置](docs/runtime-clock.zh-CN.md)，修改模型的事务见 [运行安全编辑](docs/runtime-safe-editing.zh-CN.md)。

## 验证与已知限制

[本阶段报告](docs/freebase-clock-validation.zh-CN.md) 包含命令、退出码、日志归档、截图和精确 commit/tree。通过的自动测试不能替代 dot 的独立桌面验收。

- dot 对 e16a4ec 独立构建/资产检查通过，但自由基座运行退出 **137（原因未明）**；clock fresh import 退出 **139，未到功能测试**。详见 [独立验收记录](docs/freebase-clock-validation.zh-CN.md)。
- **cold-import 139 未解决**：首次导入辅助脚本只是时序缓解，不能用缓存重试伪装 fresh pass。
- 本次独立游戏窗口通过；编辑器 GUI 仍有宿主 Vulkan 探测 ERROR，虽然退出 0，严格 gate 仍为失败。不能宣称 F5 嵌入问题或稳定基线已全部解决。
- 当前 runtime world 要求主线程物理模式；不支持 `physics/3d/run_on_separate_thread`。同步编译允许暂时阻塞 UI，不承诺后台无停顿。
- 不在本阶段开发 Area、CharacterBody、Godot 全关节映射、地形、站立或步行。PCK/ZIP 中的模型资源需要文件系统资产方案，未作为支持路径验证。
- 36 个 Unitree 原始资产保持字节不变；派生模型单独生成。Linux 之外的旧构建配置不代表已验收。

[完整中文索引及历史证据说明](docs/README.zh-CN.md)。
