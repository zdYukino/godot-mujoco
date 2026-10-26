# 第二台 G1 热添加：分层缩减复现

本目录是诊断工具，不是热加已修复的声明。基线为
`codex/gallery-grid-help` 的 `101b588b58f0f4d450d25e5ec26e75b64d4b1b73`。
不修改产品代码、G1 碰撞、质量、步进或控制。2026-10-26 的实际 dot 缩减结果尚待父任务安排；
开发环境能够通过，不替代实际 dot 失败结论。

## 已知证据与来源

下表来自父任务及原实际 dot 代理保留的历史工具回执，不是本次重新读取原日志。
原代理本次访问 `/workspace/shared/validation` 和 `/workspace/shared/tools` 得到 ENOENT；
这仅说明该代理当前环境不可访问这些路径，不说明所有环境数据丢失。
本开发环境保存的 `/tmp/g1-*` 是开发日志，不是实际 dot 原件。原证据不覆盖、不删除。

| 实际 dot 候选 | 最后边界 | 退出 | RSS 峰 KiB | 最低可用 KiB |
|---|---|---|---:|---:|
| c768324 | `load.copy_spec_begin` 无 end | 151.388 s / -2 | 1,199,000 | 1,111,564 |
| ebfc67b | 三对象 attach 完成；`rebuild.compile_begin a=1` 无 end | 151.610 s / -2 | 1,238,032 | 1,078,644 |
| d9f9297 | 串行标记 a=9；`rebuild.compile_begin a=0` 无 end | 150.393 s / -2 | 1,212,032 | 1,091,676 |

均未触 400 MiB 安全阈值；不能据此认定 OOM，也不能完全排除内存压力。
单台无控 G1 倒地、正接触及失败添加后原状态保持已在实际 dot 通过。
**重要混杂**：历史测试先运行第一台 6 秒，再执行失败添加探针，然后才添加第二台；
ebfc/d9f 还增加了所有权转交后的非法变换探针。此前没有同环境“直接热加”对照。
默认和串行均失败，因此本轮不再默认重复串行矩阵。

## 缩减结构与各自能回答的问题

| 模式 | 保留的路径 | 诊断目的 |
|---|---|---|
| Godot `hot` | 原生 configure/load，第一台运行 360 帧，再直接加载第二台 | 移除 UI、视觉和前置失败事务后是否仍卡 |
| Godot `hot probes` | 同 hot，但第二次加载前执行重力选项冲突及非法变换两个失败探针 | 失败事务历史是否影响后续加载 |
| Godot `cold` | 同一空间加载两台，第一台不运行 | 若 hot 卡，是否依赖已运行的世界状态 |
| standalone `hot` | 纯 MuJoCo parse/compile/forward，deep-copy attach + bodyToFrame；第一台运行 3000 个 .002 s 步，再组合两台、迁移、forward | 不加载 Godot，原生资产/组合编译本身能否复现 |

三种 Godot 模式只创建一个 PhysicsServer space，直接调用 API。没有 Node3D 模型、
Camera、CanvasLayer、HDR、材质、碰撞覆盖、插件面板、模型视觉重建或第二视口。
原有加载阶段 trace 保留。`hot probes` 只隔离失败事务顺序，不模拟 UI 按钮等待两帧、
package resource 校验或视觉查询，因此通过仍不能排除原完整示例的这些差异。
原生程序链接准备时指定的 MuJoCo SDK 库，不链接 Godot（实际动态加载身份的限制见下文）；保留源 spec 编译后再 attach 的顺序。
其状态迁移使用仓库 `mj_state_transfer.h`，不是全套 Godot 重建器；没有 Godot RID 分配、
unordered_map 遍历、Godot 内存分配器或编辑器默认文档预编译。两程序的原生仿真时间
分别约 6.000 s 和 6.016 s，不宣称逐位轨迹相同；各自检查重建前后的精确保持。

## 固定版本和资源

- Godot 4.7.2 .NET，历史实际 dot 引擎 commit `ed1daf0`；运行输出实际版本和 CPU 数。
- MuJoCo 3.16.0，官方预编译、`GMJ_BUILD_MUJOCO_FROM_SOURCE=OFF`。
  `libmujoco.so.3.16.0` SHA256：
  `d89b5532a1ec9c4ca8744449d648233a2f7ae5d9e7b2ccddd692e11955f6cb04`。
