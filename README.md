# godot-mujoco

在 Godot 中导入、编辑和运行 MuJoCo 模型，也可将静态地图及受支持的 Godot 刚体放进同一个物理世界。

[English](README.en.md) · [安装详解](docs/linux-install.zh-CN.md) · [更多使用文档](docs/README.zh-CN.md)

本页按“安装 → 启用插件 → 在编辑器运行例程 → 导入和保存地图”组织。当前开发与验收在 **GTR Ubuntu 22.04.5 x86_64** 进行。本分支仍有复杂 SDF 扫掠边界待完成；能力限制见文末，详细实现与测试放在[开发矩阵](docs/development/spatial-query-matrix.md)。

## 1. 准备固定版本并构建插件

| 软件 | 要求 |
|---|---|
| Godot | **4.7.2 .NET 官方版**，构建 ed1daf0bf |
| .NET SDK | **8.0.426** |
| MuJoCo | **3.16.0** Linux x86_64 SDK |
| 编译工具 | Git、Python 3、C++17 工具链、CMake ≥3.24、Make 或 Ninja |

三个图形例程使用 GDScript，没有必须手动编译的 C# 项目；仍请使用上述 .NET 版 Godot。Windows 不是本轮适配或验收平台。

### 已配置好的 GTR

在 GTR 终端或已授权 SSH 会话中执行，无需重新安装：

~~~bash
. ~/.config/godot-mujoco/gtr-env.sh
cd /home/zdyukino/workspace/godot-mujoco
"$GODOT_BIN" --version
dotnet --version
cmake --build build-gtr-3.16.0 -j2
~~~

配置文件在新 SSH 会话中仍可加载。它设置 Godot、.NET SDK、CMake 和 MUJOCO_SDK_DIR；不要改用云电脑的工具或二进制。

### 在新的 Linux x86_64 环境安装

从官方来源下载固定版本，核验发布哈希，再解压到用户目录：

