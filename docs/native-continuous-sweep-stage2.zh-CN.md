# 原生连续平移 sweep 第二阶段

基于 overlap 阶段 `0bc54e2d5f365baf3388cc4dbee8b2d9f2b4442b` 独立开发。
新增 `cast_motion` 的**明确受限组合**，不是全形状 sweep、动态 CCD 或 CharacterBody 完成。

## 距离接口的实证

`tests/native_sweep/distance_contract.cpp` 只使用 MuJoCo 3.16.0 公开 API。
同心、尺寸为 1 的 cylinder/cylinder、cylinder/box、box/box，`mj_geomDistance`
返回 0 且两个 witness 全零；sphere 参与的对应测试返回 -2，分离 5 的对应 pair 返回 +3。
因此不能直接把所有 pair 的该返回值当作有可靠 signed distance / witness 的通用 sweep 基础。
这不是宣称 MuJoCo 无法用于任何距离查询，而是本次验证不足以支持通用保证。
本阶段不调用这个 API 决定 TOI，使用独立的解析 primitive 点距离与支持函数。

## 支持矩阵

下表记录第二阶段原始矩阵；当前集成新增 Capsule 查询/目标及球对 Capsule，最新组合见[Capsule 阶段](native-capsule-stage3.zh-CN.md)。后续 float 认证修复见 `tests/native_sweep_precision/`，不取消不可表示位置的明确拒绝。

| 查询形状 | 目标 sphere | 目标 box | 目标 cylinder | 目标 world-boundary |
|---|---|---|---|---|
| sphere | 连续凸距离 | 连续凸距离 | 连续凸距离 | 线性支持平面 |
| box | 明确失败 | 明确失败 | 明确失败 | 线性支持平面 |
| cylinder | 明确失败 | 明确失败 | 明确失败 | 线性支持平面 |
| world-boundary | 线性支持平面 | 线性支持平面 | 线性支持平面 | 明确失败 |

- 只支持平移，query orientation 固定；target 使用查询时的姿态，不把其线/角速度积分到未来。
- 支持目标 body 旋转、shape 局部偏置、多个 shape；box/cylinder 对平面使用实际旋转后的支持点。
- 支持范围外的**任何通过过滤的原生目标**导致整个调用失败，即使目标很远或已有更早命中。
  不会跳过未知障碍后返回 `[1,1]`。尚未做 broadphase 裁剪。
- 专用 heightfield 是明确失败的原生目标；Area 请求明确失败；MJCF 导入 geom 无 Godot Body RID/shape 映射，
  不属于当前原生查询集合，仍不参与。不能用本结果保证不碰撞导入模型。

## 连续算法和数值边界

对球，令 `p(t)=p0+t*motion`，目标凸体 `C`，有效半径 `r=query_radius+margin`。
box 的 closest point 是三轴 clamp；有限 cylinder 是径向 disk 投影与轴向 interval 投影；sphere 是径向投影。
`F(t)=distance(p(t),C)^2` 为凸、连续可微函数，导数为 `2*(p-project_C(p))·motion`，单调不减。
先在整个 `[0,1]` 上夹逼导数零点（或端点全局最小），再在下降区间夹逼最早的 `F(t)<=r²`。
每次最多 96 次 double 夹逼，并在无可表示中点时停止；不是固定/自适应离散时间采样。
这一数学结构能找到任意短的进入区间以及切触，不要求帧末仍处于穿透。

有限形状和平面的距离是一个线性支持平面函数，直接求根；margin 只计一次。
同一 shape 在初始姿态满足严格负距离（含 margin）的，按 Godot cast_motion 策略在整次 sweep 中忽略。
初始恰好接触且向内运动返回 0；恰好接触且分离/切向运动忽略该 shape。零运动成功返回 `[1,1]`。
这些规则不是穿透恢复；`body_test_motion` 的恢复算法仍未实现。

数值不是无限精度的“证明”：导数/距离在 double 中计算，最终 ABI fraction 为 float。
对分离的最小值，使用距离的 Lipschitz 界（速度×最小值括区宽度）及
`128*double_epsilon*max(1,|start|,|motion|,|target_size|,r)` 舍入预算确认 miss；
不能确认则明确失败，不返回可通过。接触的距离测试仍有机器精度误差，不能承诺无限尺度精确几何。

