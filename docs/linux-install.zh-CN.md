# Linux 插件安装与故障排查

[返回中文首页](../README.md)。固定环境为 Linux x86_64、Godot **4.7.2 .NET 官方版 ed1daf0bf**、MuJoCo **3.16.0**。Ubuntu 22.04 是目标使用环境，现有独立图形证据来自 Debian/Mesa 环境，不代表 Ubuntu 已完成同等验收；Windows 等其他平台未适配本基线。

## 构建依赖与产物

需要 Git、Python 3（godot-cpp 绑定生成器使用）、CMake ≥3.24、C/C++17 工具链以及 Make 或 Ninja。先用 `cmake --version` 检查实际版本，不假定发行版默认包满足要求。C# 项目另需 .NET SDK 8；GDScript 使用仍采用上述固定 .NET 版 Godot，但无需创建 C# 项目。

截至 2026-10-18，[GitHub Releases](https://github.com/zdYukino/godot-mujoco/releases)没有已发布包。仓库跟踪的 `demo/addons/godot_mujoco/bin/` 只有占位文件；clone 后直接复制 addon 不会带来 native 库。请先构建：

```bash
git clone https://github.com/zdYukino/godot-mujoco.git
cd godot-mujoco
cmake -S . -B build -DMUJOCO_VERSION=3.16.0
cmake --build build -j2
```

首次配置联网获取 MuJoCo 官方 Linux 运行库和 godot-cpp。MuJoCo 下载使用 CMake 中的固定校验值；godot-cpp API 目标是 `godot-4.5-stable`，不是验收引擎版本。不要用旧 Godot 代替固定引擎，也不要复用其他 MuJoCo 版本的 build cache。

默认构建会把以下文件复制到 `demo/addons/godot_mujoco/bin/`：

- `libgodot_mujoco.linux.template_debug.x86_64.so`：本项目 GDExtension，静态链接 godot-cpp。
- `libmujoco.so.3.16.0`：扩展依赖的 MuJoCo 运行库；同目录还保留 `libmujoco.so` 等复制产物。

`.gdextension` 根据 debug/release 选择扩展文件；默认开发构建不能当作所有导出模式的二进制包。动态依赖通过 `$ORIGIN` 查找相邻 MuJoCo 库，通常无需为了 MuJoCo 设置全局 `LD_LIBRARY_PATH`。主机仍必须满足这些 ELF 文件的系统依赖；目标机可检查：

```bash
ldd demo/addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so
ldd demo/addons/godot_mujoco/bin/libmujoco.so.3.16.0
```

如有 `not found` 或符号版本错误，先解决目标机依赖/构建环境，不把 Debian 上的成功等同于 Ubuntu 上的二进制兼容证明。

## 打开仓库 demo

```bash
export GODOT_BIN=/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64
"$GODOT_BIN" --version
"$GODOT_BIN" --editor --path demo --rendering-method gl_compatibility
```

期望输出 `4.7.2.stable.mono.official.ed1daf0bf`。让图形编辑器完成首次初始化。`demo/project.godot` 默认主场景 `Main.tscn` 是独立 `MjWorld` 摆杆示例，未预先启用编辑插件或选择 MuJoCo PhysicsServer。默认 F5 看到旧摆杆是正常现象。

## 复制到现有项目

关闭目标项目编辑器，备份同名 addon，再从已经构建的仓库根目录执行：

```bash
TARGET_PROJECT=/absolute/path/to/your-godot-project
mkdir -p "$TARGET_PROJECT/addons"
cp -a demo/addons/godot_mujoco "$TARGET_PROJECT/addons/"
cp -a demo/addons/mujoco_editor "$TARGET_PROJECT/addons/"
```

保留两个目录的相对路径，尤其是 `.gdextension`、`model/` 脚本和完整 `bin/`。重编译替换 native 库时先退出编辑器，再复制并重新打开。模型资源和网格不在这两个 addon 内：

- 自己的 MJCF：保持 XML/include/mesh 依赖完整，导入后 Save project model。
- 已保存 portable 包：复制整个 `mujoco_models/model_<哈希>/`，不要只复制 `.tres`。
- 使用内置 G1 按钮：还需将 `demo/assets/robots/unitree_g1` 复制到目标 `assets/robots/unitree_g1`，保留许可证及原始文件；无需 G1 时不必复制它。

## 两项独立设置

**可视化编辑器：**在 Project → Project Settings → Plugins 启用 **MuJoCo Model Editor**，顶部出现 **MuJoCo**。插件要求 native `MjEditorDocument` 已成功加载，但独立文档预览不要求更换项目物理后端。

**共享运行世界：**使用 `MjRuntimeWorld` 或受支持的普通 Godot 刚体后端时，在项目设置搜索 **3D Physics Engine**，选择 **MuJoCo** 并重启编辑器。高级设置中保持独立物理线程关闭。对应项目设置为：

```ini
[physics]
3d/physics_engine="MuJoCo"
3d/run_on_separate_thread=false
```

旧 `MjWorld` 自行持有模型和步进，不要求该后端；不要同时把它当作共享世界的所有者。启用插件、选择后端、指定 F5 主场景是三件不同的事。

Save project model 后，Create runtime scene 生成 world+instance，需自行提供相机/光照；Create simulation playground 生成带相机、光照、控制面板的场景，初始暂停。两者都不自动添加地面。打开生成场景按 F6，或设置为主场景再 F5。

## 常见问题

| 现象 | 检查 |
|---|---|
| 插件报缺少 MjEditorDocument / 看不到 MuJoCo 后端 | 是否先构建，native 文件路径/架构是否匹配，`ldd` 是否缺库；完全重启编辑器 |
| 工作区可编辑，生成场景却不能运行 | 是否选择 MuJoCo 3D Physics Engine 并重启，是否关闭独立物理线程 |
| F5 仍是旧摆杆 | 主场景仍为 Main.tscn；改为生成的 playground，或对当前场景使用 F6 |
| 基础 runtime scene 没有画面 | 该场景没有相机/光照；添加它们，或使用 playground |
| 云桌面音频初始化失败 | 在项目设置中选择 Dummy 音频驱动，让 F5 子进程也使用该设置；不是物理修复 |
| 嵌入窗口看似灰屏 | 确认主场景、相机和驱动，查看整桌面含游戏子窗口；只截图编辑器父窗口可能遗漏画面 |

已验证的图形路径是 GL Compatibility。部分云宿主需要正常的 Mesa/ICD 配置；[驱动配置及历史证据](mouse-gui-fix.zh-CN.md)中的工作区路径属于测试环境，不能原样当作所有用户的安装命令。不要把关闭嵌入视为嵌入修复。

早期宿主 Vulkan 探测 ERROR 保留为历史失败；配置正常软件驱动后，当前开发基线的 dot 轻量真实 GUI/F5 已通过。实际渲染为 llvmpipe/OpenGL compatibility，不是 Vulkan 渲染验收。详见[当前开发基线](linux-editor-runtime-baseline.zh-CN.md)。

## 首次导入与运行限制

cold import 139 未修复，按当前日常使用范围列为非阻断遗留。首次优先使用图形编辑器，初始化后可用 headless 脚本/API 编辑已有设计。[两条日常路径](daily-paths-baseline.zh-CN.md)不证明所有模型/宿主的冷导入稳定性，也不能证明 139 仅发生于无窗口模式。

`scripts/import_headless.sh` 是自动化辅助：检查 4.7.2 mono 版本前缀并加入 frame delay；它不是精确官方 binary 哈希校验器，也不是 139 修复。保留首次失败记录，缓存重试不可改称 fresh pass。本安装流程不依赖该辅助脚本。

不要用 SceneTree.paused 或 Engine.time_scale=0 代替 MuJoCo 世界暂停，否则游戏 UI 和命令处理也可能停止。文件系统项目搬迁已验证，PCK/ZIP 中外部资产直接加载未验证。其余限制与重负载用户手测见[已知问题](known-issues.zh-CN.md)及[手测清单](linux-baseline-manual-checklist.zh-CN.md)。
