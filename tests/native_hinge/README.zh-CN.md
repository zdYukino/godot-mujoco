# 原生被动 Hinge 轻量验收（部分支持）

本阶段只覆盖被动单轴自由度，不代表完整 Godot Hinge。Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16 固定；不使用 G1。

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=/tmp/passive-hinge-check bash tests/native_hinge/run.sh
```

OUT 必须新建。runner 复用已验收 Pin 的 `acceptance.gd` 公共测试辅助函数，将它复制为临时项目内 `pin_support.gd`；不修改 Pin 文件。每个阶段记录真实退出码，保存扩展 SHA256，隔离正常和预期错误日志。正向／导入／GUI smoke 出现 ERROR 或泄漏失败；负向只允许逐条声明的 10 条错误，额外 ERROR、SCRIPT ERROR 和泄漏失败。冷导入失败后不会运行或声称后续通过。

44 条正向与 13 条负向断言覆盖：

- 世界端 Hinge：沿 basis Z 的角运动保留，X/Y 横向角运动衰减；锚点和轴方向保持约束。轴向转动同时检查角速度与实际姿态变化。
- 非坐标轴方向、两端初始反平行轴；局部 frame 锚点偏移；双动态刚体锚点重合、轴对齐且具有相对轴向旋转。双体测试施加独立轴向力矩，避免对称平动只能激发共同旋转。
- 无关属性重建保留姿态和线／角速度，暂停保持状态；clear 释放平移、RID 重新配置、端点删除清空连接。
- 真实 `HingeJoint3D` 节点 PackedScene 保存／重开，node path 恢复并创建实际 Hinge，重新步进后摆动且锚点与轴保持约束。
- 4 项非默认求解响应参数明确拒绝、不假存值。主动限位/电机另由 `tests/native_hinge_drive` 验证。
- 零轴／非有限／缩放 frame、初始斜交轴、辅助锚点无法用 float 表示的输入拒绝；有限 `1e20` 候选动力学失败保留旧连接、姿态、速度、暂停和时间，并在随后真实步进中验证旧约束仍有效。

框架采用两个 soft connect，辅助点间距固定 1 m。测试容差为锚点 3 cm、轴点积 > .999，不能解释成精确硬约束或 Godot 求解器参数等价。`.3, π/2, -π/2, .3, .9, 1, 1, 1` 仅是节点初始化兼容默认值，本套主要验证被动响应；主动限位/电机的有界能力见新增 drive 套件，仍不映射自定义求解响应。

公开 Godot 脚本接口使用 `PhysicsServer3D.joint_make_hinge` 的 frame 形式。固定版本没有向 GDScript 绑定 `joint_make_hinge_simple`；本测试没有通过动态调用伪装其可用性，不声明 simple 虚函数的独立覆盖。

## dot GUI 步骤（headless smoke 不代表已执行）

```bash
godot --path /tmp/passive-hinge-check/project --script res://gui.gd
```

1. 观察方块绕世界 Z 轴摆动，固定标记处锚点误差保持小量，横向旋转受抑制。
2. `P` 暂停／恢复，`S` 暂停时精确 `.01 s` 步进；`C` 删除关节后自由运动，`R` 重置并重加；重复操作后检查日志。
3. `W` 保存 `SavedHinge.tscn`，在编辑器打开，检查 WorldHinge→Bob 路径和 frame；F6 观察重开后的实际约束。
4. 使用新 `native_hinge_drive` GUI 验证主动限位/电机；本套负例检查不支持的求解响应和非法 frame。

尚未独立覆盖：真实桌面 GUI、成功跨空间改绑、完整 Hinge callback 销毁组合、静态端 Hinge 专门数值用例、强制编译／分配失败。共享生命周期与碰撞机制另有 Pin 回归，但不能替代上述 Hinge 专项覆盖。上游查询阶段的独立问题不由本套局部通过结果证明已解决。