成功命中返回 `0<=safe<=unsafe<=1`；向外舍入到 float（safe 再向零退一 ULP）后，再验证 **safe 不穿透、unsafe 满足距离阈值**。
同时检查 double 连续路径与 Godot `origin + motion*fraction` 的实际 float 姿态，避免大坐标消减误差。
如果整个碰撞区间短于一个 float ULP，或唯一切触时刻不能表示，调用明确失败，输出参数清零；
Godot 公共 API 得到空数组并发一次具体 warning。
例如球切触 `t=.3`、极薄障碍在 `t≈.3`、坐标 `1e8` 下不存在有效 safe 的案例被负例验证；`t=.5` 可表示的切触成功。
因此不能将所有擦边都视作成功返回，也不能将空数组解释为“无碰撞”。

无命中返回 `[1,1]`。多目标按最早接触选取，精确时间平局按 RID/shape index；safe 取所有命中下界的最小值。
optional rest-info 的 target witness、外向 normal 和接触点速度与 overlap 共用结果填充函数；
目标速度包括绕实际 COM 的角速度。info 使用 double TOI 的 witness，不依赖舍入后的路径采样。

## 状态、过滤和失败

共用 overlap 的原生所有权、layer/mask/exclude、disabled/pending-free、跨 space 和失败重建过滤。
只允许有限、无缩放/剪切/镜像的 query transform，非负有限 margin、有限 motion、有效 primitive RID。
不调用 `mj_step`、不运行 live collision，不推进 time、改变 active 或写 live contact/qpos/qvel。
需要 dirty rebuild 时沿用已有事务，失败不会使用旧模型。

代码仅修改查询 `.cpp`、新增内部纯数值头 `mj_sweep.h`；没有公共服务器头文件、刚体/接触报告接口变化。
共享变化是匿名命名空间里的 `rest_result`，用于统一 overlap/sweep 输出。

## 验证与复现

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16.0 源码构建。

```sh
# 不依赖 Godot 的连续数值回归，包含独立球/球二次方程 oracle。
g++ -std=c++17 -O2 tests/native_sweep/numerics.cpp -o /tmp/sweep_numerics
/tmp/sweep_numerics
# 公开距离接口验证（按本机源码 include 与 lib 目录替换参数）。
g++ -std=c++17 tests/native_sweep/distance_contract.cpp \
  -I "$MUJOCO_SOURCE/include" -L "$MUJOCO_BUILD/lib" \
  -Wl,-rpath,"$MUJOCO_BUILD/lib" -lmujoco -o /tmp/distance_contract
/tmp/distance_contract
# 插件先完成源码构建；脚本创建隔离项目，重复三个进程，扫描 ERROR/leak。
bash tests/native_sweep/run.sh
bash tests/native_overlap/run.sh
```

未推进 capsule、CharacterBody、body_test_motion、旋转 sweep、动态 CCD、heightfield/MJCF sweep。
这些仍需可靠凸体距离/支持平面下界、穿透恢复和各自的所有权/asset 接口；不能因本阶段通过而自动宣称支持。

### 本阶段实测（2026-10-22）

- 源码增量构建通过：Godot `4.7.2.stable.mono.official.ed1daf0bf`，MuJoCo `3.16.0`，`GMJ_BUILD_MUJOCO_FROM_SOURCE=ON`。
- 独立纯数值：1048 checks，包括 1000 个球/球解析二次方程 oracle；薄墙厚度 `1e-6`、位移 `1e9`。
- MuJoCo 公开距离契约：12 checks，重现 3 种同心穿透零 witness 情形。
- Godot sweep：3 个新进程，每次 76/0；另有 5 个明确拒绝例，匹配 3 种去重 warning。
- overlap：3 个新进程，每次 154/0；native_backend：149 checks；core smoke：PASS。
- 最终日志 ERROR/leak 扫描通过；未跑 sanitizer、GUI、Windows、打包、G1 heavy 或远端 CI。
- 验收日志：`/workspace/shared/validation/native-sweep-certified`、`sweep-overlap-final`、`sweep-backend-final`；
  数值/契约/core 日志分别为 `sweep-numerics-final.log`、`sweep-distance-final.log`、`sweep-core-final.log`。
  最后构建日志 `/workspace/shared/sweep-build-certified.log`。
