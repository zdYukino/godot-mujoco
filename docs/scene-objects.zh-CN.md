# 普通场景对象入口

插件底部“MuJoCo 对象”：选中当前场景内 Node3D 父节点，填写唯一名称，选择 box/sphere/cylinder 与静态/刚体。box 尺寸为完整 X Y Z；sphere 为半径；cylinder 为半径与完整高度，单位米。质量为正 kg（静态对象不使用质量）；Layer/Mask 为 uint32 位掩码。

点击创建得到真实 StaticBody3D/RigidBody3D、CollisionShape3D 和尺寸匹配的 MeshInstance3D。每个对象资源独立；只在指定父节点创建，不修改其他选择。重复名称拒绝而非重复创建。无缩放/镜像/剪切、无物理对象嵌套；非法输入不留下部分节点。创建默认局部原点，之后用 Godot 视口移动/旋转，尺寸通过 Shape/Mesh 资源编辑，勿缩放球/圆柱。

原生 Ctrl+Z/Ctrl+Shift+Z 撤销/重做整棵子树；Ctrl+S 保存场景，重开保留形状、质量、碰撞位。创建是设计操作，不注入已运行世界：Stop 后 F5 才载入。编辑现有对象继续使用 Inspector；此入口不承诺已有 Shape 与 Mesh 的后续自动联动。

自动验收：`OUT=/absolute/new/path bash tests/scene_objects/run.sh`，使用固定 Godot4.7.2.NET 与已构建插件。18项检查，包含真实 EditorPlugin/UndoRedo/场景序列化；非鼠标 GUI 验收。
GUI需逐项创建三形状、静态/刚体，检查尺寸、窄窗按钮、重复名称、切换父节点、Undo/Redo、保存关闭重开、F5实际碰撞。无新增native；不扩大物理支持矩阵。
