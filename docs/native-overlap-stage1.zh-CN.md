# 原生空间 overlap 第一阶段

基点：`8d3976e1d0fb71588b9b303d6c202708d6737bbe`。实现只修改
`src/physics/mj_direct_space_state.cpp`，无公共头文件、刚体状态或接触报告接口变化。

## 支持契约

- `intersect_point`：原生 sphere、box、cylinder、capsule 内部与 world-boundary 负半空间；严格内部，边界点不命中。无 epsilon 扩大。
- `intersect_shape` / `collide_shape` / `rest_info`：上述原生形状查询上述原生形状。
  plane/plane 没有有限接触流形，不返回结果。支持全刚性旋转、body 与 shape 局部偏置、多个 shape。
- 专用 `MjStaticHeightField` **尚不支持这四种 overlap**，跳过并发一次 unsupported warning；原有 heightfield ray 不变。
  普通 `HeightMapShape3D` 仍不支持。导入 MJCF 的 geom 没有 Godot Body RID/shape 所有权，跳过，
  不会伪造 collider。即便导入的是 sphere/box，也不纳入本阶段查询。
- Area 监测与环境覆盖已另行实现，但本空间查询仍不返回 Area；请求 areas 会告警，原生 bodies 结果仍遵循 bodies 参数。
- 初始重叠直接纳入结果。`motion` 不用于 overlap（只检测 transform）；非有限 motion 拒绝。
  `cast_motion` 现有[受限连续平移支持](native-continuous-sweep-stage2.zh-CN.md)及[Capsule 扩展](native-capsule-stage3.zh-CN.md)，不是全组合 sweep、CCD 或 CharacterBody。
- `margin` 是 MuJoCo 窄相距离阈值，只传一次，不把 target/query 各扩大一份。
  非负且有限；负数/NaN/Inf 拒绝。零 margin 的精确相切受各原生窄相算法浮点容差限制，
  不保证跨形状的相切命中一致；需要接近接触时应显式使用正 margin。
  Shape RID 的求解器 margin 不额外叠加到查询 margin。
- 查询 transform 只接受有限、无缩放/剪切/镜像的刚性变换；未支持或无效 RID 返回空。
- 查询 mask 匹配目标 body layer；目标 body mask 和 ray_pickable 不影响 overlap。
  exclude、disabled、跨 space、已 free/待 free 都被过滤。
- 按 RID 数值、Godot shape index 排序；同 shape 的接触点保持 MuJoCo 固定遍历顺序。
  `intersect_shape` 每个 shape 去重，`collide_shape` 不去重流形。
  `max_results <= 0` 返回空；shape/point 上限按 shape，collide 上限按接触点对。
- `collide_shape` 点对顺序：查询形状 witness、目标 witness；不把 margin 当作穿透深度。
  `rest_info` 选择距离最小（穿透最深）的接触，平局遵循上述顺序；point 在目标上，normal 从目标指向查询。
  linear_velocity 为目标接触点速度，包含 COM 的平移与角速度；静态目标为零。

## 状态与失败边界

查询先使用现有 `rebuild` 同步 dirty 模型。重建失败立即返回空，不查询旧模型，恢复合法状态后可重新查询。
重建可能更新模型 revision，但不推进 simulation time，也不改变 space active / pause / body 活动标志。
窄相使用独立、仅有两个 primitive 的临时模型和 data；不会运行 live `mj_collision` 或 `mj_step`，
不会写活动 data 的 contacts / forces / qpos / qvel。RAII 销毁 scratch spec/model/data。
MuJoCo 3.16 native GJK 对完全同心 cylinder/cylinder、cylinder/box 可漏报；零命中的 cylinder pair 使用
独立的 support-witness MPR 窄相回退（后续 witness 修复），不扰动几何、不采样运动。超出 Godot real_t 范围的 query 尺寸与非有限 witness 拒绝。
每次 shape 查询编译一个小 scratch 模型，这是正确性优先的第一阶段实现，未作吞吐量承诺；
后续可在明确线程与生命周期边界后缓存 scratch 模型。

## 连续扫掠依赖方案

