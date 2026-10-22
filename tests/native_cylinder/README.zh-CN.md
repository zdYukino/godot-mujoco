# 普通 Godot 原生圆柱

`CylinderShape3D` 可用于 `StaticBody3D`、`RigidBody3D`；沿用原生 box/sphere 的空间、质量、碰撞层/掩码、状态迁移与射线身份映射。此能力与 MJCF cylinder 编辑是不同入口。

- Godot 半径 radius、完整高度 height（米），轴向局部 +Y；映射 MuJoCo 半径、半高、局部 +Z。支持 body 与 shape 的刚性平移/旋转。
- 半径/高度必须有限且严格正值。非法底层 shape_set_data 保留旧数据；输入和读取字典复制隔离。Godot 资源本身允许零值，不代表后端支持退化圆柱：勿把资源界面的非法值当作已成功应用。
- 不支持 scale、镜像、shear，修改尺寸字段而非节点缩放。自定义惯量、CCD、sleeping、通用 shape sweep 等仍遵循既有不支持契约，不因新增圆柱而开放。
- 单 shape 惯量由 MuJoCo 根据质量和尺寸自动计算；多个启用 shape 按现有规则均分质量。尺寸更新由原有 rebuild 路径保留兼容姿态/速度，射线只读取实际编译几何。内部起点默认不命中，hit_from_inside 返回原点与零法线。

官方输入契约来源：[Godot 4.7.2 CylinderShape3D](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/3d/cylinder_shape_3d.cpp)。仅改应用扩展，没有修改 Godot 引擎。

```sh
# 先按根 README 从源码构建扩展，使用官方固定 .NET Godot。
OUT=/tmp/gmj-cylinder GODOT_BIN=/path/to/godot bash tests/native_cylinder/run.sh
```

新 OUT；日志与 executions.tsv 保存实际退出码。正例35项覆盖端盖/侧面坐标法线及身份、组合旋转、inside/exclude/layer、尺寸更新、disable/re-enable、序列化重开、释放、刚体接触/质量/惯量/状态连续性、box接触静态圆柱、多shape索引及移除。负例独立进程，严格限定9条预期 ERROR，并断言旧数据/变换不变；不能将这些预期错误混入正例。

GUI：打开 `$OUT/project/project.godot`，F5。左侧静态圆柱托住 box，右侧圆柱刚体落在平面；视觉和碰撞应重合，按 R 重开场景验证重新创建。编辑器停止再启动结果一致；CylinderSaved.tscn 是正例生成的尺寸/旋转保存样本，可打开核对资源。真实桌面操作仍需 dot 独立验收。Headless 启动 GUI 场景只证明加载路径，不证明图形正确。

固定 Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16.0。不运行 G1 重负载、不打包、不 Windows、不修冷导入139。未注入强制编译器或分配失败；有限正尺寸不保证超大数值可被 MuJoCo 编译接受。
