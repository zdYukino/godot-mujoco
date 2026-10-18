# 自由基座与独立仿真时钟：实现和验证

本阶段沿用 `codex/freebase-simulation-controls`，基于已修复 dot 两项缺陷的 257d48。WIP f3b70df 只作草稿持久化，以下完整测试取代其 9 项初步结果。main 未修改；Godot 官方二进制未修改；36 个原始 Unitree 文件逐字节 SHA-256 和 git blob SHA-1 校验通过。

## 自由基座

`MjEditorDocument.import_g1(path, free_base=false, relaxed=false)` 保留原默认固定基座行为。编辑器新增 **Import free G1 (relaxed)**，显式使用 `(true,true)`：pelvis 增加 `floating_base` 自由关节，所有 body 的 gravcomp=0，不创建合成 PD 驱动。选择 `(true,false)` 才添加原合成位置 PD；它不是站立控制器。没有站立、步行或 RL 验收。

URDF 编译可能把固定 pelvis 合并入 world；自由基座派生流程先编译副本验证原资产结构，再向保留 pelvis 的工作副本加自由关节。原文件不写回。自由关节 qpos 为 `[x,y,z,qw,qx,qy,qz]` 共 7 项，qvel 为 `[vx,vy,vz,wx,wy,wz]` 共 6 项；均遵循 MuJoCo 坐标/旋转约定。Godot 位置转换为 `(x,z,-y)`，自由关节角速度是 MuJoCo 局部旋转速度，不能当作 Godot 世界角速度直接使用。

运行 `MjModelInstance` 从真实 pelvis 的 body transform 更新根 Node3D，随后用真实 geom 世界姿态更新网格。没有靠移动网格伪造自由基座。`scene_state().bodies` 暴露质量、惯量、gravcomp 和物理位姿；`scene_info().contact_details` 暴露接触距离、位置、摩擦及两侧 geom/body 名称。

44 项物理验证（含后续同一节点重入回归）包括自由下落、qpos/qvel 维度、无驱动/无补偿、质量/惯量有限性、原脚底球接触、低/高摩擦对照、普通 Godot 障碍接触、无 MuJoCo warning 与有限状态。相同初始水平速度 1.5 m/s，120 个 Godot 物理 tick 后低/高摩擦位移约 3.07/1.12 m；最深接触约 2.62 cm，测试界限为 4 cm。该数值是此软接触、松弛倒伏用例的界限，不是所有模型的穿透保证。

## 时钟、状态重置、环境重建

游戏进程/渲染/UI/相机不使用 SceneTree.paused 或 Engine.time_scale 来暂停物理。每个 `MjRuntimeWorld` 独立管理 native space；暂停/恢复会清掉余数累积，恢复后没有墙钟时间补算。单步只允许暂停时执行 1..1000 个原始 MuJoCo timestep，执行后继续暂停。

新 API：`request_pause(bool)`、`step_simulation(N=1)`、`capture_snapshot()`、`reset_simulation()`。返回 bool 表示请求入队；完成结果由 `command_finished(result)` 发出，`last_error` 和 `last_command_result` 可查询。重复请求在前一次未完成时明确拒绝。原 `set_paused` 保留给加载/卸载事务和兼容代码；面板使用排队 API。

快照默认在世界首次物理步前捕获。重置在 native `_step` 安全边界分配候选 mjData，按名称和类型恢复 qpos/qvel/act/ctrl/time，保留当前模型和运行时增删；快照之后新增对象使用其首次装入状态，已删除对象不会复活。失败释放候选、不替换原 data。提交时清除外力、普通刚体常量力/力矩、暖启动历史，重新计算接触，更新 Godot 刚体缓存，清空时间余数，保留原暂停/运行状态。重置这一 tick 不额外推进仿真。

环境重建由 `MjEnvironmentHost.request_rebuild_environment(true)` 明确丢弃运行时增删：先在独立 SubViewport/World3D 实例化并验证保存的环境，再替换原环境。失败保留原世界、实例和状态。参数 false 会拒绝并提示使用状态重置。外部 PackedScene 从保存路径重新加载；嵌入的 PackedScene 使用本次游戏加载的保存设计，重启游戏才读取父场景新版本。模型包是不可变资源，编辑后需保存新包并明确更新场景引用。

UI `MjSimulationControls` 在 host 外，包含游戏/仿真时间、暂停、恢复、单步次数、快照、保留增删的状态重置和明确丢弃增删的环境重建按钮。**Create simulation playground** 可直接从已保存的模型生成控制界面和相机；不自动添加会改变模型接触的地面。独立示例生成器提供带地面和障碍的自由 G1 场景。

所有事务是同步、安全边界事务，不保证编译时界面无停顿。目前要求 Godot 主线程物理模式，不启用 `physics/3d/run_on_separate_thread`。运行快照只在内存中；保存模型/场景仍是设计状态，不把正在倒伏的机器人状态偷偷写入资源。

## 实测结果与命令

先 `source /workspace/shared/tools/env.sh`（本云环境）；其他机器设置实际 `GODOT_BIN`。以下每个 OUT 都是新目录，未用缓存重试冒充首次通过。

