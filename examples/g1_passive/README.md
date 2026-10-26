# 第二示例：无控 G1 与运行时热添加

真实 Unitree G1 在同一个 `MjRuntimeWorld` 中自由落下、接触地板。此示例复用第一示例的原始 CC0 HDR、非 VRAM 导入配置、灯光、原创建模的地板和 1 m 网格，以及默认收起的帮助和紧凑运行控件。没有额外中央预览、动画倒地或平衡控制器。

## 启动保存的示例

先按仓库说明构建 Godot 4.7.2 .NET / MuJoCo 3.16 扩展并放到 `demo/addons`。从仓库根目录执行：

```bash
export GODOT_BIN=/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64
export OUT=$(mktemp -d /tmp/gmj-g1-demo.XXXXXX)
bash examples/g1_passive/prepare.sh
"$GODOT_BIN" --path "$OUT/project"
```

脚本在独立目录组装已保存的 `G1.tscn`、独立模型包、共用地板 shader 和 HDR，并进行导入。默认直接使用已保存模型，无需重新编译 URDF。仓库不重复存储 HDR，组装时从第一示例复制。`--editor --path "$OUT/project" res://G1.tscn` 可在原生编辑器打开；运行界面右上方有“添加 G1”，帮助默认收起。第二示例使用独立近景相机：初始取景第一台，成功添加后自动取景两台。滚轮缩放（单机距离限制 2–9 m，双机 4.2–9 m 以保留两台在画面内），F 恢复当前单机/双机取景；UI 消耗的输入不会传给相机，不增加拖拽操作。相机只改变视图，机器人、地板尺寸及物理状态不变。

需要从原始 URDF 重新构建时：

```bash
REBUILD=1 OUT=/tmp/gmj-g1-rebuild bash examples/g1_passive/prepare.sh
```

重新构建会校验原始 manifest，调用 `MjEditorDocument.import_g1(source, true, true)`，打包资源并重新保存 G1 场景。请使用新的独立 OUT，避免覆盖手工修改。`prepare_g1.gd` 明确采用 free-base + relaxed 路径：添加 `floating_base`，不创建合成 position/PD actuator，所有 body 的 gravcomp=0，保留来源被动关节参数。为保持第一示例环境，重力使用 -9.81 m/s²（导入器原默认为 -9.8）；积分器 implicitfast、步长 .002，地板尺寸、摩擦及颜色不变。

初始机器人位于 x=-1.8 m、骨盆 y=.82 m，向侧面倾斜 5°；第二台位于 x=1.8 m、y=.82 m，倾斜 -5°。这是载入姿态的小扰动，用于避免完全对称的理想平衡，并非动画或运行中施力。无控制情况下倒地由真实重力、关节与地面接触产生。

## 热添加边界

- 先观察第一台自然倒地，再点击“添加 G1”。最多两台，按钮显示忙态并拒绝重复点击；第二台在远离第一台初始位置的另一侧载入。
- 使用现有 `MjModelInstance.load_model` 事务，同步暂停编译并恢复之前的运行状态。不是后台异步加载，不承诺无停顿。没有重开场景、环境 rebuild 或 reset。
- 初始 G1 资源缺失或加载失败时显示 `last_error`，禁用添加；无效实例不进入更新列表，地板世界保持可用。
- 添加前后检查第一台 RID、完整 qpos/qvel、世界时间不变；失败保留原世界。两台共享不可变资源，拥有独立原生模型 RID/命名空间。
- 保留导入器 `contype=2 / conaffinity=1`：机器人与地板碰撞，**机器人间互碰和同机自碰撞被排除**。本示例不宣称验证机器人互碰。
- “重置”使用已有原生 checkpoint/born-state 逻辑，保留两台模型，恢复各自载入姿态；它不是热添加实现的一部分。
- 碰撞线框由构建时实际编译凸包/原生几何导出，保存为压缩的 `g1_collision_previews.res`。运行时两台共享线框 Mesh 和材质，逐帧只更新姿态，不重复编译来源或生成完整网格。

## 来源与许可

复用仓库 `demo/assets/robots/unitree_g1/g1_29dof_mode_18`，原始来源为 https://github.com/unitreerobotics/unitree_ros ，固定提交 `5994d4faef0a9cadd3287f8de0199a67eeb2a259`，目录 `robots/g1_description`。保留全部 34 个原始 STL 资产，不换简化人偶。完整原始文件哈希见 [upstream-manifest.json](upstream-manifest.json)，BSD-3-Clause 许可见 [UPSTREAM_LICENSE](UPSTREAM_LICENSE)。模型包内网格按原始内容 SHA256 命名，原 URDF 另存于 sources，路径转换不修改网格字节。

