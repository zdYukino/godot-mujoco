# 原生 PhysicsServer 后端推进计划与阶段状态

开发基点：已验收的 `8d3976e`（PR #5，未合 main）。用户已授权按优先级开发原生后端；集成分支为 `codex/native-backend-integration`。P0 先收口现有刚体语义，接触报告与查询由独立任务开发，必须逐个集成和验证；以下后续能力不能因已授权而记为完成。

以下区分普通Godot节点能力与MJCF模型能力；未运行的能力不因MuJoCo底层支持而视作Godot支持。HTML由父任务维护。

| 分类 | 已有能力 | 主要缺口与代码依据 |
|---|---|---|
| Body/形状 | StaticBody3D、RigidBody3D；box/sphere/plane/cylinder；刚性姿态、尺寸、质量推导、层/掩码、exception | mj_physics_server.cpp只接受STATIC/RIGID；scale/shear/镜像拒绝；capsule、convex、concave、通用HeightMapShape3D在mj_unsupported.cpp仍stub |
| 地形 | 专用MjStaticHeightField固定网格，安全增删替换，视觉/碰撞/ray | 不等于Godot HeightMapShape3D，不含动态雕刻或大地图 |
| 查询 | ray、有限已支持几何、collider/RID/shape身份、mask/exclude/inside；专用地形backface处理 | mj_direct_space_state.cpp的point/shape overlap、cast_motion、collide_shape、rest_info、closest point未实现；mesh模型存在不代表ray支持其mesh |
| CharacterBody/运动学 | 暂无普通CharacterBody3D行为保证 | _body_test_motion stub；KINEMATIC模式拒绝。缺连续运动查询、初始穿透恢复、safe/unsafe fraction、接触法线/多命中；不能仅打开mode枚举便宣称move_and_slide支持 |
| Area | space默认环境重力/阻尼的有限处理 | _area_create及监测回调/形状/层/变换等stub；默认space参数不等于Area3D重叠与环境覆写 |
| 原生关节 | MJCF实例自身关节由MuJoCo模拟 | 普通Godot Pin/Hinge/Slider/ConeTwist/Generic6DOF Joint3D均stub；不能将MJCF关节编辑算作Godot Joint3D支持 |
| 接触/高级刚体 | MuJoCo空间contact信息；基础力、冲量/速度与状态同步 | direct body _get_contact_count返回0，Godot contact reporting未实现；sleep、CCD、axis lock、自定义惯量/质心等仍不支持 |
| 生命周期 | RID管理、free延迟、实例身份/revision、队列、兼容迁移回滚；本轮整份预设边界事务 | 每新增对象类型必须接入同一free/rebuild/rollback协议；不能依赖原shape/body生命周期测试覆盖Area/joint的新依赖图 |

后续里程碑（依赖阶段通过后推进，未实现项保持未完成）：

0. **P0 现有刚体语义**：见 [支持与拒绝契约](native-body-semantics.zh-CN.md)。以数值测试验证质量、摩擦、重力缩放、阻尼、力/冲量、自定义积分与暂停/重置回调；不能以 setter/getter 存值代替动力学效果。
1. **查询基础与接触身份**：先为现有形状补point/shape overlap、collide/rest info与稳定结果排序/身份。验证层/掩码、exclude、多个shape索引、移除后RID失效、边界点/退化输入、重建前后身份；不宣称连续运动。
2. **CapsuleShape3D**：明确Godot完整高度与MuJoCo半段长度转换，退化球规则/尺寸限制、质量惯量、ray/overlap联动。依赖查询基础以覆盖角色常用形状；形状可单独交付，不能冒充CharacterBody完成。
3. **运动查询**：实现cast_motion和body_test_motion，明确扫掠算法、初始穿透恢复、margin、safe/unsafe fraction、多个碰撞结果。验证薄墙/高速、角落、滑坡、开始重叠、移动障碍和回归可重复性。依赖1（角色capsule路径还依赖2）。这是CharacterBody的前置门槛。
4. **运动学及CharacterBody**：接入KINEMATIC同步与Godot move_and_collide/move_and_slide契约；验证地面/墙/天花板、坡度、floor snap、平台速度、连续帧行为与动态刚体交互。依赖3；仅通过ray或静态落体测试不足以验收。
5. **Area3D监测**：依赖overlap与生命周期基础；增加独立Area RID/形状、monitorable/mask、enter/exit事件缓存与安全回调。验证删除/换space/关闭monitor后事件平衡、回调中删除、shape identity、多个Area重叠。重力/阻尼priority覆盖作为后续独立子阶段，不能与基础监测捆绑承诺。
6. **普通Joint3D**：先Pin与Hinge最小功能，再依据需求Slider/其他。明确约束frame、世界锚点、collision exclusion、limit/motor单位与支持参数；验证两动态体/静态体/世界锚点、删除重建、状态连续性、非法参数与回滚。依赖body生命周期/接触身份，不必等待CharacterBody；禁止默默忽略Godot参数。
7. **高级刚体与优化**：contact reporting、CCD、sleep等分开需求和验收。CCD依赖运动查询；sleep牵涉激活岛/唤醒，不能只是停止step；性能指标必须固定场景、同工具链、明确负载授权。

每阶段门槛：先写支持矩阵/拒绝契约；源码构建；轻量正负例日志隔离（任何非预期ERROR/leak失败）；跨节点删除/重加/多space/回调生命周期；dot真实GUI与固定提交独立验收；再由用户决定合入。平台固定Linux4.7.2.NET/MJ3.16；不引入Windows、打包、重G1、引擎级冷139修复。