MuJoCo 的 `nativeccd` 是凸形状窄相 GJK/EPA，不等同于时间连续 sweep。
当前碰撞 dispatch 提供接触但不提供可靠的分离距离下界；离散步进或仅碰撞时二分会漏薄墙。
后续应先建立独立、可测试的 signed-distance / witness 接口（例如验证 `mj_geomDistance` 对全部支持 pair 的范围、
正 margin、退化和容差），再实现保守推进或解析 TOI；建立 safe/unsafe 的括区不变量与终止容差。
初始穿透策略需独立约定（Godot cast_motion 跳过初始重叠形状 vs body_test_motion 的恢复流程），
并测试高速薄墙、擦边、极小位移、角落、多障碍和初始穿透。不能把本阶段 overlap 冒充这些行为。
heightfield/mesh 还需独立 asset-aware distance / sweep 路径及原生所有权方案。

## 验证入口

`tests/native_overlap/run.sh` 创建隔离项目并重复三个新进程；扫描 ERROR 与 leak。
覆盖原生有限形状两两组合、plane、接触方向/目标 witness、初始穿透、margin、mask/exclude、
禁用/重启/移除/free/跨 space、旋转与局部偏置、多 shape、排序、结果上限、失败重建与恢复、
不激活空间/不积分状态、接触点角速度。测试日志和实际计数见本次 PR 验证记录。

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16 源码构建；不包含 Windows、打包、G1 heavy 或远端 CI 门槛。

### 本阶段实测（2026-10-22）

- Godot `4.7.2.stable.mono.official.ed1daf0bf`，`GMJ_BUILD_MUJOCO_FROM_SOURCE=ON`，MuJoCo `3.16.0`。
- `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 6`：通过；core smoke：PASS。
- `tests/native_overlap/run.sh`：3 个新进程，每次 154 passed / 0 failed。
- `REPEAT=1 tests/native_backend/run.sh`：149 checks / 3 个新进程，通过。
- `bash tests/native_cylinder/run.sh`：35 正例 + 9 精确匹配的预期拒绝，通过。
- `bash tests/heightfield/run.sh`：73 passed / 0 failed。
- 上述最终回归均通过各自 ERROR / leak 日志扫描；未跑 sanitizer 或 GUI 验收。
- 最终日志目录：`/workspace/shared/validation/native-overlap-2`、`overlap-backend`、
  `overlap-cylinder`、`overlap-heightfield`；构建日志 `overlap-build-fallback.log` 在 shared 根目录。
- 首次运行暴露的同心 cylinder 窄相漏报已修复；早期 `native-overlap-1` 是失败诊断日志，不是验收结果。


## 后续 witness 修复

集成证据 `fe35dd92875b7463e63611ded9a753c9dad1d9e7` 的 18 组测试揭示此前的 48 项表面归属失败，
旧 154 项 overlap 回归不能替代该证据。修复基于 sweep 提交 `c39bb79957141be563794b5c1880a44386732c69`。

每个 native contact 先用原始 primitive 的解析表面检查两侧 witness。不能合法还原的流形，或 native
GJK 漏报的同心 cylinder pair，改用独立 MPR portal 的**原始 support 顶点和同一组重心权重**生成两侧 witness。
不再把 MuJoCo/libccd 的 contact position 当作天然的 witness 中点，也不交换、投影或移动真实几何来凑表面。
使用形状内严格内部参考点建立 portal，不改变任何物理姿态或 support 顶点。

MPR 位移方向与 target 的光滑表面法线并不总是相同，因此 `rest_info.normal` 从目标 witness 所在表面特征的
外向法线锥提取；这不改变 witness 对或其穿透深度。无效多点流形由一个经过验证的穿透 witness 对替代，
不保证流形点数与旧实现相同，也不宣称全局最小平移恢复。初始深穿透仍命中，并保留非零穿透距离。

小型 BSD libccd 派生 query helper 位于 `src/physics/query_ccd`，CMake 增加三个 C 编译单元；
MuJoCo 本体、公共服务器接口和 sweep 距离/算法未改。来源、许可和局部改动见该目录 README。
新增 `tests/native_overlap_witness` 从集成复现扩展至 36 组/325 断言，包括偏心、normal cone 和深度保留。
