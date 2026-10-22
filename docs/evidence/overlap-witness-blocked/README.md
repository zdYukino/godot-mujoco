# Overlap witness 集成阻断（不是通过记录）

实际待测代码 = 已发布接触集成 `43a0ab827a890577460f57083be5e336d8c0ef2e` + 查询提交 `0bc54e2d5f365baf3388cc4dbee8b2d9f2b4442b`。源码构建成功。当前发布集成分支不含该查询实现；本目录仅保留复现证据与测试，不宣称 overlap 完成。

`tests/native_overlap_witness/run.sh`：import exit0，positive exit1。18组不同尺寸同心 cylinder/cylinder、cylinder/box 双向、共旋转和不同旋转；127断言中79通过、48失败。各组检查每个 collide_shape witness 是否处于自己的原语表面，以及 rest.point 目标表面与单位法线。普通 overlap 154×3 和相关轻量回归仍通过，不能替代这些数值失败。

最小例：query cylinder radius=.35/height=.6，target radius=1.4/height=3.4，共同中心Godot(3,-2,5)。查询返回 query=(4.4,-2,5)、target=(2.65,-2,5)，落在错误一方表面；其他流形点和旋转组合不能仅交换两点修复。

独立 MuJoCo3.16 C++ probe 也显示相同中心 native `mj_geomDistance` 返回 distance0且两点均中心，collision dispatch返回0。应用现有MPR回退可以发现相交，但 MuJoCo `mjc_Convex` 会调用 `mjc_fixNormal` 修正圆柱法线，并用微扰补充流形且覆盖其深度；不能直接把这些接触当成可靠的两侧表面witness。源代码只读核对：
- https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_collision_convex.c
- https://github.com/google-deepmind/mujoco/blob/3.16.0/src/engine/engine_support.c

修复方向：在应用层使用可验证的 primitive distance/witness 接口，验证包含/同心退化及旋转；不要改引擎、扰动真实几何假装精确、只交换点或只测试非空。与独立查询任务的真实 sweep 前置距离接口协调。`failure-results.json` 是失败证据，不计入任何通过总数。
