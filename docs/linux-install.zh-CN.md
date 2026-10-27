# Linux 插件安装与故障排查

[返回中文首页](../README.md)。安装基线为 Linux x86_64、Godot **4.7.2 .NET 官方版 ed1daf0bf**、MuJoCo **3.16.0**。不要求固定开发机或发行版安装路径；历史宿主验收证据按其原范围保留，不推导所有发行版均兼容。Windows 等其他平台未适配本基线。

## 推荐：克隆后一键配置 / Recommended bootstrap

```bash
git clone https://github.com/zdYukino/godot-mujoco.git
cd godot-mujoco
./boostup.sh
```

向导启动后先检查仓库工具、常见本机安装位置、PATH 和环境变量，并报告 Godot / .NET、
Python、Git、编译器、CMake、Make/Ninja 以及插件产物状态。
仓库工具已就绪时直接检查并编译，不再询问 Godot / .NET 安装来源。删除构建目录后，可直接运行：

```bash
./boostup.sh --rebuild
./boostup.sh --check       # 仅检查，不安装、不编译
./boostup.sh --configure   # 主动重新选择工具来源
```

首次配置时，默认推荐导入已检测到的兼容工具；没有匹配安装时提供下载选项。
重新配置中选择 `1` 会实际重新下载或使用校验缓存重装，不会悄悄复用已有目录；选择后立即提示
执行将在两项工具来源都选定后开始。替换失败时保留旧工具。

需要安装时，向导分别选择 Godot / .NET 8 的自动下载或已有解压目录，再显示操作摘要。
工具统一复制到被 Git 忽略的 `third_party/`，原目录保留；已安装且校验通过的仓库
工具直接复用。Godot 必须为完整 Mono 包（含 GodotSharp），.NET 必须为 SDK。
版本和官方压缩包哈希由 `scripts/ci/toolchain.json` 锁定，`global.json` 固定 SDK。

The wizard inspects existing tools first and builds directly when repository tools
are ready. `--check` only inspects; `--rebuild` skips install menus; `--configure`
opens source selection again. Compatible detected installations can be imported.
The bilingual wizard downloads the pinned tools or imports extracted directories.
Tools live under the ignored `third_party/`; source directories are retained.
Godot must include GodotSharp and .NET must be the complete SDK.

Ubuntu 22.04/24.04 缺少构建或运行依赖时，会列出软件包并请求确认 sudo 安装。
CMake 不满足最低版本时下载校验后的固定版本到 `third_party/`，不替换系统 CMake。
其他 Linux x86_64 只提供缺失依赖提示。首次构建仍需联网获取 MuJoCo 和 godot-cpp。

检查通过后自动编译，部署原生库并连接四个例程的共享插件。成功后写入：

- 仓库 `third_party/environment.json`、`environment.sh`：供入口脚本和终端加载。
- `~/.local/bin/godot`、`~/.local/bin/dotnet`：指向仓库工具的启动入口，替换同名旧入口。
- `~/.bashrc`、`~/.profile` 及已有 Bash 登录配置中的托管区块：重复运行只更新同一区块。

Open a new Bash terminal to use `godot` and `dotnet`. For the current terminal:

```bash
source third_party/environment.sh
```

入口脚本可从其他工作目录用绝对路径调用；工具配置使用仓库相对路径。
移动仓库后重新运行 `boostup.sh` 更新终端入口。删除仓库后，移除 shell 中
`godot-mujoco` 托管区块和这两个命令入口即可。向导不会扫描或删除机器上的旧 Godot。

已有工具可以直接指定，路径中有空格时加引号；`--yes` 表示接受操作摘要及依赖安装：

```bash
./boostup.sh --godot-dir "/path/to/extracted Godot" \
  --dotnet-dir "/path/to/dotnet SDK"
./boostup.sh --yes                         # 无交互，优先复用或导入，缺工具时下载
./boostup.sh --help
```

还支持 `--build-dir DIR`、`--jobs N` 和 `--mujoco-root DIR`，保持下文构建参数含义。
失败时立即停止并保留原目录；修复问题后重跑。无效工具目录或损坏下载缓存会明确指出，
请将对应路径移走后重试。重复运行不会覆盖用户新工程。

### 打开例程与创建工程 / Launch and create projects

```bash
./em_run.sh                              # 项目管理器 / Project manager
./em_run.sh --exp                        # 交互选择 / Choose an example
./em_run.sh --exp shape_gallery
./em_run.sh --exp g1_passive
./em_run.sh --exp sdf_terrain
./em_run.sh --exp pendulum
./em_run.sh --new my-project
```

