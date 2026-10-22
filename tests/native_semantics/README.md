# 原生刚体数值语义回归（P0）

固定 Linux x86_64、Godot 4.7.2 .NET、MuJoCo 3.16。先从当前源码构建扩展；本入口复制生成的 native 库到独立临时项目，记录库 SHA256，不使用 G1。

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=/tmp/native-semantics-unique tests/native_semantics/run.sh
```

`OUT` 必须是未包含 `project/` 的新目录。`import.log`、`positive.log`、`negative.log` 分离；`executions.tsv` 记录每个实际执行命令的退出码，任一非零退出立即停止，未运行阶段不得视为通过。正向日志出现 ERROR 或泄漏即失败；负向仅允许 21 条与测试明确声明对应的参数拒绝错误，SCRIPT ERROR、额外错误、泄漏均失败。`results.json` 包含每项断言、Godot 版本和扩展 SHA256。冷导入 139 仍是独立初始化限制；导入失败后本入口不运行后续 smoke、不重试伪称 fresh pass。

## 数值与生命周期覆盖

- 单独暂停空间，以 `.01 s` 精确步进验证质量变化后的冲量、三轴一次性力与常量力、重力系数（包括负值）、力矩与自动惯量；暂停时待施加的力保留，步进后一次性力清除。
- 普通 Godot 空间的阻尼以实际 Godot tick 为单位，内部 MuJoCo 子步不能重复衰减；同时测试 REPLACE 和 COMBINE。精确多步命令按实际总时长衰减。
- 自定义积分关闭自动重力、阻尼、瞬时/常量力与力矩；显式 `PhysicsDirectBodyState3D.integrate_forces()` 按重力后阻尼更新速度。重新开启不重放已消费的一次性力。
- 非对称旋转盒、偏移 COM、世界坐标偏心冲量；复合盒按体积加权质量得到 COM，而非每个形状均分质量；物理参数重建保留线/角速度。
- 暂停不重复调用力积分或状态回调；单步回调只调用一次并报告真实时长；暂停恢复 checkpoint 只同步状态；回调内释放、移除再加入无旧回调串扰。
- 四组真实滑动接触比较普通摩擦最小值与双方 rough 符号规则。仅覆盖原生 body 对原生 body；不扩展到 MJCF 混合摩擦承诺。
- 非法质量/重力/摩擦/阻尼/模式/速度拒绝，默认空间重力的非有限值与派生溢出、有限 double 超出 float 范围、线性/角阻尼的组合溢出（参数、模式切换、换空间）同样拒绝；不支持的自定义惯量、COM 和反弹不假存值；非法偏心冲量/力/常量力不得部分修改线性或角状态。

命令完成结果在物理边界产生，回调在之后的 `flush_queries` 送达。测试明确等待后者，避免把“请求已完成”当成“回调已送达”。所有等待有外部 120 秒限时，命令结果最多等待 30 帧。

## dot 编辑器 GUI 复验步骤（尚需独立执行）

1. 使用同一提交重新构建的扩展与固定 Godot 打开普通刚体可视项目（`tests/native_backend/run.sh` 生成的项目内 `VisualDemo.tscn`）；在 Inspector 对两个相同盒设置质量 1/2，运行后对相同方向施加同量冲量，确认速度比 2:1；保存并重开核对配置。
2. 复制地板/盒四组，分别设置摩擦 `.1/.8`、`.7/.8`、盒 rough `.7`/地板 `.1`、盒 `.1`/地板 rough `.8`；同初始横向速度运行，低摩擦组保留明显滑动，高/rough 组明显制动。数值结论以本 headless 回归为准。
3. 在运行世界暂停后设置力、改变质量或摩擦；等待数秒确认不自行移动，单步后确认施力生效；再暂停、checkpoint/step/reset，确认可视位置与脚本状态一致。此步骤使用已有运行时控制接口，不能用编辑器暂停按钮替代世界暂停语义。
4. 在自定义 `_integrate_forces` 中显示 `state.step` 与回调次数；暂停不递增，精确步进后递增一次，显式 `integrate_forces` 与自动模式分别核对。删除/重加盒，确认无旧实例回调、ERROR 或泄漏。

这些 GUI 步骤不是本 headless 入口的通过声明。接触报告、运动 sweep、CharacterBody、Area 与关节另由后续阶段验证；这里不把 stub getter 视为功能实现。