- 基线扩展必须来自本分支并含原生阶段日志；无需为本工具重改 C++ 扩展。
  prepare 会记录扩展 SHA、SDK 库 SHA、仓库 HEAD、模型 XML 和每个 STL SHA，并检查
  SDK 与项目内暂存的 MuJoCo **磁盘文件** SHA 相同。这不证明两个进程实际加载了该库：
  `LD_LIBRARY_PATH`、`LD_PRELOAD` 和动态链接器解析可能改变加载结果。监控报告记录这两个
  继承环境变量，但本工具尚未通过 `/proc/PID/maps` 或 `dladdr` 验证实际加载对象身份；
  也未检测 preload 的符号替换。manifest 中明确记录此范围，不能把磁盘比对写成强制同库。
- 复用 `examples/g1_passive/models/passive_g1_*/model.tres` 的完整 snapshot，
  逐字提取 XML；只复制 XML 引用的 **34 个 STL**，不重跑 URDF 导入，不合并/简化碰撞。
  另复用 gallery floor 包。源 URDF和 sky不需要；snapshot 来源字段可保留失效路径，
  加载仅依赖所列包资源。
- 单机 native counts：69 G1 geom＋1 floor，nv=35，nu=0；双机：139 geom，nv=70，nu=0。
  自由基座、29 hinges、重力和原来的 contype=2/conaffinity=1 保留；不声称机器人互碰。
- 出生位置 Godot `(-1.8,.82,0)` / `(1.8,.82,0)`，两者 Z 旋转 -5°，
  与已保存第一台变换及第二台添加代码一致。独立 MuJoCo 坐标映射为 `(x,0,.82)`、Y +5°。
- Unitree 固定源 commit `5994d4faef0a9cadd3287f8de0199a67eeb2a259`，BSD-3-Clause。
  prepare 附带原 LICENSE 和 upstream manifest；不再复制资产进 Git。

## 准备：不启动完整示例、不打开用户桌面

Linux x86_64，Python 3、C++17 编译器；工具位置由执行者确认，不假定父环境路径仍存在。
先加载环境中已验证的 Godot/SDK。下面的 `SDK` 必须指向有 include/mujoco 和 lib 的 3.16.0 SDK。

```bash
cd /path/to/godot-mujoco
export GODOT_BIN=/path/to/Godot_4.7.2.NET
export SDK=/path/to/mujoco-3.16.0
export OUT=/tmp/g1-minimal-unique
python3 tests/g1_hot_add_repro/prepare.py --out "$OUT" --sdk "$SDK"
```

OUT 必须全新，避免覆盖证据。prepare 不运行 Godot；只提取已有 snapshot，复制依赖，
构建独立 C++ 程序并登记原生扩展。不需要 editor import，不需要 .NET 编译。
检查 `$OUT/manifest.json` 后执行一个分支。不要并行运行，不自动执行完整矩阵。

## 实际 dot 建议的条件式执行顺序

第一步优先直接热加，区分前置失败探针及被移除的 UI/视觉路径：

```bash
GMJ_TRACE_SCENE_LOAD=1 python3 tests/g1_hot_add_repro/bounded.py \
  --log "$OUT/godot-hot.log" -- "$GODOT_BIN" --headless --path "$OUT/project" \
  --fixed-fps 60 --script res://runtime.gd -- hot
```

若直接热加通过，仅下一步测试前置失败事务：

```bash
GMJ_TRACE_SCENE_LOAD=1 python3 tests/g1_hot_add_repro/bounded.py \
  --log "$OUT/godot-probes.log" -- "$GODOT_BIN" --headless --path "$OUT/project" \
  --fixed-fps 60 --script res://runtime.gd -- hot probes
```

若直接热加已卡在组合 compile，下一步优先独立原生程序（不是再次运行完整 Godot 示例）：

```bash
python3 tests/g1_hot_add_repro/bounded.py --log "$OUT/native-hot.log" \
  -- "$OUT/native" "$OUT/project" hot
```

仅在需要区分第一台运行历史、且已有结果支持时，运行 cold：

```bash
GMJ_TRACE_SCENE_LOAD=1 python3 tests/g1_hot_add_repro/bounded.py \
  --log "$OUT/godot-cold.log" -- "$GODOT_BIN" --headless --path "$OUT/project" \
  --fixed-fps 60 --script res://runtime.gd -- cold
```

不要继承 `GMJ_DIAGNOSTIC_SERIAL_COMPILE=1`；基准使用默认编译配置。
独立程序可接尾参数 `serial`，但本轮不默认重复已失败的线程对照。

## 资源边界、日志与判读