`--new` 仅接受单个目录名，创建 `projects/<name>/` 并打开编辑器；目标已存在则报错。
工程复制两个完整 addon 和 Linux x86_64 开发运行库，预启用 MuJoCo 后端和编辑插件。
场景包含地面（顶面 y=0）、相机、灯光，以及半径 0.5m、质量 100kg 的球；球心 y=1.5m，
即球底离地 1m，初速度为零。F5 开始仿真，F8 停止。

New projects contain independent addons and can be moved outside the repository.
Press F5 to drop the 100kg ball (radius 0.5m, initial center y=1.5m) onto ground at y=0.
Repository rebuilds do not update those copied addons; close the editor before updating them.

新工程不包含其他平台或 release 导出库。`projects/`、`third_party/` 和例程构建、导入产物
均被 Git 忽略；例程源码、模板和必需资源仍应提交。希望版本管理自己的工程时，将其移出仓库
或单独建立 Git 仓库。工具或插件缺失时，启动脚本提示运行 `boostup.sh`，不隐式安装或编译。
无图形会话时启动失败，但已成功创建的工程保留。

## 手动准备工具 / Manual tool preparation

在任意 Linux x86_64 机器上准备以下工具，无需 GTR、云端环境文件或固定仓库位置：

| 工具 | 基线与准备方式 |
|---|---|
| Godot | [官方 4.7.2 .NET](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)，构建 ed1daf0bf；完整解压 mono Linux x86_64 包，保留 GodotSharp |
| .NET | [SDK 8.0.426](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)；私有安装设置 DOTNET_ROOT，将其加入 PATH |
| 构建工具 | Git、Python ≥3.10、C/C++17 编译器、CMake ≥3.24、Make 或 Ninja，均可从 PATH 找到 |
| MuJoCo | 默认自动下载官方 3.16.0 Linux x86_64 SDK，也可指定已经解压的 SDK |

Godot 下载 URL、压缩包 SHA256/SHA512、二进制 SHA256 和 SDK 版本记录在 `scripts/ci/toolchain.json`。可手动下载 Godot 并核验；克隆仓库后，也可在仓库根目录显式调用现有下载器：

```bash
python3 scripts/ci/install_godot.py "$HOME/.local/share/godot-mujoco/godot"
```

将下载器输出的实际二进制路径设为 GODOT_BIN。脚本只在用户指定目录安装 Godot；不会安装 .NET 或修改 PATH。其他下载也应核验官方发布哈希，不自动换版本。

## 统一检查与构建

```bash
git clone https://github.com/zdYukino/godot-mujoco.git
cd godot-mujoco
export GODOT_BIN="/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64"
bash scripts/setup.sh check
bash scripts/setup.sh build
```

若 PATH 中的 `godot` 已是准确的官方可执行文件，可使用 `export GODOT_BIN=godot`。支持软链接；指向自定义启动包装脚本时哈希校验会拒绝，需改为实际可执行文件路径。

`check` 检查平台、工具版本、编译器、官方 Godot 二进制及所选 SDK，不联网、不生成构建文件。`build` 先执行同样检查，再调用 CMake 配置和编译。默认构建目录为 `<仓库>/build-linux`，并行数为 2；不会自动启动编辑器或覆盖目标项目。

| 接口 | 用途 |
|---|---|
| `check/build --build-dir DIR` | 自定义构建目录；缓存不匹配时保留原目录并报错 |
| `check/build --mujoco-root DIR` | 官方 SDK 中 include/ 与 lib/ 的父目录 |
| `build --jobs N` | 正整数并行数，默认 2 |
| `smoke --out DIR` | 构建后独立严格验证，目录必须不存在或为空；未设置时读取 OUT，再默认创建临时目录 |
| `GODOT_BIN` | 选择 Godot；未设置时从 PATH 找 `godot` |
| `MUJOCO_SDK_DIR` | 可选 SDK 路径；命令行 --mujoco-root 优先；均未设置时下载 MuJoCo |
| `CC/CXX`、`CMAKE_GENERATOR` | 标准编译器选择；生成器支持 Unix Makefiles 或 Ninja |

脚本可用绝对路径从任意当前目录调用，路径可含空格；相对参数按当前目录解析。不会自动使用私有环境文件、修改 shell 配置或调用 sudo。缺工具时按错误提示安装，再重跑。

### 复用本地 MuJoCo SDK

```bash
bash scripts/setup.sh check --mujoco-root "/path/to/mujoco-3.16.0"
bash scripts/setup.sh build --mujoco-root "/path/to/mujoco-3.16.0" \
  --build-dir "/path/to/build-linux" --jobs 2
```

