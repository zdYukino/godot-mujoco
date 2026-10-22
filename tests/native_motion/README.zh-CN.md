# 原生 body_test_motion / CharacterBody3D 最小回归

此目录验收已实现的最小 body motion/Character 工作流。支持边界见
`docs/native-character-stage4.zh-CN.md`；固定平台实测结果见对应 evidence 目录。

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16，使用主任务构建的 addon：

```bash
source /workspace/shared/tools/env.sh
OUT=$(mktemp -d /tmp/gmj-motion.XXXXXX) bash tests/native_motion/run.sh
```

运行器复制独立项目，分别用新进程执行 RID 与 CharacterBody 两个脚本，各重复三次。
一组失败仍执行另一组并保存 `results.json`，不隐藏 floor snap 或多帧行为失败。
日志出现 ERROR、leak、unsupported，断言失败、超时或缺失结果都使验收失败。
`executions.tsv` 保留各进程退出码，JSON 包含被测 extension SHA256 与 CharacterBody 诊断状态。

## 正例：66 断言/轮

### `rid.gd`：43

- sphere/capsule 运动主体，静态目标；解析入口 `safe≈.6`、travel/remainder、point/normal、collider RID/local shape。
- 查询只使用 parameters.from，不写实际 body transform，不激活 space，不向 dynamic target 施加冲量。
- mask、目标 mask 独立、exclude_bodies/objects、Object 身份、双向 collision exceptions。
- target 禁用、脱离空间、释放；运动主体多 shape 最早 local index；max_collisions 1 与 32。
- kinematic target 的即时位置更新。
- 初始穿透恢复：零运动、recovery_as_collision 开关；travel 包含恢复位移，remainder 只属于请求 motion。
- dynamic target 冻结姿态，接触点速度包含角速度和局部 shape 偏置引起的 COM 偏移。

### `character.gd`：23

- 普通 CharacterBody3D + CapsuleShape3D；move_and_collide、test_only、collider identity、travel/remainder。
- 地面落地 90 帧、沿地面向墙运动并滑动 100 帧、floor/wall 法线/分类与位置约束。
- apply_floor_snap 与下一帧持久性。先通过无 snap 的 move_and_slide 清理 teleport 前的 floor flags，避免测试自身制造假失败。
- 向天花板运动 24 帧，阻挡和 ceiling 分类。
- 20 度斜坡落地 100 帧、上坡 30 帧，几何法线和 floor 分类。
- dynamic target 阻挡 query，但 kinematic character 不把自身 movement 变成刚体冲量；释放墙后不读取旧几何。

## 契约

- `body_test_motion` 清路返回 false 且 travel=motion；初始恢复即使 recovery_as_collision=false 也返回恢复 travel。
- KINEMATIC 使用 query-only mocap；不会在 stub warning 后降级检查。
- body_test_motion 的碰撞可见性按 mover mask 对 target layer，不要求 target mask 反向匹配；exceptions 双向生效。
- dynamic target 的线速度按 COM 语义；预期接触速度为 `v + ω × (point - world_com)`。
- 失败不是通过条件放宽来消除；保留日志后由实现决定能否满足 floor snap、斜坡、多帧 CharacterBody 行为。

不包含动态 CCD、旋转扫掠、rigid-linear、separation ray、楼梯或完整移动平台语义；不宣称 CharacterBody 全契约覆盖。

`run_negative.sh` 另验 10 项：不支持的运动形状、缩放、两墙夹困、不可表示擦边、
舍入路径新增碰撞。要求明确零 travel 拒绝及状态不变，严格匹配预期警告。
RID 正例另验大坐标相反局部偏置不穿墙与 clear travel 不超出请求向量。
