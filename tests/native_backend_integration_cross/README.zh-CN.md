# Capsule × Area 环境 × 被动 Hinge 组合补充

这是集成层组合验证，不重复各功能单测，也不声明完整原生后端通过。固定 Linux x86_64、Godot 4.7.2 .NET、MuJoCo 3.16。

```bash
source /workspace/shared/tools/env.sh
# 使用本次集成源码重新构建的 addon。
OUT=/tmp/backend-cross-check bash tests/native_backend_integration_cross/run.sh
```

入口复制当前 addon 到新项目，复用 Pin 已有的空间／步进辅助脚本，不执行 Pin 原测试。import 和 supplemental 真实退出码保存在 `executions.tsv`，逐条断言及扩展 SHA256 在 `results.json`。任意非零退出、ERROR、泄漏、warning 或 NaN/Inf 报警均失败。

22 条断言覆盖：

- Area 自身使用 Capsule，动态体也使用 Capsule。重力覆盖为 `(6,0,0)`，Area 线／角阻尼为 `2 / 3`，body 阻尼为 `.5 / .25`。`.01 s` 后初始线速度 `2` 变为 `2.01`，初始角速度 `4` 变为 `3.87`，验证实际数值效果。
- 相同场内 Capsule body 的被动 Hinge 承受横向场力，锚点误差低于 `.03 m`，且确实产生自由轴摆动；场作用没有被关节关闭。
- clear、重加、free joint RID 后，分别检查约束恢复或解除；自由阶段 `.1 s` 后速度符合 `v_new = .75*v_old + (0.6,0,0)`。
- 删除 Capsule Area 后，胶囊体恢复世界重力和默认阻尼；所有状态有限。

这些是 headless 实际物理测试。尚未执行该组合的独立桌面 GUI；未覆盖完整 Hinge limits/motor、闭环、复杂形状或重负载。其他查询／CharacterBody 等套件结果由主集成任务分别报告，不能由本套通过推断。
