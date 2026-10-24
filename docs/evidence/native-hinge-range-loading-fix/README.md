# Hinge 同号区间加载修复：开发自测证据

**这不是 dot 最终验收。** 用户要求所有最终代码/GUI验收在实际 dot 云电脑、官方 Godot 4.7.2 .NET 上执行。本目录仅记录 coding 环境的开发复现与自测；原 `7c6d87c` 不能按已通过最终验收处理。

## 缺陷、修复与边界

旧 `7c6d87c` native（SHA256 `c25f92e782aa348fa7aaa92291810230838d3b8311acf3b490fdc2cac51637c9`）在 Godot upper-first 参数加载时，把合法负上限与默认 lower 比较并错误拒绝。旧产物复现 59 pass / 8 fail / 3 ERROR、exit1：`[-2.5,-2]` 的native上限残留+π/2；另一setter顺序也可破坏正区间。见 `before/range.log`、当时脚本与退出记录。未把新产物的通过伪装为旧失败。

未启用 motor/limit 时，临时倒置的 pair 暂存，不改变已接受getter；补齐合法另一端一次提交。flag边界仍未补齐则明确拒绝并保留pending，不能由Godot重复flag调用绕过。active非法更新和非有限/超范围仍立即拒绝。成功make建立新Hinge类型默认状态再由Godot重放参数；失败make保留旧配置。clear/detach/Pin切换不携带旧pending。

合法同号区间可能远离初始零角；纠偏按原.3系数但每子步最多.2rad逐步收敛，原.25rad速度/转角保护、motor冲量预算与整段回滚均未放宽。

## 本次开发结果

最终源码 build3 exit0，native SHA256 `db56f1db873c71f43db4daec091fd1361e2b835e8ef59cb97a7cf31999f128c8`。

- 完整新suite十阶段均exit0：原65正向/18负向/12guard/18poststep/11alias/14输入smoke均通过；新增range-loading **143/143**、range-negative **15/15**。
- 四区间 `[-2.5,-2]`、`[-2,-2]`、`[2,2.5]`、`[2,2]`，两setter顺序、真实PackedScene保存重开、node缓存/native一致、从配置角零开始实际上下界运动、active节点换端点与出树重入均覆盖。
- 负例含active非法更新、pending重复enable拒绝/修正恢复、非有限/超范围、有限1e20候选make失败保持pair/flags/实际状态。range-negative严格匹配7条预期ERROR，其他负例也分别隔离；无额外ERROR/SCRIPT ERROR/leak。
- 11套关键交叉开发自测全exit0：passive Hinge、Pin、typed terrain/control、runtime clock/presets、contacts、P0 semantics、Area environment、Character、strict smoke。见 `cross/exits.tsv`。

原始新suite日志均在 `development/`；完整生成项目 `/tmp/gmj-hinge-range-active-final3`。交叉原始日志保留 `/workspace/shared/validation/hinge-range-fix`，校验清单 `cross-log-sha256.json`。

父任务独立saved诊断报告18套完成、3套受.NET NuGet mutex/只读目录阻碍，后3套不是功能失败也不是通过。本次开发环境的typed通过不能替代它们在实际dot上的最终验收。

## dot 可复用依赖与命令

源码依赖与前阶段相同：Linux x86_64、CMake/C++编译器、godot-cpp `godot-4.5-stable`（项目既有GDExtension绑定基点）、MuJoCo3.16.0、官方Godot4.7.2.NET、.NET8 SDK。官方Godot/MuJoCo下载与SHA256在 `scripts/ci/toolchain.json`；Godot安装器同时验证归档及二进制，禁止换成系统4.6.3。

```bash
python3 scripts/ci/install_godot.py /tmp/gmj-dot-toolchain
export GODOT_BIN=/tmp/gmj-dot-toolchain/Godot_v4.7.2-stable_mono_linux_x86_64/Godot_v4.7.2-stable_mono_linux.x86_64
cmake -S . -B /tmp/gmj-dot-build -DMUJOCO_VERSION=3.16.0 -DGODOT_CPP_TAG=godot-4.5-stable -DGODOTCPP_TARGET=template_debug
cmake --build /tmp/gmj-dot-build -j 2
OUT=/tmp/gmj-dot-hinge-range bash tests/native_hinge_drive/run.sh
# 其他suite取cross/exits.tsv第一列：
OUT=/tmp/gmj-dot-$suite REPEAT=1 bash tests/$suite/run.sh
```

C#验证需dot环境真实可写的SDK/NuGet运行目录；权限失败须记录受阻，不能跳过后标通过。GUI步骤在测试README，增加四个同号区间的Inspector保存重开/native比对及正反驱动限位观察。测试脚本只用于验证，不构成交付包。

## 状态与下一步

本修复在同功能分支，PR保持draft，未改main/已验收后端基线。HTML状态仍为“开发修复完成，待dot最终验收”；不得标已验收。父任务在实际dot对精确新SHA源码构建后执行完整代码和GUI验收，再决定下一步。

冷导入139未根治；无G1重负载、Windows、产品打包、远端CI或强制分配失败通过声明。