天空作者 Greg Zaal / Poly Haven，CC0；详细下载、SHA256 和导入设置沿用 [第一示例素材说明](../shape_gallery/assets/SOURCES.md)（组装后的独立项目中为 `assets/SOURCES.md`）。网格是项目原创，不包含 NVIDIA 地板 USD 或 MuJoCo 原纹理。

## 有界验收与资源

```bash
OUT=/tmp/gmj-g1-check bash tests/g1_passive/run.sh
# 可选：重建来源后再测，并移走原始 URDF 证明独立包可运行
REBUILD=1 OUT=/tmp/gmj-g1-rebuilt-check bash tests/g1_passive/run.sh
```

只测试一台自然倒地，再热添加一台；检查无 actuator/gravcomp、自由基座、69 个 geom（57 个 mesh geom 复用 34 个源 mesh）、两台各自对地板的正法向接触力、倒地姿态、初始资源失败处理与热加失败回滚、时间/状态连续性、双机继续运行、四显隐、重置及 1180×812 下倒地身体投影范围/缩放不改状态。输出原生模型 ID/数量、编译用时和 Linux 进程 VmHWM。没有无限规模压力测试。

当前开发环境双机 headless 测试峰值约 1.7 GB；真实渲染及编辑器需要额外内存，**不能据此保证仅剩 2 GB 的 dot 宿主能够同时开编辑器和双机**。建议串行运行独立游戏进程，关闭本任务自有验证进程后再做下一轮；不关闭用户窗口。实际 GUI、截图和最终资源可行性由父任务独立验收。

### 热加诊断与实际 dot 状态

实际 dot 在 `bf97610` 的单机和失败回滚检查通过后，热添加尚未返回即达到 150 秒测试时限；日志已进入原生编译，不能仅凭宿主可用内存判定为 OOM，也不能据开发环境通过宣称 dot 热加通过。该结果保留，待定位后再独立复验。

当前候选输出 `G1_TEST_STAGE`、`G1_ADD_STAGE`、`MJ_MODEL_LOAD_STAGE`，包含单调毫秒时间/帧号，并在热加层记录暂停状态、原生时间和对象数。可区分两次等待帧、资源校验、暂停、原生 `scene_load_model`、恢复暂停、视觉几何读取/节点构建、状态读取及碰撞覆盖创建。普通实例默认不开启详细加载日志，仅示例新添加节点设置诊断 metadata。没有延长超时或重试加载来掩盖失败。

碰撞覆盖只读取已缓存的真实线框和实时 geom 姿态，避免为了覆盖层再次导出完整 STL 顶点；这是消除冗余读取，不是已证实的 dot 超时根因。

原生细分诊断需先重编当前候选扩展，然后显式设置：

```bash
GMJ_TRACE_SCENE_LOAD=1 OUT=/tmp/gmj-g1-native-trace bash tests/g1_passive/run.sh
```

`MJ_NATIVE_LOAD_STAGE` 直接输出并刷新 stderr，使用独立操作 ID、从入口起算的单调毫秒、阶段及线程 ID。覆盖文档构造/资产路径、`mj_compile`、`mj_makeData`、`mj_forward`、spec 所有权转移、初态读取、每个模型 attach、重建编译、状态迁移、旧数据删除和文档析构；`a/b` 字段在 compile_begin 记录 compiler.usethread，在 compile_end 记录 ngeom/nv，在 make_data_begin 记录 narena/nbuffer 字节，在 forward_options 记录 integrator/solver，在 forward_begin 记录是否绑定 mjData threadpool。`G1_ENGINE_CONFIG` 记录引擎版本、显示后端、逻辑 CPU 数和项目线程设置，供两个环境对照。这些设置不被修改。

原生日志默认关闭，仅在同步 `scene_load_model` 调用栈内启用；未改暂停条件、锁、迁移或事务提交逻辑。4d 实际 dot 已确认停在 `native_scene_load_begin` 内，编译报告后仍未返回、152 秒有界结束；等待帧和覆盖构建已排除，随后 c768 的实际 dot 日志进一步定位到 `load.copy_spec_begin` 后未返回，151.39 秒有界结束（峰 RSS 1,199,000 KiB，最低 MemAvailable 1,111,564 KiB）；底层复制为何停住仍未确认。

