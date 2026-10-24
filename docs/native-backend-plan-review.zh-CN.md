# 原生 PhysicsServer 后端推进计划与阶段状态

当前后端候选 `4c2f1f7` 已通过 dot 独立源码构建、21 套轻量回归及 GUI 验收，仍在 draft PR #8，未合 main。2026-10-24 后续功能分支 `codex/hinge-limits-motor` 仅推进有界 Hinge 限位/速度电机及直接依赖，不自动扩展全部后端。新阶段仍需其独立验收；HTML 由父任务更新。

以下区分普通Godot节点能力与MJCF模型能力；未运行的能力不因MuJoCo底层支持而视作Godot支持。HTML由父任务维护。

| 分类 | 已有能力 | 主要缺口与代码依据 |
|---|---|---|
| Body/形状 | Static/Rigid，box/sphere/plane/cylinder/capsule；质量、力/冲量、摩擦、重力/阻尼与 COM 数值语义 | scale/shear/镜像拒绝；convex/concave、通用HeightMap、rigid-linear未支持 |
| 地形 | 专用MjStaticHeightField固定网格、安全替换、视觉/碰撞/ray | 不等于HeightMapShape3D；无动态雕刻/大地图 |
| 查询 | 原生primitive point/shape overlap、collide/rest、受限连续translation sweep；ray身份过滤 | overlap/sweep不覆盖heightfield/MJCF；无法认证float端点明确拒绝；无旋转sweep/CCD |
| CharacterBody/运动学 | sphere/capsule最小body-motion恢复/连续运动；move_and_collide/slide、floor snap；kinematic mocap与reset一致 | 单向查询障碍，不推动态体；非完整平台/楼梯；无heightfield/MJCF motion或moving box/cylinder |
| Area | 原生形状无冲量监测，enter/exit、FIFO生命周期；priority重力/阻尼覆写 | 无复杂shape/MJCF监测、Area空间查询或CCD |
| 原生关节 | 已验收Pin/passive Hinge：freebody、forest、碰撞排除、world/static/两rigid；本分支新增独立Hinge限位/速度电机，见[边界](native-hinge-drive.zh-CN.md) | 主动关节链、闭环、多圈、反平行主动frame、自定义求解响应未支持；Slider/ConeTwist/6DOF未实现 |
| 接触/高级刚体 | 最后实际子步的接触/冲量、direct-state/contact_monitor；P0数值语义 | 非整帧累计；导入geom无原生Body身份；sleep/CCD/axis lock等未支持 |
| 生命周期 | RID/延迟free/FIFO、候选迁移回滚、实例revision；新Hinge失败步整区间回滚及实际完成反馈 | 新阶段的独立dot验收待完成；分配失败未强制注入，重负载未覆盖 |

原优先级路线（0–5 的有界实现已进入上述已验收候选；下列条目是验证目标，不表示所有细节均完成。当前仅推进 6 的独立 Hinge 主动阶段，其余缺口待选择）：

0. **P0 现有刚体语义**：见 [支持与拒绝契约](native-body-semantics.zh-CN.md)。以数值测试验证质量、摩擦、重力缩放、阻尼、力/冲量、自定义积分与暂停/重置回调；不能以 setter/getter 存值代替动力学效果。
1. **查询基础与接触身份**：先为现有形状补point/shape overlap、collide/rest info与稳定结果排序/身份。验证层/掩码、exclude、多个shape索引、移除后RID失效、边界点/退化输入、重建前后身份；不宣称连续运动。
2. **CapsuleShape3D**：明确Godot完整高度与MuJoCo半段长度转换，退化球规则/尺寸限制、质量惯量、ray/overlap联动。依赖查询基础以覆盖角色常用形状；形状可单独交付，不能冒充CharacterBody完成。
3. **运动查询**：实现cast_motion和body_test_motion，明确扫掠算法、初始穿透恢复、margin、safe/unsafe fraction、多个碰撞结果。验证薄墙/高速、角落、滑坡、开始重叠、移动障碍和回归可重复性。依赖1（角色capsule路径还依赖2）。这是CharacterBody的前置门槛。
4. **运动学及CharacterBody**：接入KINEMATIC同步与Godot move_and_collide/move_and_slide契约；验证地面/墙/天花板、坡度、floor snap、平台速度、连续帧行为与动态刚体交互。依赖3；仅通过ray或静态落体测试不足以验收。
5. **Area3D监测**：依赖overlap与生命周期基础；增加独立Area RID/形状、monitorable/mask、enter/exit事件缓存与安全回调。验证删除/换space/关闭monitor后事件平衡、回调中删除、shape identity、多个Area重叠。重力/阻尼priority覆盖作为后续独立子阶段，不能与基础监测捆绑承诺。
6. **普通Joint3D**：先Pin与Hinge最小功能，再依据需求Slider/其他。明确约束frame、世界锚点、collision exclusion、limit/motor单位与支持参数；验证两动态体/静态体/世界锚点、删除重建、状态连续性、非法参数与回滚。依赖body生命周期/接触身份，不必等待CharacterBody；禁止默默忽略Godot参数。
7. **高级刚体与优化**：接触报告已进入集成阶段（见 tests/native_contacts/README.zh-CN.md）；CCD、sleep等另行需求和验收。CCD依赖运动查询；sleep牵涉激活岛/唤醒，不能只是停止step；性能指标必须固定场景、同工具链、明确负载授权。

每阶段门槛：先写支持矩阵/拒绝契约；源码构建；轻量正负例日志隔离（任何非预期ERROR/leak失败）；跨节点删除/重加/多space/回调生命周期；dot真实GUI与固定提交独立验收；再由用户决定合入。平台固定Linux4.7.2.NET/MJ3.16；不引入Windows、打包、重G1、引擎级冷139修复。
