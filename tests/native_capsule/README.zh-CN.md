# 原生 CapsuleShape3D 轻量回归

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16，复用主任务已构建 addon。
本目录不构建、不打包、不启动远端 CI。脚本复制独立项目，在三个新进程重复正例，负例单独运行和匹配错误。

```bash
source /workspace/shared/tools/env.sh
OUT=$(mktemp -d /tmp/gmj-capsule.XXXXXX) bash tests/native_capsule/run.sh
```

`results.json` 保存计数、Godot 版本和实际被测 extension SHA256；`executions.tsv` 记录各阶段退出码。
正例任何 ERROR、leak 或 unsupported 都失败；负例只接受指定的 11 条形状/变换拒绝 ERROR，以及已知连续扫掠数值拒绝 WARNING。

## 已执行验收计数

- geometry：24。真实 capsule 类型、包括半球的 full height、数据隔离、端帽和侧面 ray、inside 策略、point、旋转与局部偏置、每对 witness 的独立表面检验、rest 法线、margin、初始重叠。
- lifecycle：14。ray/point/shape exclude、layer/mask、尺寸更新、禁用/启用、多 shape 索引、移除、换 space、释放。
- degenerate：5。`height == 2 * radius` 的射线、point 和 overlap 球退化行为。
- sweep：41。移动胶囊对 sphere/box/cylinder/capsule/plane、margin、零运动、远离、初始穿透、mask/exclude/disabled、水平旋转、球退化、可表示切触、近切触 miss、高速薄墙、忽略初始目标但保留后续目标，以及不激活 space。
- dynamics：6。普通 CapsuleShape3D resource、落地高度、mass、解析惯量、改变尺寸时保留运动状态、球退化惯量。
- overlap_pairs：48。四类目标双向、同心和偏心旋转，独立验证双方表面及深穿透。
- ownership：7。排序、max_results、失败重建、恢复、shape RID 释放。
- area：5。胶囊触发、退化球更新、进入退出、释放。
- 总计正例 **150 × 3**；负例 **14** 个断言（包括 11 条预期错误、2 个 sweep 拒绝）。实际结果以执行后的 JSON 为准。

## 独立几何与惯量依据

表面检验使用 query/target 各自局部坐标下“点到中心轴线段的距离减 radius”，不复刻实现的接触中点重建。
full height `h` 转换为轴线段半长 `h / 2 - r`。

均匀密度 capsule 的圆柱长度 `L = h - 2r`。圆柱质量 `mc = m L / (L + 4r/3)`，两半球质量之和 `ms = m - mc`。

- 轴向惯量：`I_y = mc r²/2 + ms (2r²/5)`。
- 横向惯量：`I_x = I_z = mc (3r²+L²)/12 + ms (2r²/5 + L²/4 + 3Lr/8)`。

半球质心平移项不能按“整球加圆柱、两者都在中点”替代。`L=0` 应退化为 `2mr²/5`。

## 已验证的实现契约

1. direct RID 的 capsule data 是 `{radius,height}`；有限 `r>0,h>=2r` 接受，`h<2r` 拒绝并保留旧值。
   Godot Resource setter 自身可联动调整尺寸，所以非法输入使用 direct RID API 验证。
2. 严格 fraction 策略与此前 sphere sweep 一致：准确可表示的 `t=.5` capsule 擦边成功；`t=.3` 的零宽接触、
   小于 float fraction ULP 的碰撞区间不能假装有可用 unsafe，应返回空并发已知数值拒绝 warning。
3. capsule 对各有限 convex target 的轴线段距离求解不是离散采样；本测试以解析 TOI 和高速薄墙暴露采样漏检，
   不把有限测试当作连续性的数学证明。
4. 形状错误使用与 Cylinder 平行的 Capsule 文案（run.sh 有精确白名单）；实现若调整消息需同步白名单，不能笼统忽略 ERROR。
5. 默认均匀密度自动惯量采用完整 capsule 体积分；测试容差与既有 cylinder 回归相同数量级。

本测试没有运行 CharacterBody3D 的 move_and_slide；运动学语义应由独立阶段验收。
