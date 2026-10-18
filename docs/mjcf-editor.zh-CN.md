# MuJoCo 编辑器使用

安装后启用插件，在顶部选择 **MuJoCo** 工作区。它持有独立预览模型，不会把未应用字段直接写入正在运行的物理世界。

## 导入、选择和视口操作

使用 Import MJCF、Import fixed G1 或显式 Import free G1 (relaxed)。原始资产只读，修改发生在派生文档中。左侧树选择 body/joint/geom/actuator，或在视口左键点击几何；右键拖动和滚轮控制相机。

Move/Rotate 使用当前选择的局部 MJCF X/Y/Z 轴。预览为 Godot Y-up，数值面板为 MJCF Z-up；长度 m、质量 kg、时间 s、角度 rad（旋转按钮标注的步长为度）。Size 操作真实物理形状：球 `[r,0,0]`，圆柱 `[r,half_height,0]`，box `[half_x,half_y,half_z]`。球不会被显示成椭球却继续用球碰撞。

输入字段后必须 Apply 或 Discard。草稿存在时拒绝切换选择、导入或替换文档，树高亮恢复到实际编辑对象，原输入保留。按钮、撤销和重做共用文档事务。

## 属性规则

- hinge/slide 的限位、范围、可表示的标量 damping 和 frictionloss 可编辑；范围顺序和物理合法性必须通过检查。自由/球关节多维 qpos 不作为标量字段写回。
- body 质量、主惯量、惯性中心 ipos 和惯性方向 iquat 可编辑；惯量为正并满足物理约束，四元数格式 `[w,x,y,z]`。
- automatic 模式从几何质量/密度推导惯性。显式 geom mass 优先于 density；明确编辑 density 会切换到由该密度推导。manual 模式的显式 body 惯性优先，不能同时把 density 当作生效控制量。
- 切回 automatic 才恢复几何推导。源 compiler 的惯量策略也有优先级；与源策略冲突时给出错误，不默默忽略字段。
- 只有被识别为兼容位置 PD 的 actuator 开放 kp/kv；velocity/motor/general 不伪装为同一种 PD。control 与结构字段不能混在同一 Apply 中。
- frame 派生 pose 和 fromto 派生 pose/size 只读，避免把编译后的派生值错误写成源参数。其他不支持项明确只读或拒绝，而不是保存时丢掉。

## 保存和运行

Save document 保存编辑文档和其预览状态；Save project model 发布不可变 portable 包。预览里有意设置/保存的姿态可成为资源的初始设计状态，它与运行场景的内存快照不同。

保存项目模型后，可 Create runtime scene 或 Create simulation playground。后者附带相机和仿真控制，但不擅自添加地面来改变源模型物理。需要接触地面时，在保存的环境中添加普通 StaticBody3D/CollisionShape3D。

模型包更新不会自动替换所有实例。选择编辑器场景节点后可显式 Assign saved model；运行时选择带唯一标识的目标再 Apply saved model to runtime。见 [运行安全编辑](runtime-safe-editing.zh-CN.md)。

dot 复验重点：连续选择切换、无效输入、重复 Apply/Discard、真实“新增球/柱→视口选中→Size”路径、undo/redo、保存重开。具体回归证据见 [树高亮](tree-selection-fix.zh-CN.md)、[球柱尺寸](primitive-size-fix.zh-CN.md)、[高级属性英文规则](editor-advanced-properties.md)。
