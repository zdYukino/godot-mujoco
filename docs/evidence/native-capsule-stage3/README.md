# Capsule 阶段验收

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16 源码构建通过。先合入 P0/contact 和冻结
集成 `2442976827fa1590de1777143ecc41cdac227025`，没有改已有交付提交。

Capsule 150×3 正例、14 负例断言（11 个预期错误、2 个数值 sweep 拒绝）全部通过。
结果/二进制 SHA256、退出码、首轮逐项检查分别见 results.json、executions.tsv、checks.log。
独立 capsule 连续几何 445 与既有 sweep 数值 1048 通过。
交叉回归 overlap154×3、witness325、sweep76×3+5拒绝、Area53+FIFO22、P0语义98、
contact68+1预期拒绝、cylinder35+9拒绝通过。backend149及core smoke也通过。

真实失败记录：`capsule-1` 暴露漏加 P0 capsule 体积，已修复后重跑；
`capsule-contacts` import 退出139，未进入测试；相同二进制 fresh 项目 `capsule-contacts-2`
import/positive/negative/gui-smoke 全部退出0。未将首次失败算成通过，也未修改引擎规避。
最终脚本 ERROR/leak 检查通过，未运行 sanitizer 或桌面GUI。

本机完整日志：`/workspace/shared/validation/capsule-3`、`capsule-final-*`、
`capsule-area`、`capsule-semantics`、`capsule-contacts-2`；源码构建日志
`/workspace/shared/capsule-build-3.log`。

支持范围、连续距离论证和限制见 ../../native-capsule-stage3.zh-CN.md。
这不是 body_test_motion/CharacterBody 阶段验收。
