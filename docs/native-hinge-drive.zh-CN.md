# 原生 Hinge 限位与速度电机（有界阶段）

开发基点 `4c2f1f7` 已由 dot 独立验收；本功能在独立分支 `codex/hinge-limits-motor`，不覆盖该候选、不合 main。Linux x86_64 / 官方 Godot 4.7.2 .NET / MuJoCo 3.16.0。

## 支持与拒绝

使用普通 `HingeJoint3D` 或 PhysicsServer3D Hinge 参数。继承被动 Hinge 的两组软 connect、free body、锚点、碰撞排除和生命周期。新增真实速度电机与角度限位，不改变为 MuJoCo 树式关节。

- 主动模式仅支持独立 Hinge：一端 Rigid，另一端 world、Static 或另一个 Rigid。任一动态端若另连 Pin/Hinge，拒绝启用；主动连接存在后，再添加共享动态端的连接也拒绝。多个互不共享动态端的驱动可共处一个 space；共享 world/Static 允许。
- frame 的 Z 为轴、X 为角参考；平行 frame 的角度为 A 相对 B 沿 A 轴的旋转，单位 rad，包含 frame 本身的相位。主动模式拒绝初始反平行轴，避免 full-frame 零位不兼容；被动模式仍支持其原边界。simple 内部接口在创建时选择零位，固定 Godot 不向 GDScript 绑定该接口，不声称其独立 GUI 覆盖。
- `LIMIT_LOWER/UPPER` 有限、`-3 <= lower <= upper <= 3`，等值可锁角；不支持跨 ±π 的区间或多圈累计限位。
- `MOTOR_TARGET_VELOCITY` 有限且在 ±100 rad/s；`MOTOR_MAX_IMPULSE` 在 0..1000 N·m·s。实际速度与时间步还必须满足下述数值边界。0 预算不驱动，但限位仍可产生反力。
- 最大电机冲量预算属于一次实际 server 积分区间。按 MuJoCo 子步的 `dt/span` 分摊；请求一次 10 子步步进不会获得 10 倍预算。这不是力矩参数，也不承诺匹配 GodotPhysics 的迭代细节。无独立恒力矩电机模式；普通刚体 torque API 仍可施加载荷。
- bias、limit bias/softness/relaxation 仅接受既有默认初始化值，不宣称可调映射；自定义值明确拒绝。非有限、超范围立即报错并保留旧参数。已启用 motor 或 limit 时，倒置区间也立即拒绝；两者都关闭时，为兼容 Godot upper-first 参数重放，单边导致的临时倒置先暂存，getter 仍返回已接受范围。补齐另一边得到合法 pair 后一次提交。若任何 flag 更新时仍未补齐，报错并保留 pending 与旧 pair/flags，重复 enable 不能绕过；修正为有效 pair 或清除/重新创建连接才解除。节点 Inspector 可能缓存拒绝值，须检查错误和服务器状态。

## 物理实现

每个子步从当前位姿取两端真实世界锚点的线 Jacobian 和角 Jacobian。三个相对锚速度方向加两个横向角速度方向组成五个独立被动约束。通过 `mj_solveM` 和 5×5 Schur 投影计算允许转轴方向的冲量响应，而非直接使用未约束的 COM 逆惯量；因此偏心锚点的平行轴惯量进入响应，双动态端得到反作用。

电机先按预算朝目标相对角速度施加冲量；限位再限制下一子步允许的角速度，已越界时使用 .3 误差修正，并将纠偏速度限制为每子步最多 .2 rad，允许远离零位的合法同号区间逐步收敛；原 .25 rad 数值拒绝阈值未放宽。只改广义速度，不钳制姿态、不瞬移。MuJoCo 继续处理原来的软 connect、重力、外力及接触；这不是硬约束或完整 Godot 求解器等价实现。载荷下有有限误差，实际验收数值和容差以测试记录为准。

数值边界：MuJoCo 子步 `dt <= .02s`，冲量前后轴向角速度对应的子步转角不超过 .25 rad；检查质量投影正定性、残差及有限状态。子步后再次检查真实转角，限位启用时拒绝跨 atan2 分支；拒绝新增 MuJoCo warning 或非有限状态。无法认证时暂停整个 space 并给出明确错误，不让跨界被误判为另一侧限位。

## 安全更新、重置与完成反馈

参数/flag 在主线程设置；物理回调内沿现有 FIFO 延迟，出队重新校验。创建/重配继续使用隔离模型编译和状态迁移，失败保留原定义。成功 `joint_make_hinge` 建立新的 Hinge 类型配置：上下限、速度和预算恢复默认，motor/limit 关闭，旧 pending 清除；Godot 随后按 upper/lower→flags 重放节点设计。低层调用者重配后也须显式重设驱动参数，不能依赖旧类型状态残留。clear、端点 detach、切换到 Pin 同样清 pending。普通参数更新不重建模型，暂停时也可修改设计。

有主动 Hinge 的积分区间保存数据与回调元信息；任一子步拒绝时回滚**整个区间**的 qpos/qvel/time、阻尼和力作用，保留尚未消费的一次力，不发送虚构成功积分回调，并暂停。world step 完成结果在实际执行后产生，失败包含真实时间；排队接受不等于成功。inactive physics/space 的 step 明确拒绝，不留下可被覆盖的待执行请求。未做分配失败强制注入。

checkpoint/reset 恢复仿真状态，不撤销当前 Hinge 设计参数。清除/释放/端点删除或模式、space 改变沿既有规则移除连接。场景保存重开通过 HingeJoint3D 保存设计；不把仿真快照写为设计。

## 验收与后续边界

入口：[tests/native_hinge_drive/README.zh-CN.md](../tests/native_hinge_drive/README.zh-CN.md)。最终运行证据另列；headless 输入 smoke 不等于 dot 桌面验收。

仍未完成：关节链中的主动约束、任意闭环、多圈限位、可调求解响应、完整 Hinge 跨求解器等价、Slider/ConeTwist/6DOF。复杂接触负载、大质量比和长时强载不因轻量测试通过而视作覆盖。无 G1 重负载、Windows、打包或引擎冷导入修复。

官方参考：[Godot 4.7.2 Hinge 源码](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/godot_physics_3d/joints/godot_hinge_joint_3d.cpp)、[MuJoCo 3.16 API](https://github.com/google-deepmind/mujoco/blob/3.16.0/include/mujoco/mujoco.h)。它们用于核对接口与单位，不代表本实现数值等价。

## 参数加载顺序修复

`7c6d87c` 在合法负区间保存重开时曾将 upper 错留为默认值，此候选不能按最终验收通过处理。新增回归覆盖 `[-2.5,-2]`、`[-2,-2]`、`[2,2.5]`、`[2,2]`，检查节点缓存/native一致性及实际限位运动。
云端 coding 环境运行仅为开发自测；所有最终代码与 GUI 验收在实际 dot 云电脑、官方 Godot 4.7.2 .NET 上执行。依赖/构建入口不变。
