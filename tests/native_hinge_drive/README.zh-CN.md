# 有界 Hinge 限位／速度电机验收

仅独立的 world/static/两 rigid 端点 pair，不允许端点同时连接其他 native joint。固定 Linux x86_64、Godot 4.7.2 .NET、MuJoCo 3.16；本入口不运行 G1 或重负载。

```bash
source /workspace/shared/tools/env.sh
# 先由主任务从本次源码构建 addon，不使用旧 native。
OUT=/tmp/hinge-drive-check bash tests/native_hinge_drive/run.sh
```

复用已验收 Pin/Hinge 辅助脚本，仅复制到临时项目，不改旧测试。保存十阶段日志与真实退出码：import、positive、negative、guard、poststep、alias、range-loading、range-negative、gui-smoke、input-smoke。正常日志出现 ERROR／泄漏即失败；negative 精确匹配 10 条预期错误；guard 独立匹配 1 条预期错误和 12/12 断言；poststep 与 alias 各严格匹配 2 条预期错误，分别要求 18/18 和 11/11 断言。range-negative 另外严格匹配 7 条错误，正常 range-loading 不能有任何 ERROR。任何额外 ERROR、SCRIPT ERROR 或泄漏失败。`results.json` 包含逐项结果和 native SHA256。导入失败后未运行阶段不能显示通过。

## 数值契约与覆盖

- frame Z 轴，角度为 A 相对 B，角速度单位 rad/s。正向测试检查真实姿态、速度幅值、正负反转；相位偏移 frame 的等限锁定不能把初始角误当零。
- limit lower≤upper 且在 `[-3,3]`；相等表示锁定。上／下界、电机与限位同时、关电机后外力矩下限位分别验证。
- target velocity 输入范围 `[-100,100]`，max impulse `[0,1000]`。合法输入不保证任意步长／数值状态都可运行。
- 每次实际 server span 共享冲量预算，分配给内部子步。1kg/r=.2m 球的轴向惯量 `.016 kg·m²`，预算 `.001 N·m·s` 应得 `Δω=.0625 rad/s`；分别用 1 和 10 个子步验证预算不倍增。零预算不驱动。
- 1kg/2kg 两 rigid 电机验证不同角速度和等反向角动量（分别使用惯量 .016/.032）；旋转 frame、偏移 COM、非对称盒惯量与 static 端验证实际响应，不只读参数。另有真正偏心锚点：球 COM 距轴 1m，预算 .001 得 ω≈.001/(.016+1)，同时验证 COM 切向速度与锚点保持，避免把锚点恰在 COM 的案例误作平行轴覆盖。
- 独立两 pair 的数值响应互不串扰；integration callback 内更新目标／预算在下一 span 生效，随后同一 callback 中参数更新→clear 按序完成，另一 pair 继续驱动。暂停参数更新不推进物理；checkpoint reset 恢复仿真状态但保留之后修改的关节设计；clear 解除约束。真实 HingeJoint3D PackedScene 保存重开后检查 flags 与实际 1.5 rad/s 目标。
- 非有限／超范围／倒置限位／端点图违约原子拒绝，旧电机继续作用。被动反平行 frame 可保留，但主动 motor/limit 模式保守拒绝反平行初始轴。

固定 bias/softness/relaxation 默认值只是初始化兼容，未映射为可调求解参数；这不是任意关节图或完整 Godot 求解器等价声明。

## 数值 guard 与完成反馈

`guard.gd` 来自主任务独立审查探针。要求 MuJoCo 子步 `dt≤.02s`，相对角速度每子步转角满足实现的 `.25rad` 界限；它不是把整个多子步 span 限为 `.02s`。异常驱动在隔离阶段失败，整 span 回滚、空间暂停；速度（包括尚未消费的阻尼）、姿态、仿真时间和一次性力矩保持。不能发出虚假的 integration callback，也不能让单步请求先报告 success。完成结果须来自实际模拟结果；关闭电机后重试恰好消费一次原先力矩。

另外，poststep/alias 两个独立探针覆盖外力矩越过角度分支、后续子步失败回滚先前已积分子步，以及单子步整圈 2π 回到相同 wrapped angle 的混叠。必须检查实际角速度 × dt，不能只比较包裹角差。inactive 空间、重复请求、取消请求也要求真实失败／无执行结果，不产生虚假完成。

脚本覆盖计数为正向 65、负向 18、guard 12、poststep 18、alias 11、range-loading 143、range-negative 15、输入 smoke 14；实测结果以此次 native 对应的 `results.json` 为准。GUI smoke 和输入 smoke 都是 headless；真实桌面须 dot 独立验收。

## dot GUI 操作

```bash
godot --path /tmp/hinge-drive-check/project --script res://gui.gd
```

GUI 复用真实 Node `_input` 派发，不把 SceneTree 上的同名函数冒充按键输入。

1. `M` 开关电机，`V` 反转 ±1.5rad/s 目标；观察实际速度和方向。
2. `L` 开关 ±.6rad 限位；启用后达到边界停止继续转动，反转后离开原边界。
3. `P` 暂停，修改 M/L/V 时姿态不变；`S` 精确 `.01s` 步进，重复 pending 点击不叠加请求。
4. `C` 删除连接，`R` 重置／重加，重复操作；`W` 保存 `SavedHinge.tscn` 后编辑器重开/F6，核对节点参数、限位和电机行为。
5. 检查退出日志无 ERROR／泄漏。异常 guard 属独立负例，不在正常 GUI 日志中放行。

未覆盖：复杂机构或共享端点驱动、大角速度/大步长越界运行、任意求解参数映射、重负载和 GUI 桌面自动化。本套通过不替代其他原生后端回归。

## 同号限位保存重开回归

`range_loading.gd` 覆盖 `[-2.5,-2]`、`[-2,-2]`、`[2,2.5]`、`[2,2]`。未启用驱动时分别采用 upper-first/lower-first；真实 PackedScene 加载、节点换端点、出树重入后，检查节点缓存与 native pair 完整一致，并从配置参考角零实际步进收敛到上下界／等限。没有预设到区间中点来绕过大初始误差。反向驱动分别检验两端边界。

未启用时临时倒置 pair 只可暂存，getter 保持已接受 pair；不完整 pending 到 flag 边界必须拒绝，重复启用也不能绕过，补齐另一端后可恢复。已启用时非法修改立即拒绝，保留范围、flags、非零物理状态、暂停与时间；非有限／越界标量保护不放宽。

旧备份 native SHA256 `c25f92e782aa348fa7aaa92291810230838d3b8311acf3b490fdc2cac51637c9` 的开发探针曾实测失败：负范围被读为 `[-2.5,1.570796]`，正范围 lower-first 被读为 `[-1.570796,2.6]`，真实 PackedScene 负范围亦复现。修复后的开发结果必须与独立 dot 官方 4.7.2.NET 最终验收区分；这些脚本通过不代表已完成 dot 桌面验收。

换端点与出树重入前另外显式开启 native motor+limit，并断言旧状态确实 active；重配后核对 node 缓存 flags 与服务器重新一致。失败候选 make_hinge（有限但不安全的 1e20 锚点）独立验证旧已接受范围、active flag、姿态、速度、暂停及时间不变，并严格隔离其一条预期错误。