| 命令（设置 OUT 后运行） | OUT 目录尾名 | 退出码 / 结果 |
|---|---|---|
| `tests/native_backend/run.sh` | milestone-native-final | 0 / 447 |
| `tests/dynamic_scene/run.sh` | milestone-dynamic-final | 0 / 86 |
| `tests/editor_plugin/run.sh` | milestone-editor-final | 0 / 160 |
| `bash tests/freebase/run.sh` | freebase-reentry-release | 0 / 44 |
| `bash tests/runtime_clock/run.sh` | milestone-clock-release | 0 / 101 + C# |
| `tests/portable_runtime/run_runtime.sh` | milestone-portable-full | 0 / 30+30+84+9+41、C#、重启 |
| `tests/g1_actuation/run.sh` | milestone-g1-full | 0 / native、GDScript、C#；各 29 joints、60 trials、240000 steps |

OUT 根目录为 `/workspace/shared/validation/`。G1 命令另设置 `MUJOCO_ROOT=/workspace/shared/builds/godot-mujoco-3.16/_deps/mujoco-src`、`GODOT="$GODOT_BIN"`。构建 `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j4` 退出 0。

Clock 测试覆盖重复暂停/恢复、精确 1/N 步、无效输入、重复点击、普通刚体缓存/外力、激活状态/暖启动、paused 模型编辑、运行时反复增删、多 World3D 隔离、快照时间、环境候选失败、重建、保存重开及真实按钮信号。单步次数测试直接写输入框文本再点击按钮，不只改 SpinBox.value。

portable 的两项故意错误仍只在独立负向子进程验证，分别 6/8 项；各只允许一条匹配的预期 ERROR，任何额外错误/泄漏都失败。正常日志没有豁免，详见此前 [隔离规则](portable-isolated-rejections.md)。

原始日志归档：[raw-logs.zip](evidence/freebase-clock/raw-logs.zip)，逐文件哈希：[manifest](evidence/freebase-clock/raw-log-manifest.json)，测试结果及二进制哈希：[summary](evidence/freebase-clock/summary.json)。早期失败保留在云环境 `freebase-01/02/03`、`runtime-clock-01`、`milestone-clock-complete` 等目录，未标作通过。

## GUI 与限制

官方 Godot 实际独立窗口：`--path <freebase OUT>/project --rendering-method gl_compatibility --audio-driver Dummy --position 0,0 --resolution 1500x950 res://FreebasePlayground.tscn`，退出 0，无 ERROR/泄漏。截图来自真实窗口：[9 步=0.018秒](evidence/freebase-clock/runtime-step9.png)、[松弛倒伏](evidence/freebase-clock/runtime-fallen.png)、[状态重置后](evidence/freebase-clock/runtime-reset.png)。游戏时间持续增加而仿真时间可冻结/回零。

实际编辑器测试退出 0、163 项操作/截图检查通过，但日志有两条 Vulkan 探测 ERROR，**严格 GUI gate 判为 FAIL**。保留 [编辑器截图](evidence/freebase-clock/editor-gui.png) 和完整日志，不通过过滤错误来宣称稳定。已知 cold-import 139 仍是独立未解决限制；本次成功的 fresh import 不证明稳定率。

dot 复验：运行 `tests/freebase/run.sh` 生成干净项目后，将 `tests/freebase/prepare_playground.gd` 复制到其 project，运行 `godot --headless --path <project> --script res://prepare_playground.gd`。打开该项目和 `FreebasePlayground.tscn`，分别验证独立窗口及 F5 嵌入显示。初始暂停；右键拖动/滚轮相机应继续响应。输入 N 后点击单步，观察精确仿真时间；恢复到倒伏，再暂停、状态重置、环境重建。添加第二个 G1/普通刚体并重复增删，确认状态重置保留、环境重建丢弃；另一 World3D 不受影响。复验最新树高亮和球柱按钮修复，不把此阶段自动测试代替 dot 的桌面验收。


## 自由根节点重入补充

在功能提交后的生命周期检查中补充保存/恢复 authored spawn transform：运行中跟随 pelvis 的根节点在卸载或离开场景树时恢复初始放置变换，下一次加载不把倒伏后的物理姿态再次当作放置偏移。明确卸载后手动设置的新放置仍会在下一次加载时生效。

`freebase-reentry-release` 新目录测试退出 0，44 项通过；新增 3 轮同一节点 unload/load 与 remove/add，检查无累计位姿偏移。初始 32 项日志保留，不重标为 44 项。后续日志见 [自由基座重入证据](evidence/freebase-reentry/)。

该修复后追加复跑 `freebase-reentry-portable`（30+30+84+9+41、C#、隔离负向用例及重启）和 `freebase-reentry-clock`（101+C#），均退出 0；正常日志无 ERROR/泄漏。原始日志打包于 [followup-logs.zip](evidence/freebase-reentry/followup-logs.zip)。中文入口/指南 74 个本地链接目标检查通过。


## dot 对 e16a4ec 的独立验收更新

据 dot 独立报告：构建成功，36 个原始资产一致，中文文档 90 个本地链接有效；自由基座运行退出 **137，原因未明**；clock 的 fresh import 退出 **139，未进入功能测试**。这些结果与云端自动测试分别记录，不用云端通过覆盖 dot 失败，不推断 137 为 OOM 或其他特定原因。cold-import 仍是独立限制，不开展受阻的引擎冷导入/内存补丁调试。

随后应用层重建结果反馈缺陷的修复与实际按钮回归见 [控件反馈修复报告](rebuild-feedback-fix.zh-CN.md)。