检查器验证头文件版本和官方运行库哈希。不支持用本地路径绕过版本校验。SDK 模式避免重复下载 MuJoCo，但首次获取 godot-cpp 仍需联网，不是完整离线安装。不使用本地 SDK 时取消设置 MUJOCO_SDK_DIR。

### 等价的手动 CMake 命令

已经完成上述工具准备和版本检查后，可直接配置和构建：

```bash
cmake -S . -B build-linux \
  -DMUJOCO_VERSION=3.16.0 -DGODOT_CPP_TAG=godot-4.5-stable \
  -DGMJ_BUILD_MUJOCO_FROM_SOURCE=OFF -DGMJ_ALLOW_UNVERIFIED=OFF \
  -DGMJ_MUJOCO_ROOT:PATH=""
cmake --build build-linux --parallel 2
```

本地 SDK 模式将最后一项替换为 `-DGMJ_MUJOCO_ROOT:PATH="/path/to/mujoco-3.16.0"`，并使用另一个新构建目录。手动命令不会自动读取 MUJOCO_SDK_DIR。CMake 默认选择编译器；需要时在首次配置前设置 CC/CXX，以 Ninja 构建可增加 `-G Ninja`。

首次自动配置联网获取 MuJoCo 官方运行库和 godot-cpp。MuJoCo 下载使用 CMake 中的固定校验值；godot-cpp API 目标 `godot-4.5-stable` 与验收引擎版本是不同概念。统一入口检查已有缓存的仓库、依赖版本、SDK 模式和编译器选择；切换配置时使用新目录，不删除原缓存或悄悄沿用旧依赖。

## 构建产物

仓库里的 native 目录不包含完整编译产物，需要先构建。仓库内四个图形例程会通过相对链接直接使用构建产物；安装到其他项目时再复制 addon。

默认构建会把以下文件复制到 `addons/godot_mujoco/bin/`：

- `libgodot_mujoco.linux.template_debug.x86_64.so`：本项目 GDExtension，静态链接 godot-cpp。
- `libmujoco.so.3.16.0`：扩展依赖的 MuJoCo 运行库；同目录还保留 `libmujoco.so` 等复制产物。

`.gdextension` 根据 debug/release 选择扩展文件；默认开发构建不能当作所有导出模式的二进制包。动态依赖通过 `$ORIGIN` 查找相邻 MuJoCo 库，通常无需为了 MuJoCo 设置全局 `LD_LIBRARY_PATH`。主机仍必须满足这些 ELF 文件的系统依赖；目标机可检查：

```bash
ldd addons/godot_mujoco/bin/libgodot_mujoco.linux.template_debug.x86_64.so
ldd addons/godot_mujoco/bin/libmujoco.so.3.16.0
```

如有 `not found` 或符号版本错误，先解决目标机依赖／构建环境；已有宿主的成功不等于任意目标机的二进制兼容证明。

## 在项目管理器直接打开例程

构建完成后，启动 Godot 4.7.2 .NET 项目管理器，点击 **导入 → 选择 project.godot → 导入并编辑**。直接选择仓库内的项目，无需复制文件或运行准备脚本：

| 项目文件 | F5 默认场景 |
|---|---|
| examples/shape_gallery/project.godot | Main.tscn：形状下落与碰撞 |
| examples/g1_passive/project.godot | G1.tscn：单台无控制 G1 |
| examples/sdf_terrain/project.godot | Main.tscn：三块 SDF 地形和三颗测试球 |
| examples/pendulum/project.godot | Main.tscn：独立 MjWorld 摆杆 |

前三个项目配置共享 MuJoCo 后端，摆杆使用独立 MjWorld；各项目均配置编辑插件及 GL Compatibility。保持完整仓库目录结构，相对链接会连接共享插件、天空和着色器；首次导入完成后点击 **运行项目** 即可。日常操作见[首页](../README.md)。

## 打开独立世界摆杆例程

```bash
export GODOT_BIN="/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64"
"$GODOT_BIN" --version
"$GODOT_BIN" --editor --path examples/pendulum --rendering-method gl_compatibility
```

期望输出 `4.7.2.stable.mono.official.ed1daf0bf`。让图形编辑器完成首次初始化。`examples/pendulum/project.godot` 默认主场景 `Main.tscn` 是独立 `MjWorld` 摆杆示例，已启用编辑插件，但摆杆使用独立 MjWorld，不依赖 MuJoCo PhysicsServer。默认 F5 看到旧摆杆是正常现象。