每次最多两台机器人，无长期压力测试。默认墙钟上限 **45 秒**；启动前可用内存低于
768 MiB 则不启动，运行时 MemAvailable 低于 400 MiB 或采样 RSS 超过 1800 MiB
即 SIGTERM 自己创建的进程组，3 秒内仍有活进程才 SIGKILL 同组。正常 leader 退出后
也检查并清理该组后代；通过 monitor-local Linux subreaper 收养并回收孤儿后代。读取异常、
KeyboardInterrupt 或监控器收到 SIGINT/SIGTERM 都进入 finally 清理并写明退出原因。
leader 在发完信号前不 reap，避免 PGID 被过早复用。报告记录 signals、remaining 和 errors，
有残留或清理错误不会报告成功。不会查杀其他 Godot、桌面或用户进程。
保证范围是自己创建且保持在同一进程组/session 的程序；主动另建 session/进程组的逃逸程序、
监控器被 SIGKILL 或宿主崩溃不在可捕获清理保证内。本复现的 native/Godot 子程序不主动这样逃逸。
这是有界保护，不保证宿主不会发生压力；父任务应在空闲时串行安排。

`*.log` 保存完整 stdout/stderr，`*.resources.json` 保存退出原因、时间、采样 RSS、最低可用内存、
每 5 秒各线程 CPU ticks/state/wchan、前后 cgroup memory.events/pressure 和 I/O pressure。
这些是 **采样值**，不是内核精确峰值；wchan 也不是用户态调用栈。
程序若很快成功可能不足两个 CPU 样本；若卡住45秒应有多个样本。
不可读的 cgroup 路径记录错误，不改系统配置、不换路径绕过权限。

预期成功必须同时满足 exit=0、日志结尾 PASS，及 139 geom/无 actuator、第一台 qpos/qvel/time
精确保留。失败应记录最后 begin/end、资源 reason；超时不是程序返回 false，不能写成功。
若停在 combined compile / rebuild.compile_begin，说明本次未到 transfer；若 compile 返回而
transfer 卡住，则是不同故障边界。`hot probes` 中探针本身异常会立即 FAIL，不继续制造歧义。

当前仍缺：实际 dot 缩减结果、卡住时全部原生用户态线程栈、内部 spec 指针/缓存身份与前后变化。
manifest 只证明输入字节相同，不能证明内部对象相同。若仍卡，应先交回阶段日志、CPU/cgroup
采样给父任务；需要调试器采样时另定一次有界方案，不自动延长超时或重复完整测试。

## 开发环境自检（2026-10-26，仅验证工具可运行）

见本目录 `evidence/development/` 的阶段原始日志与资源摘要。最终脚本本地结果：

| 分支 | 退出 | 墙钟秒 | 采样 RSS 峰 KiB | 结果 |
|---|---:|---:|---:|---|
| standalone hot | 0 | 1.105 | 958,232 | time≈6.0，139 geom，迁移保持 |
| Godot cold | 0 | 1.209 | 1,290,160 | time=0，139 geom，迁移保持 |
| Godot hot | 0 | 1.406 | 1,297,204 | time≈6.016，139 geom，迁移保持 |
| Godot hot probes | 0 | 1.409 | 1,112,060 | 两种拒绝均发生，之后迁移保持 |

编写时首轮 standalone 版本整数误写为31600，启动自检立即失败，未编译模型；已改为官方头文件
编码3016000。随后检查出生姿态映射并统一最终路径，旧开发试跑留在原 /tmp 目录，没有冒充
实际 dot 证据。上述最终四项没有重跑完整 gallery/G1 GUI 验收，**未复现实际 dot 停滞，也未修复它**。

## 监控器小测与参数拒绝（不运行 G1）

```bash
python3 tests/g1_hot_add_repro/test_bounded.py
```

覆盖正常退出、leader 退出但留下忽略 SIGTERM 的后代、超时、监控器 SIGTERM 中断、
注入 `/proc` 读取异常；逐项确认所创建进程均被回收，并确认另一个独立测试进程组未被触碰。
测试证据在 `evidence/monitor-review/`。本轮 5 项通过；异常、超时和中断路径均执行
SIGTERM→SIGKILL（假进程故意忽略 TERM）。这不是新的 G1 矩阵测试。

入口仅允许 README 列出的模式，拼错 `hots` 在 native 返回1、Godot返回2，并在模型加载前
明确提示 unknown mode rejected；不再静默进入 cold。磁盘 SHA 限制的措辞收紧没有新增同库实测结论。
