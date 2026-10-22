# 原生刚体 P0：支持与拒绝契约

开发基点 `8d3976e`，固定 Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16。此文描述本功能分支实现；主线和 PR #5 不因本分支开发而自动合入。验收结果见本阶段 evidence，GUI 由 dot 独立验收。

| 能力 | 本阶段行为 | 边界 |
|---|---|---|
| 质量 | 正质量；启用的 box/sphere/cylinder 按体积分配总质量，由 MuJoCo 求复合质心、主惯量；冲量除以总质量 | 无有限体积形状使用既有备用惯量；不支持手动惯量/质心。动态 plane 不支持 |
| 摩擦 | 普通原生物体之间按 `abs(min(a,b))` 合并，负号表示 Godot rough；显式碰撞对保留层/掩码及 exception 过滤 | 原生与 MJCF 模型接触仍采用 MuJoCo 合并规则；不保证两引擎接触求解器数值完全相同。原生显式对数量为二次规模，仅面向当前轻量场景 |
| 重力 | world 重力 × body gravity_scale；负缩放支持。自定义积分关闭自动重力 | 已配置 MJCF world 拒绝默认环境重力覆写；不是 Area 环境覆写 |
| 阻尼 | combine 加默认空间值，replace 仅用 body 值。每个实际积分区间乘 `max(0,1-damping*dt)`，不因 MuJoCo 子步数改变 | authored world 以实际推进时间为 dt；无实际步进不衰减 |
| 力、冲量 | 世界坐标；central/offset/torque 与常量形式。offset 是相对 body 原点的世界方向偏移，扣除自动质心后求力矩；瞬时力在一次实际积分区间后清除，常量力持续 | 暂停不消耗待施加力。冲量立即修改速度；应用力等待下一积分区间。非有限输入或累加溢出拒绝，offset 操作不部分修改 |
| 自定义积分 | omit 模式屏蔽默认重力、阻尼、外力和外力矩；接触约束仍由 MuJoCo 求解。冲量/直接设置速度仍有效 | direct_state.integrate_forces 显式按 Godot 基类算法积分重力/阻尼，不自动积分外力；重复调用就是重复积分 |
| 状态回调 | 实际积分后在 flush 阶段触发，传入实际积分区间 step。暂停且没有实际步进不触发积分回调；暂停 reset 仅安排状态同步 | 多个 MuJoCo 子步在一个 server tick 内只产生一组回调；不是每个内部子步一个 Godot 回调 |
| 生命周期 | 回调前检查 RID/space，回调中释放延迟到 flush 后；换 space 清除旧回调标记；重建读取兼容状态 | 本阶段不含新的 Area、关节或 CharacterBody 生命周期 |
| 明确拒绝 | 非有限数值、非正质量、负阻尼、非法阻尼模式、非零 bounce、手动惯量/质心；参数拒绝后不回报未实现的新值 | sleep、CCD、axis lock、kinematic 等保持现有拒绝契约，后续任务另行实现 |

Godot 原生参考：[刚体默认力积分和质量分配](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/godot_physics_3d/godot_body_3d.cpp)、[摩擦合并](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/godot_physics_3d/godot_body_pair_3d.cpp)、[direct_state.integrate_forces](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/physics_3d/physics_server_3d.cpp)。默认自动积分先衰减已有速度再施加力；显式 direct-state 辅助方法依 Godot 基类先加重力再衰减，二者顺序刻意保留。

本阶段不宣称接触报告、overlap/sweep、Capsule/CharacterBody、Area 或普通 Joint3D 已完成。冷导入 139 未根治；不运行 G1/多 G1 重负载、不修引擎、不打包或验证 Windows。
