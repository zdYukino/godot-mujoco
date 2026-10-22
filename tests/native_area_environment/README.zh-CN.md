# Area 环境覆盖：原生有限形状

本分支从 `0a42c4a21eda49b574595284f1ff4dee0dbb1687` 创建，先接入 P0 `a92cd39` 和
COM/contact `43a0ab8`，再合入父任务冻结的 `2442976827fa1590de1777143ecc41cdac227025`。
以 `git diff 2442976..HEAD` 审查本阶段增量。query/witness/sweep 直接保留集成版本，没有另写修复。

## 官方契约依据（固定 Godot 4.7.2）

读取了官方 tag 的 [Area3D.xml](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Area3D.xml)、
[godot_body_3d.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/godot_physics_3d/godot_body_3d.cpp)
及 [godot_area_3d.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/godot_physics_3d/godot_area_3d.cpp)。
按 priority 从高到低，gravity / linear damping / angular damping 三个通道独立处理：

| 模式 | 当前通道 | 是否继续较低 priority / World |
|---|---|---|
| DISABLED | 不参与 | 继续 |
| COMBINE | 加到已有总量 | 继续 |
| COMBINE_REPLACE | 加到已有总量 | 停止 |
| REPLACE | 替换已有总量 | 停止 |
| REPLACE_COMBINE | 替换已有总量 | 继续 |

未停止的通道最后加入 World 默认值；之后 Body damping REPLACE 覆盖总阻尼、COMBINE 加自身阻尼，
最终重力乘 Body gravity_scale。相同 priority 在本后端按 RID 升序稳定处理；官方文档未规定同优先级顺序，
依赖 replace 先后时请使用不同 priority。

方向重力是世界向量乘强度，不归一化，不随 Area 旋转。点重力中心是 `Area.transform * gravity_vector`，
计算位置取 Body 原点（与上述 Godot 实现一致）；正 unit_distance 使用平方反比，0 使用恒定强度，
正好位于中心时为零。单位为米、秒、m/s²；阻尼系数与 P0 的 `max(0,1-damp*span)` 一致。

## 支持与实际积分边界

- 仅原生 RIGID Body，Area 和 Body 参与形状限现有 box/sphere/cylinder；不新增复杂几何、MJCF 或 heightfield 支持。
- 使用 Area mask 匹配 Body layer；monitoring/monitorable 不影响环境覆盖。每个 Area 只贡献一次，不按 shape 对重复累加。
- 活动空间每个实际积分区间开始时用当前刚性姿态检测重叠，采样环境并固定用于该区间所有 MuJoCo 子步。
  不做连续穿越检测；变化在下一实际积分区间生效。多次 single-step 请求作为一个积分区间，阻尼只算一次，保留 P0 契约。
- 原生 Body 使用 `(最终重力 - MuJoCo model gravity) * mass` 的外力补偿，保留模型本身的基准重力。
  Area 仍不进入 MuJoCo 实体模型；没有接触冲量或额外自由度。导入模型不被本阶段 Area 修改。
- custom_integrator/omit_force_integration 抑制自动重力/阻尼/力，显式 `state.integrate_forces()` 使用相同环境总量。
- direct-state total gravity/damping 为最近实际积分区间的采样值；首次积分前按当前环境求值。换 World 清除采样。
  回调内参数更新沿用已有 FIFO，既不改变刚完成区间的速度，也不追溯改变其 getter 采样值。
- 暂停不推进速度；暂停时修改覆盖场在下一单步生效。普通 World 和 authored World 的默认重力仍分别遵循 P0 设置/拒绝契约。
- 有限数值校验和非法 mode 拒绝保留旧参数；阻尼和 point unit distance 不接受负值。总量超出 native finite 范围时显式报错并返回零环境，防止非有限值进入求解器；不承诺极端范围物理精度。
- wind、softbody、Area 空间查询、CCD、复杂几何均未扩大。已有监测配对与回调行为保持。

## 依赖冲突与共享接口

接入 P0 时冲突集中在 `_area_set_param`、`_body_set_space`、`_step`、`_flush_queries` 和 direct-state helpers：
保留 P0 的数值验证、COM 映射、callback_pending/sync_pending、实际 span 与一次阻尼，叠加 Area/FIFO 生命周期。
接入 `2442976` 时保留其 `_body_set_space` 的失效 RID 防护，并完整采用其 query 源文件、CMake 与测试。
冲突没有用旧文件覆盖冻结提交的 query 或 witness。

新共享接口为 `MjEnvironment` / `body_environment` 和 Body 积分环境采样；direct-state 和自动积分使用同一计算路径。
几何判定复用监测的 scratch primitive 窄相，环境判定不写监测 reported 集合、不触发信号。

## 验证命令与 GUI

```sh
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/contact-source -j 5
OUT=/tmp/area-env-release-final bash tests/native_area_environment/run.sh
OUT=/tmp/area-env-release-p0 bash tests/native_semantics/run.sh
OUT=/tmp/area-env-release-monitor bash tests/native_area/run.sh
OUT=/tmp/area-env-release-contact bash tests/native_contacts/run.sh
```

正例覆盖反插入顺序的多 Area priority、五种模式真实线/角速度、动态 priority、默认 World、点重力、
进出/禁用/删除导致重力和阻尼恢复、回调修改、暂停单步、custom integration 与 getter 采样一致性。
所有正例/导入/GUI headless 日志禁止 ERROR/leak；负例精确匹配四项输入拒绝。

桌面步骤：

```sh
godot --path /tmp/area-env-release-final/project --script res://gui.gd
```

球在橙色高优先级区域向上加速，离开后蓝色区域使其向右加速，离开两者后使用默认向下重力。
标签显示采样重力、真实速度、总阻尼；空格重置。关闭后检查日志无 ERROR/leak。
本云环境无 DISPLAY/Xvfb，只有 headless smoke 通过；真实 GUI 验收仍需父任务完成。
不做 Windows、打包、G1 重载、远端 CI 或性能门槛。

最终实测：环境 85 passed（另四个精确预期拒绝）；P0 98 passed；监测 53 + FIFO 22 passed；
contact 68 passed；core smoke PASS。源码 build 与所有最终脚本 exit 0，正例日志无 ERROR/leak。
证据见 `docs/evidence/native-area-environment/`。对齐过程中另外跑过 witness 325、sweep 三轮各76及
原生后端149项；这些是 getter 采样细化前的集成检查，不冒充最终产物重复验收。
