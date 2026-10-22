# 原生 overlap 接触点数值复验

本入口面向 `intersect_shape` / `collide_shape` / `get_rest_info`，不涉及 sweep、CharacterBody、Area 或 G1。

```bash
source /workspace/shared/tools/env.sh
# 先从含 overlap 实现的确切提交构建 native 扩展。
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=/tmp/overlap-witness-unique bash tests/native_overlap_witness/run.sh
```

仅适用于固定 Linux Godot 4.7.2 .NET / MuJoCo 3.16。入口使用新临时项目，记录实际退出码、日志和扩展 SHA256；导入失败则停止，不重试并冒称通过。正常日志出现 ERROR/SCRIPT ERROR/leak 即失败。

36 组严格同心或偏心、不同尺寸的 cylinder/cylinder 和 cylinder/box 测试，包括查询与目标交换、无旋转、共同旋转和各自不同旋转。世界中心为 `(3,-2,5)`，避免只验证原点附近的坐标转换。

每组检查：

- overlap 目标 RID 和 shape 身份；
- 非空、成对返回的接触点；
- **每一个**查询侧接触点与查询原语解析表面的距离小于 `.003`；
- **每一个**目标侧接触点与目标原语解析表面的距离小于 `.003`；
- rest RID/shape、有限单位法线和目标表面上的 rest point；
- target outward normal cone 的独立几何检查；
- 深穿透 witness 不收缩为零（每一对间距大于 `.1`）。

表面距离独立使用盒和有限圆柱的解析 SDF，不复用后端的 `contact.pos ± normal * distance / 2` 还原逻辑。测试不预设同心情况的唯一分离方向，也不把“返回非空 contact”当作接触点正确。

`positive.log` 的 `OVERLAP_WITNESS_RESULT` 保留每项断言和最大表面误差。通过后生成 `results.json`；失败时保留原始日志及 `executions.tsv`，不输出通过摘要。实际通过状态以执行记录为准，源码存在不代表已运行。
