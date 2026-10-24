# Hinge 限位/速度电机验证（2026-10-24）

基于已独立验收 `4c2f1f728416f03922c2bc7d84babd1b0bed94a4`；功能分支 `codex/hinge-limits-motor`，不修改基线或 main。当前支持边界见 [功能契约](../../native-hinge-drive.zh-CN.md)，GUI 步骤见 [测试说明](../../../tests/native_hinge_drive/README.zh-CN.md)。

## 最终结果

固定官方 Godot 4.7.2.stable.mono.official.ed1daf0bf / MuJoCo 3.16.0 / Linux x86_64，最终源码 build6 退出 0。
最终 native SHA256：`c25f92e782aa348fa7aaa92291810230838d3b8311acf3b490fdc2cac51637c9`。

新套件八阶段全退出 0：65 正向、18 参数负向、12 pre-step guard、18 post-step/lifecycle、11 整圈 alias、14 Viewport→Node 输入 smoke。负例分别严格匹配 10/1/2/2 条预期 ERROR；非预期 ERROR/SCRIPT ERROR/leak 为零。见 `drive/results.json`、`drive/executions.tsv` 及原始日志。

最终同一 native 的 21 套回归全退出 0，见 `regressions/exits.tsv` 与每套 JSON。包括 passive Hinge/Pin、runtime clock、typed control/terrain、atomic presets、Character、P0、contacts、Area/environment、native backend、overlap/witness/sweep/precision、capsule/cylinder、heightfield、editor、strict smoke。各 runner 严格区分预期负例；未将只读分析计作运行通过。

原始完整回归项目和日志：`/workspace/shared/validation/hinge-drive-final6`；本目录保留结果与 `regression-log-sha256.json` 原始日志校验清单。新增套件完整产物：`/tmp/gmj-hinge-drive-final6`，原始日志已复制到 `drive/`。源码构建日志 `build.log`。

## 复用命令

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=/tmp/hinge-drive-verify bash tests/native_hinge_drive/run.sh
# 下列 suite 名称取 regressions/exits.tsv 第一列，OUT 必须新建：
OUT=/tmp/verify-$suite REPEAT=1 bash tests/$suite/run.sh
```

原执行环境短暂不可用时没有切换环境或重启构建；恢复后核对目录、未提交文件和原 session，继续等待原回归完成。

## 复审与失败证据

- 质量投影需计入偏心锚点。最终覆盖离 COM 1 m 的球体平行轴惯量、1kg/2kg 两端角动量及旋转非对称惯量。
- 反平行 full frame 的相位兼容不足，主动模式明确拒绝，被动能力保留。
- 原提前返回 step success 的路径与新增数值拒绝不兼容，改为实际步后完成。拒绝整段回滚时间、姿态、速度、阻尼、一次力和回调信息；queued cancel/inactive 等已测。
- build5 中 wrapped-angle 检查漏掉外力引起单步整圈：`review/alias-run.log` 是 **9 pass/2 fail、exit1** 的真实历史失败。build6 加实际相对角速度检查，原脚本不变 **11/11、exit0**，见 `review/build6-alias-run.log`。不能把历史失败日志混为最终正向。
- 早期 build2/4/5 局部通过不替代本次最终产物的重跑。

## 尚未运行/限制

新功能的真实 dot 桌面 GUI、独立源码构建仍待父任务安排；headless 输入派发仅为 smoke。无强制分配失败注入，无 G1 重负载、Windows、打包、远端 CI 或引擎修复。冷导入139未根治，缓存/已有导入流程不算 fresh cold pass。主动关节链、闭环、多圈、可调求解响应、复杂接触负载和长时大载荷不在完成声明内。

## HTML 节点交接

- 原生后端 / Hinge / 被动约束：保持已验收（基线4c2f1f7）。
- 原生后端 / Hinge / 独立连接角限位与速度电机：实现及本地源码/轻量回归完成，dot 独立验收待完成，未合 main。
- 原生后端 / 生命周期 / 驱动失败整步回滚与真实 step 完成反馈：同上。
- 原生后端 / Hinge / 主动链、闭环、多圈、自定义响应：未完成；仅建议后续按需求选择，不自动执行。
- 下一步：dot 从最终提交重建并按测试 README 做 motor/limit/反转/暂停/步进/保存重开 GUI；通过后再决定合入。HTML 本任务不重复生成。