## 复制到现有项目

关闭目标项目编辑器，备份同名 addon，再从已经构建的仓库根目录执行：

```bash
TARGET_PROJECT="/absolute/path/to/your-godot-project"
mkdir -p "$TARGET_PROJECT/addons"
cp -a addons/godot_mujoco "$TARGET_PROJECT/addons/"
cp -a addons/mujoco_editor "$TARGET_PROJECT/addons/"
```

保留两个目录的相对路径，尤其是 `.gdextension`、`model/` 脚本和完整 `bin/`。重编译替换 native 库时先退出编辑器，再复制并重新打开。模型资源和网格不在这两个 addon 内：

- 自己的 MJCF：保持 XML/include/mesh 依赖完整，导入后 Save project model。
- 已保存 portable 包：复制整个 `mujoco_models/model_<哈希>/`，不要只复制 `.tres`。
- 使用内置 G1 按钮：还需将 `assets/robots/unitree_g1` 复制到目标 `assets/robots/unitree_g1`，保留许可证及原始文件；无需 G1 时不必复制它。

## 两项独立设置

**可视化编辑器：**在 Project → Project Settings → Plugins 启用 **MuJoCo Model Editor**，右侧出现 **MuJoCo** 页签。插件要求 native `MjEditorDocument` 已成功加载，但独立文档预览不要求更换项目物理后端。

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
| 无音频设备的桌面初始化失败 | 在项目设置中选择 Dummy 音频驱动，让 F5 子进程也使用该设置；不是物理修复 |
| 嵌入窗口看似灰屏 | 确认主场景、相机和驱动，查看整桌面含游戏子窗口；只截图编辑器父窗口可能遗漏画面 |

已验证的图形路径是 GL Compatibility。宿主需要可用的 OpenGL／Mesa 驱动配置；[驱动配置及历史证据](mouse-gui-fix.zh-CN.md)中的工作区路径属于测试环境，不能原样当作所有用户的安装命令。不要把关闭嵌入视为嵌入修复。

默认让 Godot 选择显示驱动。Wayland 出错时，在已有 X11/Xwayland 会话中可尝试增加 `--display-driver x11`，并保留原错误日志。SSH 终端可运行 headless，但启动图形编辑器需要宿主的可用桌面会话。历史宿主的 Vulkan 探测、软件驱动及 GUI/F5 结果见[开发基线](linux-editor-runtime-baseline.zh-CN.md)，不作为本机已经通过验证的声明。

## 独立自动验证

```bash
bash scripts/setup.sh smoke
# 或指定一个不存在／为空的目录：
bash scripts/setup.sh smoke --out "/path/to/new-results"
```

smoke 不重新构建；先确认构建成功。它调用现有 `tests/mjworld_smoke`，核验官方 Godot/MuJoCo 二进制，记录首次导入、正负向运行和日志审计。保留所有实际退出码及 results.json；已知导入 139 分类为 blocked 并返回 3，不自动重试或改判成功。通过 headless 不代表真实渲染／GUI 验收通过。

`scripts/cloud_setup.sh` 现为兼容入口，依次调用 build 和 smoke，并提示迁移；不再下载普通版 Godot、强制 gcc 或忽略导入失败。原调用可传递 build 的参数，工具需要先按本指南准备。

仅验证入口接口、无需 Godot 或联网：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests/setup -p 'test_*.py'
```

## 首次导入与运行限制

cold import 139 未修复，按当前日常使用范围列为非阻断遗留。首次优先使用图形编辑器，初始化后可用 headless 脚本/API 编辑已有设计。[两条日常路径](daily-paths-baseline.zh-CN.md)不证明所有模型/宿主的冷导入稳定性，也不能证明 139 仅发生于无窗口模式。

`scripts/import_headless.sh` 是自动化辅助：检查 4.7.2 mono 版本前缀并加入 frame delay；它不是精确官方 binary 哈希校验器，也不是 139 修复。保留首次失败记录，缓存重试不可改称 fresh pass。图形安装流程不依赖该辅助脚本；统一 smoke 使用现有 runner 的同等单次导入缓解，不把它视为修复。

不要用 SceneTree.paused 或 Engine.time_scale=0 代替 MuJoCo 世界暂停，否则游戏 UI 和命令处理也可能停止。文件系统项目搬迁已验证，PCK/ZIP 中外部资产直接加载未验证。其余限制与重负载用户手测见[已知问题](known-issues.zh-CN.md)及[手测清单](linux-baseline-manual-checklist.zh-CN.md)。
