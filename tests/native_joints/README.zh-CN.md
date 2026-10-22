# 原生 PinJoint3D 轻量验收

仅 Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16。当前阶段只验收 Pin；不以此声明 Hinge、闭环机构或完整 Godot 参数等价。

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=/tmp/native-pin-check bash tests/native_joints/run.sh
```

使用尚未包含 `project/` 的新 OUT。runner 将当前源码构建的扩展复制到独立项目，分别归档 import、positive、negative、gui-smoke 日志，`executions.tsv` 记录真实退出码，`results.json` 记录逐项断言及扩展 SHA256。任一命令非零退出立即失败；正向日志出现 ERROR／泄漏失败；负向只允许逐条声明的 11 条拒绝错误，不放行额外 ERROR、SCRIPT ERROR 或泄漏。冷导入失败不能将未运行阶段标通过。

当前测试包含 49 条正向、21 条负向断言：

- world / static / dynamic 双端点局部锚点与真实数值约束；摆动可旋转而非焊死。锚点误差阈值 3 cm，以兼容明确的 MuJoCo soft connect 响应，不宣称硬约束零误差。
- 暂停与精确 `.01 s` 步进；无关属性重建保留 pose/velocity；修改锚点和移动静态端点后约束持续有效。
- pair collision-disable 关闭/恢复实际接触，报告在 sync callback 内读取，避免暂停下一帧清空快照造成错误结论。
- clear、重配、删除端点、移除/重加空间后的约束释放和重新约束；回调 make→mode-change 与 mode-change→make 的 FIFO 语义。
- 真实 `PinJoint3D` 节点 PackedScene 保存、加载、重新实例化；路径与局部锚点恢复，重新运行后仍约束并允许摆动。
- 不支持参数和 priority 不假存；NaN、自连接、跨空间端点、重复边及闭环拒绝，旧 Pin 仍实际约束。有限但不安全的 `1e20` 锚点触发候选动力学拒绝，旧定义、pose、velocity、暂停状态和时间全部保持。

兼容参数 getter 的 `.3 / 1 / 0` 仅为允许的 Godot 默认配置。实际求解为 native 文档所述固定 MuJoCo soft-connect 响应，不把这些值解释为已映射的 Godot bias/damping/clamp。负例中的有限候选失败与 NaN 前置校验是不同路径；未注入分配失败或编译器强制失败。

## dot 真实 GUI 验收步骤（本目录 headless smoke 不替代此项）

```bash
godot --path /tmp/native-pin-check/project --script res://gui.gd
```

1. 方块围绕固定标记自由摆动，锚点误差保持小量，旋转不是锁死。记录画面与日志。
2. `P` 暂停后等待，姿态不变化；`S` 每次仅执行 `.01 s`。恢复运行后继续摆动。
3. `C` 删除关节，方块自由下落；`R` 重置并重加关节，恢复悬摆。重复操作，检查日志无 ERROR／泄漏。
4. `W` 保存 `SavedPin.tscn`，在编辑器打开，核对 `WorldPin.node_a` 指向 `Bob`、节点位置与形状；F6 运行观察约束。保存的是当前设计节点状态，不保存求解器内部历史。

未覆盖：成功跨空间改绑同一已配置 joint RID 的数值行为、全部回调销毁组合、强制分配失败、重负载和真实桌面操作。Hinge、Pin 非默认调参及闭环不属于本 Pin 阶段通过声明。
