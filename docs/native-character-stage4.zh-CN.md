# 原生 CharacterBody 最小工作流（阶段 4）

基于 Capsule `db40796` 和普通旋转 sweep float 修复 `c64164c` 的独立后续提交。
不改上述交付提交，不合 main。固定 Linux Godot 4.7.2.NET / MuJoCo 3.16。

## 支持范围

实现 `_body_test_motion`，运动主体是原生 sphere/capsule，可有多个局部旋转/偏置 shape。
目标沿用原生 sphere、box、cylinder、capsule、plane；只平移，目标冻结在查询时姿态。
共享空间查询的原生 RID/Object/shape 所有权映射；排除自身、双向 body exception、
Godot motion 的 exclude_bodies/exclude_objects；按 mover mask 对 target layer 过滤。
禁用、脱离空间、释放的 shape/body 不参与。失败重建不会拿旧几何冒充成功。

先对初始穿透及 margin 做恢复，再做真实连续 sweep。每轮恢复同时求解当前接触的
法向半空间约束，最多 16 轮、每轮 32 次约束投影；不可行或数值不收敛明确拒绝。
恢复 slop 固定为 1e-6，每个约束按实际 body/local 舍入后的 shape 位移验证法线投影；
无关大坐标不会放大 slop，不能表示的恢复明确拒绝。
不会依靠逐个推出后反复换边，把夹困主体挪穿墙。恢复后的初始距离另行校验，
不得继承公共 cast_motion 的“忽略初始重叠”策略。零运动也可返回恢复 travel；
recovery_as_collision 控制恢复接触是否算碰撞。travel 包含恢复，remainder 只扣运动进展。

返回实际 target 表面点、外法线、碰撞深度、RID/Object、本地/目标 shape index、
目标角速度与 COM 点速度 `v + ω × (point - COM)`。按深度降序、RID、目标 shape、
本地 shape 排序，max_collisions 为 1..32。最早碰撞决定连续 safe/unsafe fraction。
返回前按 Godot 的 body 原点加 travel 再应用局部 shape 的实际 float 运算次序重扫，
防止巨大相反局部偏置造成穿薄墙。已有碰撞可保守回退可表示 travel；若舍入路径
引入理想路径没有的碰撞，实际端点有可靠 witness 时保留该碰撞并回退 safe；
否则明确拒绝，不能无碰撞地悄悄截断运动。
最终 unsafe 也必须按同一 BODY 运算顺序取得真实目标 witness；相邻 fraction 或已认证的
终点可用于细化，无法认证则拒绝，不用理想 shape 路径的 contact 填充结果。

失败返回 false、collision_count=0、travel=0、remainder=motion、fractions=0 并报告警告；
不能把这种拒绝当作无障碍成功，也不伪造零法线碰撞。普通 clear 返回 false 和完整请求
travel（Godot 对 body 原点应用该向量时仍有 float 舍入，实际路径已认证）。

## Float 认证与连续性

公共 cast_motion 沿用解析/凸距离单调导数求根的连续检测，不采样发现碰撞。
先尝试相邻 float fraction；近 t=0 时 fraction ULP 远小于世界位置 ULP，改用连续求解器
已经算出的凸距离极小点作为候选 unsafe，t=0 作为候选 safe。两端必须分别满足
连续 double 位姿与实际 Godot float 位姿的严格 gap 符号，然后才二分细化。
不引入距离容差，也不把认证失败当成空路。不能表示的擦边/极薄接触仍拒绝。
大坐标可得到较宽区间，例如原先拒绝的 sphere 案例现在返回约 [0.4,0.6]，
测试独立验证两个端点的连续及 float 几何，不再要求它无条件拒绝。

## Kinematic 与共享接口

新增 BODY_MODE_KINEMATIC 的 MuJoCo mocap body 编译、位置更新及重建迁移。
控制预设验证事务在 mj_forward 前用最新原生 transform 覆盖旧 mocap 迁移值，
并检查 mocap 数组有限性。world checkpoint/reset仅恢复仿真关节/控制状态，外部控制的kinematic/mocap姿态保留当前值；reset候选在forward前复制当前mocap数组，确保Godot缓存、ray与body motion一致。查询不推进仿真、不改主体真实姿态或空间活动状态。

本阶段 kinematic 是**单向查询障碍**：contype/conaffinity=0，显式 solver pair 也跳过
kinematic，因此 Character 查询可被动态刚体挡住，但移动 Character 不向动态刚体施加
求解器冲量。不会根据 transform 差值推断平台速度；显式设置的速度用于查询结果。
接口变化仅在 query/server 实现及内部 sweep Result.minimum；无新增公开 GDExtension API。

## 已测工作流与限制

真实 CharacterBody3D + CapsuleShape3D：test_only、move_and_collide、move_and_slide，
多帧落地、沿墙滑动、floor snap、天花板、20 度可行走斜坡、动态目标阻挡和移除。
这不是完整 CharacterBody 兼容承诺：未支持楼梯、完整移动平台、separation ray、
rigid-linear、旋转 sweep、动态 CCD、moving box/cylinder；专用 heightfield 与导入 MJCF
几何也不在 body-motion 支持集，未伪装统一覆盖。数值极端输入可保守拒绝。
不声称支持 kinematic 与 dynamic 的双向推挤或动态角色控制。

验收和真实失败记录见 `evidence/native-character-stage4/README.md`。

阶段 4 复审三项修复及独立数值复现见 `evidence/native-character-review-fixes/README.md`，
它补充并修正原阶段证据（原 wall=6 只认证 safe 的契约不充分，现改为严格拒绝）。
