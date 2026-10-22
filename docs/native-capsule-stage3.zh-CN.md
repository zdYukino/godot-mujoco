# 原生 CapsuleShape3D 阶段

基于 `62fb00ae0ab75d2ad8b775f7597bcd0f20cd7ff0` 新建独立分支，先合入
`fe35dd92875b7463e63611ded9a753c9dad1d9e7` 的已提交 P0/contact 前置代码；
再合入冻结集成 `2442976827fa1590de1777143ecc41cdac227025` 的 Area FIFO，保留已修复的 overlap witness 测试。此阶段本身不含CharacterBody/body_test_motion；当前集成另有[受限阶段4实现](native-character-stage4.zh-CN.md)。

## 尺寸与模型

- Godot 本地 Y 轴；MuJoCo 本地 Z 轴，沿用 `(x,y,z) -> (x,-z,y)`。
- `radius > 0`，完整 `height >= 2*radius`，尺寸必须有限。MuJoCo capsule size 为
  `radius, height/2-radius`，后者是轴线段半长，不包括半球。
- `height == 2*radius` 编译为球；Godot RID/type/data 仍为 Capsule，不制造 epsilon 圆柱段。
- 直接 server 非法设置拒绝且保留旧数据；资源 setter 自身联动调整 radius/height。
- 不支持 scale/shear/镜像；支持 body 和 shape 各自刚性旋转及局部偏置。
- 沿用 P0 的均匀密度体积分配多形状质量。体积为 `pi*r²*(height-2*r) + 4*pi*r³/3`；
  惯量由 MuJoCo 体积积分生成（圆柱与两半球，不是等质量球和圆柱）。
- 更新、禁用、删除、换 space、形状释放复用原生重建和所有权链。

## 查询与连续运动支持矩阵

Area FIFO 监测也接入 Capsule 和退化球；其余环境覆写、Area direct query 支持范围不变。

point、ray、intersect_shape、collide_shape、rest_info 新增 Capsule，沿用 mask/exclude、
稳定排序、max_results、初始重叠和表面 witness 验证。不推进模拟或改变 active。

cast_motion：移动 sphere 或 capsule 对静止 sphere/box/cylinder/capsule/plane；
移动 box/cylinder 对 plane；移动 plane 对有限 primitive。其他 pair 明确失败，
不会因为某个更近目标已命中而跳过不支持目标。heightfield 和导入 MJCF 范围不扩展。

Capsule = 轴线段 + 球。先对目标凸体求轴线段的最小距离（沿线段的平方距离导数单调），
再对整个运动区间求平方距离的全局最小值及首次入口。平移线段到目标的距离等于到固定凸
Minkowski 集的距离，其平方距离的梯度由唯一分离向量给出；因此是连续凸求根，不是时间采样。
轴线段长度为零复用球查询。平面走线性 support TOI。

保持既有初始严格穿透按目标 shape 忽略、零运动 `[1,1]` 的 cast_motion 契约；
margin 加在查询球半径上一次。safe/unsafe 继续检查双精度轨迹及实际 Godot float 位姿；
数值擦边或短接触区间无法在 float 表示时明确失败。目标姿态冻结，不是动态 CCD 或旋转 sweep。

## 验收

测试入口 `tests/native_capsule/run.sh`；独立连续几何 `tests/native_sweep/capsule_numerics.cpp`。
使用固定 Linux Godot 4.7.2.NET / MuJoCo 3.16 源码构建，最终计数见该阶段证据目录。
未运行 Windows、打包、G1 heavy、远端 CI 或 sanitizer。