- [Godot 4.7.2 官方发布](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable)：选择 Godot_v4.7.2-stable_mono_linux_x86_64.zip。
- [.NET 8 官方下载](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)：选择 SDK 8.0.426，设置 DOTNET_ROOT 并将其加入 PATH。
- [MuJoCo 3.16.0 官方发布](https://github.com/google-deepmind/mujoco/releases/tag/3.16.0)：选择 mujoco-3.16.0-linux-x86_64.tar.gz。下载校验与依赖检查见[安装详解](docs/linux-install.zh-CN.md)。

版本或资产不可用时先检查原因，不自动换版本或换成普通版 Godot。准备好 Git、Python、C/C++ 编译工具和 CMake 后：

~~~bash
git clone https://github.com/zdYukino/godot-mujoco.git
cd godot-mujoco
export MUJOCO_SDK_DIR="$HOME/.local/opt/mujoco-3.16.0"
export GODOT_BIN="/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64"
cmake -S . -B build-gtr-3.16.0 \
  -DMUJOCO_VERSION=3.16.0 \
  -DGMJ_BUILD_MUJOCO_FROM_SOURCE=OFF \
  -DGMJ_MUJOCO_ROOT="$MUJOCO_SDK_DIR"
cmake --build build-gtr-3.16.0 -j2
~~~

将环境变量中的路径改为实际安装位置。构建会生成 demo/addons/godot_mujoco/bin/ 中的扩展及 MuJoCo 运行库；使用本地 SDK 可以避免重复下载。更换依赖版本时使用新的构建目录。

## 2. 安装到项目并启用

关闭目标项目编辑器，先备份同名插件，再复制两个 addon，必须包含 bin/：

~~~bash
TARGET_PROJECT="/absolute/path/to/your-project"
mkdir -p "$TARGET_PROJECT/addons"
cp -a demo/addons/godot_mujoco "$TARGET_PROJECT/addons/"
cp -a demo/addons/mujoco_editor "$TARGET_PROJECT/addons/"
"$GODOT_BIN" --editor --path "$TARGET_PROJECT" \
  --display-driver x11 --rendering-method gl_compatibility
~~~

1. 等待首次资源导入完成。在 **项目 → 项目设置 → 插件** 中启用 **MuJoCo Model Editor**。
2. 要运行共享物理世界，在项目设置中搜索 **3D Physics Engine**，将 physics/3d/physics_engine 设为 **MuJoCo**；保持 physics/3d/run_on_separate_thread=false，按提示重开项目。
3. 右侧切换到 **MuJoCo** 页签。界面使用左侧场景树、一个中央 3D 视窗和右侧属性；不用另开预览视窗。
4. 刚更新过 native 库时，完全退出编辑器后重新打开。只刷新脚本无法重新加载所有 native 改动。

编辑插件和物理后端是两项设置：能看到 MuJoCo 页签，不代表项目已经选用 MuJoCo 物理后端。下面三个例程的 project.godot 已配置插件和后端，首次打开仍应核对。

### F5、F6 和停止

- **F5** 运行项目主场景，依据 Project Settings 中的 run/main_scene。
- **F6** 运行当前打开的场景。先双击下面指定的 .tscn，避免运行错场景。
- **F8** 停止运行；也可关闭本次运行窗口。Ctrl+S 保存场景，停止运行不会代替保存。
- 运行窗口中的“暂停/继续”只控制本例仿真；与编辑器调试暂停不同。

本轮已在 GTR 原生 X11 窗口运行并截取三个例程，编辑器导入/Apply/保存重开也有自动验证。下面快捷键和手动菜单步骤作为使用指南；未宣称已经逐键完成人工验收。

## 3. 例程 1：刚体形状 gallery

在 GTR 仓库根目录执行，使用一个不存在的新项目目录：

~~~bash
export GALLERY_PROJECT="$HOME/workspace/gallery-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$GALLERY_PROJECT"
cp -a examples/shape_gallery/. "$GALLERY_PROJECT/"
cp -a demo/addons "$GALLERY_PROJECT/"
"$GODOT_BIN" --editor --path "$GALLERY_PROJECT" \
  --display-driver x11 --rendering-method gl_compatibility
~~~

1. 记下 GALLERY_PROJECT；要从项目管理器打开时，导入该目录的 **project.godot**。
2. 等待首次导入，核对插件和 MuJoCo 后端。此例已有保存的模型包，无需重新生成。
3. 在文件系统面板打开 **res://Main.tscn**。按 F6 运行当前场景；F5 也会运行 Main.tscn，因为它已设为主场景。
4. 观察球、盒、圆柱、圆锥、胶囊等形状在天空和网格地面中下落、接触。
5. 运行面板勾选 **实体** 或 **碰撞**，可分别隐藏视觉实体或显示橙色碰撞叠加。显示开关不改变物理。
6. 点击 **暂停** 冻结仿真，按钮变为 **继续**；点击 **重置** 恢复初始状态。**说明 / 帮助** 展开操作说明。
7. 完成后按 F8 或关闭运行窗口，返回编辑器。

[例程源码及素材](examples/shape_gallery/) · [隔离验证入口](tests/shape_gallery/run.sh)

## 4. 例程 2：无控制 G1 倒地与热添加

先用已有模型包准备独立项目；默认不重新导入机器人资产：

~~~bash
export G1_OUT="$HOME/workspace/g1-example-$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$G1_OUT" bash examples/g1_passive/prepare.sh
"$GODOT_BIN" --editor --path "$G1_OUT/project" \
  --display-driver x11 --rendering-method gl_compatibility
~~~

1. 项目文件是 **$G1_OUT/project/project.godot**；首次导入完成后核对插件与后端。
2. 双击 **res://G1.tscn**，按 F6。此项目的主场景也已设为 G1.tscn，F5 可运行它；不要误选同目录的 gallery Main.tscn。
3. 初始 G1 为自由基座、重力开启、没有 actuator/PD 站立控制。若面板显示“继续”，先点击继续；轻微倾斜后自由倒地是预期现象。
4. 使用 **实体 / 碰撞** 分别查看外观和碰撞轮廓；滚轮缩放，F 重新取景。
5. 点击 **添加 G1**。同步编译时会短暂停顿，成功后显示第二台和耗时，并自动取景到两台。已有实例状态、RID、世界时间及暂停/运行状态应保留。
6. 本例最多 **2 台**，第二台成功后按钮禁用。模型有意排除机器人自碰撞及机器人之间碰撞；互相穿过不代表这项配置回归。
7. **暂停/继续** 控制仿真；**重置** 恢复机器人载入姿态。结束时 F8 停止。

不要反复无界启动重型多 G1。内存紧张时先停止本次运行，查看日志，再使用[有界热添加监测](tests/g1_hot_add_repro/)。它不发送真机控制命令。

[例程说明及资产来源](examples/g1_passive/README.md) · [Unitree 资产许可](demo/assets/robots/unitree_g1/g1_29dof_mode_18/LICENSE)

## 5. 例程 3：台阶、洼地与崎岖 SDF 地形

### 先运行已准备的落球场景

~~~bash
export TERRAIN_OUT="$HOME/workspace/sdf-terrain-$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$TERRAIN_OUT" bash examples/sdf_terrain/prepare.sh
"$GODOT_BIN" --editor --path "$TERRAIN_OUT/project" \
  --display-driver x11 --rendering-method gl_compatibility
~~~

1. 项目文件是 **$TERRAIN_OUT/project/project.godot**。准备脚本会生成地形并导入资源，输出 **res://Main.tscn**、**res://assets/terrain.obj**、参数文件及独立地图包。
2. 双击 **res://Main.tscn**，F6 运行；F5 的主场景也已配置为 Main.tscn。
3. 三块闭合网格包含六级台阶、中央洼地和崎岖路面，单位 **m**、坐标 **Y_UP**、固定 seed **20261026**。默认选择真实 **SDF**，八叉树深度 **6**。
4. 观察三颗球下落并接触地形。中央球半径 0.12m，落在 -0.35m 坑底后球心应接近 -0.23m；它应落入洼地，不能悬在被填平的凸包顶面。
5. 顶部 **实体** 与 **SDF 距离切片** 独立切换。黄色轮廓是距离场切片，不是完整三维碰撞边界。
6. 本例工具条目前没有独立暂停/重置按钮。用 F8 停止，再 F6 重新运行可恢复初始落球状态；不要把隐藏实体当作暂停。

### 在右侧导入、修改碰撞并保存

以下流程使用新的宿主场景，避免替换地图根节点或叠加重复碰撞：

1. 在同一项目新建 **3D 场景**，以 Node3D 为根，保存为 **res://TerrainHost.tscn**。保持这个场景打开。
2. 右侧打开 **MuJoCo** 页签，将范围选为 **静态地图草稿**。在“导入 / 独立包”中填写 **res://assets/terrain.obj**，选择 **m** 和 **Y_UP**，点击 **导入（保留脏数据）**。
3. 在右侧地图树选择 stairs、depression、rough 各网格。滚动到 **选中对象 · 基本碰撞**，选择 **sdf**，将 **SDF 八叉树深度（0=引擎默认）** 设为 **6**，点击 **验证并应用碰撞草稿**。每块分别确认。
4. 深度 0 使用默认；显式值只允许 3..8。深度越高，编译、内存及查询成本越大。保存失败时先看右侧状态，不自动换成 mesh。
5. 使用 **MuJoCo 显示** 中的显示开关及 **聚焦全图 / 聚焦选中** 检查实体和碰撞。不要把视觉网格正确当作碰撞已通过。
6. 点击 **保存独立地图包**，记下状态栏生成的包路径；以后用 **打开地图包** 选择其 manifest.json 重开。保存地图包与保存 Godot 场景是两步。
7. 点击 **Apply 到编辑场景**，宿主下应出现一个 **StaticMap**。Ctrl+S 保存 TerrainHost.tscn；重复 Apply 应更新原地图。若更改了宿主/地图变换，按状态提示重新载入目标。
8. 关闭并重开场景或项目，确认地图和 sdf/depth 参数保留。运行实例需要明确停止并重新运行，保存文件不会自动替换已运行地图。
9. 需要在宿主中手动落球时，给 TerrainHost 添加与 StaticMap 同级的 RigidBody3D（位置 0,1.5,0，质量 0.2），添加 CollisionShape3D/SphereShape3D（半径 0.12）及匹配的 MeshInstance3D/SphereMesh。保存后 F6。此手动建球和快捷键步骤尚未逐项人工验收；已准备的 Main.tscn 是本轮真实运行过的落球入口。

### 如何比较凸包与 SDF

先另存宿主场景和地图包作为对照，再把 depression 的碰撞方式改为 **mesh**，验证草稿、Apply、保存并停止重跑。mesh 的凸包会填平凹陷，球可能停在外沿高度附近；切回 **sdf** 后应落到坑底。对照必须标明“凸包”，不要覆盖原 SDF 示例。

高度场 hfield 适合单值高度地表；SDF 封闭网格可表达更复杂凹形。视觉网格、凸包、高度场和 SDF 是不同碰撞数据。更多参数、可重复生成方式及自动对照见[例程 3](examples/sdf_terrain/README.md)。

## 6. C# 项目首次构建

三个例程不需要 C# 编译。自己的 .NET 项目已有 .csproj 时，在该项目目录执行 **dotnet build**，再用 Godot .NET 打开。首次构建可能需要恢复 NuGet 包；使用与当前 Godot 匹配的 Godot.NET.Sdk，不混用其他 SDK 版本。

仓库有可照用的[类型化 C# 控制 API](docs/typed-control.md)和隔离入口：

~~~bash
OUT="$HOME/workspace/typed-example-$(date -u +%Y%m%dT%H%M%SZ)" \
  bash tests/typed_control/run.sh
~~~

它会准备自己的 project、编译 TypedControl.csproj 并运行，日志分开保存，不改现有项目。请求入队的 Accepted 不等于完成，控制代码仍需检查完成反馈。

## 常见问题

| 现象 | 检查方法 |
|---|---|
| 缺 .so、插件类找不到 | 确认 native 构建成功，复制了完整 bin/，扩展与 MuJoCo 运行库都在；完全退出并重开 Godot |
| 提示缺 DLL、C# 无法加载 | 确认使用 Godot 4.7.2 **.NET**、SDK 8.0.426，并先在项目目录 dotnet build；不要混用普通版引擎 |
| 有右侧页签但刚体不动 | 核对 physics/3d/physics_engine=MuJoCo、主线程物理和运行面板暂停状态 |
| F5 运行错场景 | 核对主场景；先双击正确 .tscn，用 F6 运行当前场景 |
| 首次导入慢或失败 | 等待导入完成并查看输出；确认资源路径可写、资产齐全、磁盘和内存充足，不连续重复启动 |
| G1 添加按钮禁用 | 检查加载错误及是否已达 max2；无控制倒地不是站立控制失败 |
| 洼地被填平 | 核对实际碰撞方式是否 sdf，是否 Apply、保存并重新运行；不要以视觉形状判断 |
| Apply 提示不能替换根 | 新建 Node3D 宿主，把地图作为 StaticMap 子节点；不要直接替换地图场景根 |
| SSH 成功但没画面 | SSH 不等于 GUI 控制；需要已授权、已解锁的 GTR 图形会话。锁屏时继续 headless，不绕过锁屏 |
| 原生 Wayland 崩溃 | 本轮该路径报 client error 11；已有 Xwayland 下 --display-driver x11 成功，不需要更改显示安全设置 |

## 使用边界与进一步文档

普通形状、导入资源及空间查询有明确支持范围。SDF 连续扫掠默认使用 **0.5mm 总空间误差预算**，可在每个空间查询状态上设置至 1mm：
~~~gdscript
var state = get_world_3d().direct_space_state
state.call("set_sdf_query_precision_m", 0.001) # 米；默认 0.0005
var fractions = state.cast_motion(parameters)
var status: Dictionary = state.call("get_query_status")
if not status.ok:
    push_error(status.error) # 未认证不能当作无碰撞
~~~
预算针对**编译后的 SDF**，不保证原始网格与 SDF 的偏差也在 1mm 内。精确初始切触、擦边或过严预算仍可能返回未知；调用者必须检查状态。查询有耗时较长的情况，不适合默认按高频实时使用；公共 sweep 也不等于动态刚体 CCD。

[查询能力和性能限制](docs/development/spatial-query-matrix.md) · [静态高度场](docs/static-heightfield.md) · [模型包搬迁](docs/portable-models.zh-CN.md) · [运行时安全编辑](docs/runtime-safe-editing.zh-CN.md)

本项目使用 [MIT](LICENSE)。第三方声明见 [THIRD_PARTY](demo/addons/godot_mujoco/THIRD_PARTY.md)；Unitree 资产保留原有许可和来源。
