# MJCF 层级节点编辑

第一阶段把 MJCF 作者数据、Godot 正式场景树和共享 MuJoCo 世界连接起来。五个例程及新工程模板均使用这条路径；`MjWorld` 仍保留给独立 API 与诊断测试。

## 日常操作

1. 打开并保存一个 3D 场景，在右侧 **MuJoCo → MJCF 层级模型** 点击 **载入 MJCF**，选择 `.xml`。仅接受 MJCF XML；旧模型包和升级入口已移除。
2. 场景中生成 `MjRuntimeWorld → MjModelInstance → MjBody3D / MjGeom3D / MjJoint3D`。body 按源层级嵌套，geom/joint 属于对应 body；`_Visual` 是视觉子节点，选择它会转到语义节点。
3. 在场景树中选择部件，在 Godot **检查器 / Inspector** 的 `Mjcf` 参数组修改物理量。用原生移动、旋转 Gizmo 修改初始设计位姿。关节黄色轴线表示其局部轴。需要查看 Inspector 时点击右侧检查器标签。
4. 在 MuJoCo 面板新增 body、常见几何，或点击“新增 joint”（默认 free，其他类型在 Inspector 的 Type 中选择）；可导入 OBJ/STL mesh。使用场景树 F2、Ctrl+D、删除与重新挂载；Ctrl+Z / Ctrl+Shift+Z 撤销和重做。
5. Ctrl+S 保存 `.tscn`。未完成、物理无效的模型也可以保存并重开；只有当前设计验证完成后才能 F5。状态栏显示编译进度和具体错误，可取消或恢复上次有效设计。

左侧场景树通过不同颜色和形状的图标区分节点：body 为蓝色立方体，joint 为橙色关节，geom 为绿色几何图标。

球只允许均匀缩放；圆柱和胶囊两个径向比例必须相同；缩放会写回物理尺寸并把 Node3D scale 恢复为 1，保持形状种类。body、joint 和模型摆放必须是刚性变换。plane 的尺寸仅控制显示范围，碰撞仍为无限平面。普通 frame 坐标会映射回源数据，复杂 frame 缩放/继承不支持直接移动，Inspector 会标明只读。mesh geom 支持凸包与 SDF 切换；heightfield 使用专用地形编辑入口。

Inspector 包括 body 的自动/显式惯量、质量、主惯量、惯性坐标朝向和质心；几何的尺寸、密度、摩擦、碰撞过滤与 margin；关节的类型、锚点/轴、限位、阻尼和初始位置；position/velocity actuator 的增益。角度在 Inspector 中以度显示，仿真控制与原生 qpos 使用弧度。

选中 **geom** 后，在 Inspector 的 **Node3D → Visibility** 中设置 **MJCF 颜色**、**MJCF 不透明度**（0 完全透明，1 完全不透明）和 **MJCF 贴图 (PNG)**。贴图路径留空可清除；PNG 会复制到项目的 `mujoco_models/`，作为 MJCF 的 texture/material 资产保存并随 MJCF 导出。颜色与不透明度写入 MJCF RGBA，修改当前 geom 时会派生独立材质，其他使用同一材质的部件保持原样。编辑支持原生撤销/重做，后台验证后更新预览，保存重开及 F5 运行保留外观。2D 贴图使用 mesh 的 UV；没有 UV 的几何沿局部 MJCF Z 轴投影。贴图与颜色相乘，希望显示贴图原色时将颜色设为白色。

调色支持按住鼠标连续拖动；点击弹窗外提交本次调色，一次撤销可恢复开始时的颜色；Esc 取消本次调色。数值变化和后台编译不会重建当前 Inspector，切换关节类型等字段结构变化仍正常刷新。

## 数据和依赖

场景内的 `MjAuthorResource` 保存完整 XML 树、稳定 ID、显式初始关节位姿和来源信息。actuator、sensor、tendon、equality、默认类等不会因视图未显示而消失。名字和 NodePath 不是身份；重命名会修复有类型的引用。删除及关节类型变化会列出关联对象并确认级联，整体操作可撤销。复制子树会复制完全内部依赖，跨边界依赖会被列为省略项。

载入 XML 时复制依赖到项目的 `mujoco_models/`，原始文件保持只读。网格缩放为实例派生新的 mesh 定义；复制模型拥有独立作者文档。可在面板显式导出 MJCF 与依赖。外部压缩视觉/碰撞 mesh 是可重建资源，完整作者树才是编辑源；搬迁时复制整个工程及 `mujoco_models/`。

## F5 时修改设计

本地编辑器场景是唯一设计源。运行中仍可编辑本地层级：第一次物理修改暂停实际 MuJoCo，后台验证当前模型，再编译整个共享世界并在物理边界原子替换。成功后保持暂停，点击“继续”恢复；失败、超时或取消时保留草稿和旧活动物理，并禁止以旧缓存继续运行。

未受影响的关节 qpos/qvel、控制值和世界时间继续保留。稳定 ID 重命名保留状态；关节类型、轴、父链或显式初始位姿改变时，受影响子树恢复新设计初态并清零速度。显示、相机、控制输入、施力和速度调整不发起结构编译。运行中掉落位置、速度和世界时间不会写进 Ctrl+S 保存的设计。

游戏里的“添加 G1”“抬高地形角点”向对应编辑器场景发送设计命令，修改出现在本地场景树、Undo 和后续保存中。独立运行没有编辑器连接时禁用设计按钮；暂停、步进、控制、重置照常可用。

## 编译与兼容性

编译在独立的 Godot headless worker 进程中执行，使用该工程的 GDExtension。进程可强制结束，结果带版本/任务标识，旧结果不能覆盖新设计。默认时限 120 秒，可设置项目键 `mujoco/authoring/compile_timeout_seconds`。worker 结果保存在用户缓存，主界面按帧准备显示资源。

源模型的全局选项需与世界一致。共享世界暂不接纳插件、flex/skin、源 mocap、全局 userdata 和 keyframe；这些作者数据仍保留，报错后可保存，不能静默丢弃后运行。已有独立 `MjWorld` API 不受该组合限制影响。

默认单 G1 是验收项。双 G1 添加仅为可取消、有时限的诊断；原有跨宿主超过 150 秒的热加问题和旧路径冷导入 139 仍保留在已知问题中，当前实现不将其宣称为已修复。

## 验证入口

- `tests/node_authoring/run.py`：XML/依赖闭包、无效保存、强制超时/取消/恢复、版本隔离、原子重建、状态迁移、Editor Undo/保存和实际编辑器到游戏的 debugger 连接。
- `tests/example_projects/run.py`：五个项目和新工程模板的独立导入/运行；摆杆覆盖 Main、ChaosPendulum、VisualDebug；轻量例程正常构建 .NET 后运行九项控制与接触断言。
- `tests/node_authoring/gui_probe.gd`、`gui_actions.py`：真实桌面鼠标/键盘验收用观测与驱动工具。headless 断言不能替代 Gizmo、Ctrl+D、Ctrl+S 和独立进程重开的 GUI 证据。

geom 的凸包/SDF 精度、World 六项检测参数、资源预算及导出行为见[逐 geom 碰撞设置](geom-collision.zh-CN.md)。