当前运行加载将临时验证文档的 spec 所有权交给插入事务，避免 `mj_copySpec`
深拷贝编译后的网格缓存。事务在拒绝、正常移除时负责释放 spec，文档仍负责释放
自身 model/data。诊断边界改为 `load.take_spec_begin/end`；测试额外覆盖转移后
非法变换被拒绝且原世界状态/时间不变。

这移除了实际 dot 已确认停住的调用，但不是 MuJoCo 内部根因结论，仍待独立 dot
复验。CPU 数量是已记录的环境差异，并非已证实原因。依据官方 3.16.0
[user_model.cc](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/user/user_model.cc)
和 [user_mesh.cc](https://github.com/google-deepmind/mujoco/blob/3.16.0/src/user/user_mesh.cc)，
spec 复制涉及树、资产和编译网格缓存；该复制路径本身不启动编译线程池。

后续 ebfc 实际 dot 已通过所有权转移及三对象 attach，但停在组合模型
`rebuild.compile_begin`（usethread=1），151.61 秒超时；热加仍未通过。
以下为本轮已执行的组合编译 worker pool 串行对照命令，仅保留作诊断记录；本轮不再重跑：

```bash
GMJ_TRACE_SCENE_LOAD=1 GMJ_DIAGNOSTIC_SERIAL_COMPILE=1 OUT=/tmp/gmj-g1-serial-diagnostic bash tests/g1_passive/run.sh
```

仅两个开关同时为 `1` 且处于已跟踪的加载事务时，把临时组合 spec 的
`compiler.usethread` 置为 false；不更改包、资产、碰撞、solver、物理步进或系统线程设置。
`rebuild.diagnostic_serial_compile` 的 a 字段记录 C++ hardware_concurrency，
其后的 compile_begin 必须为 a=0。单独关闭 trace 即恢复默认编译路径。
此开关是隔离变量的诊断，不是已确认修复；即使通过也需区别诊断配置与默认配置。
官方选项说明：[compiler usethread](https://mujoco.readthedocs.io/en/stable/XMLreference.html#compiler-usethread)。
开发环境使用官方预编译 3.16.0，`GMJ_BUILD_MUJOCO_FROM_SOURCE=OFF`；
libmujoco.so.3.16.0 SHA256 为
`d89b5532a1ec9c4ca8744449d648233a2f7ae5d9e7b2ccddd692e11955f6cb04`。
实际 dot 已核对 MuJoCo 库 SHA 完全相同，且同为 `GMJ_BUILD_MUJOCO_FROM_SOURCE=OFF`。

本轮最终实际 dot 结果（父任务独立执行并回传）：

- 单台真实 G1 无控制倒地通过：无 actuator、无重力补偿、自由基座及 29 个铰链，
  骨盆从约 0.82 m 降至 0.102 m，有地板正法向接触力，无 MuJoCo warnings。
  已验证失败添加回滚时第一台 qpos/qvel、RID 和仿真时间保持。
- 默认组合编译配置（ebfc，usethread=1）热加仍在 `rebuild.compile_begin`
  后停滞，151.61 秒超时退出（exit -2）。
- 最后串行对照候选 `d9f929723d281f65eecb928258c5c1593cd03463` 的日志确认
  `rebuild.diagnostic_serial_compile a=9`、`rebuild.compile_begin a=0`，
  开关确已生效；150.393 秒内仍无 compile_end，超时退出（exit -2）。
  峰 RSS 1,212,032 KiB，最低 MemAvailable 1,091,676 KiB，未触发 400 MiB
  资源阈值；这些数据不足以认定 OOM，也不证明所有资源因素均已排除。
  该次实际 dot 原生扩展 SHA256：
  `194661c5dfbd29e064e95d011c7cb8aefb0316b38c98ae9951ec714ade4748ee`。

因此实际 dot 的热加功能未通过验收，默认与串行配置均超时，根因未定；不能归因于
CPU 数差异、MuJoCo 库版本不一致或仅编译 worker pool。开发环境通过记录仅适用于
开发环境，不能作为全部完成或实际 dot 热加通过的声明。本轮停止进一步诊断补丁和
重跑，保留原失败证据及物理模型不变；单机通过与热加阻碍分别记录。

2026-10-26 后续工作仅整理 [分层缩减复现](../../tests/g1_hot_add_repro/README.md)，
区分直接热加与前置失败事务，不重复完整盲测；实际 dot 热加仍未通过。
