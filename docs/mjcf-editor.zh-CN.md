# MuJoCo 编辑器使用

安装后在 **项目 → 项目设置 → 插件** 启用 **MuJoCo Model Editor**，打开编辑器**右侧 MuJoCo 页签**，范围选择 **MJCF 文档**。中央使用 Godot 原生 3D 视图；独立草稿与运行实例分别管理。仓库三个图形例程已配置插件，可[从项目管理器直接打开](../README.md)。

## 导入、选择和视口操作

1. 点击展开 **文档 / 导入 / 发布**，勾选 **显示 MJCF 草稿（独立于正式场景）**。该分组默认折叠，草稿显示默认关闭。
2. 点击 **Import MJCF**，在文件选择器中选择 .xml；G1 专用入口是 **Import fixed G1** 和 **Import free G1 (relaxed)**，选择配套的原始 URDF。保留模型的网格、纹理和 include 依赖。
3. 点击 **聚焦模型**。在 MuJoCo 面板内的模型树选择 body/joint/geom/actuator，或在中央视图左键点选几何。使用 Godot 原生 3D 导航查看。
4. 修改字段后点击 **Apply** 或 **Discard**。**Run / Pause** 控制独立草稿预览；它与 F5 运行的场景不同。

原始资产只读，修改发生在派生文档中。正式场景节点使用 Godot 原生变换轴；独立草稿通过数值和 Move / Rotate / Size 按钮编辑。

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

1. 点击 **Save project model**，在当前项目的 **mujoco_models/** 下保存完整模型包，状态中显示 model.tres 路径。
2. 首次使用建议点击 **Create simulation playground**，通过对话框保存 .tscn。它包含相机、光照和仿真面板，初始暂停；地面由源模型或自建场景提供。
3. 在文件系统面板打开生成的 .tscn，点击 **运行当前场景**（F6），再点击运行面板的 **恢复仿真 / Resume**。运行共享世界前应已选择 MuJoCo 物理后端并关闭独立物理线程。
4. 结束时点击 **停止**（F8）。下次用 **Open project model** 选择包内 model.tres 继续编辑；要生成新场景，打开后再点一次 **Save project model**。

**Create runtime scene** 只生成世界和模型节点，适合继续搭建自己的相机、光照与环境。模型包保存、.gmj.json 文档保存、Godot 场景保存是不同操作；搬迁模型时复制整个包目录。

模型包更新不会自动替换所有实例。选择编辑器场景节点后可显式 Assign saved model；运行时选择带唯一标识的目标再 Apply saved model to runtime。见 [运行安全编辑](runtime-safe-editing.zh-CN.md)。

dot 复验重点：连续选择切换、无效输入、重复 Apply/Discard、真实“新增球/柱→视口选中→Size”路径、undo/redo、保存重开。具体回归证据见 [树高亮](tree-selection-fix.zh-CN.md)、[球柱尺寸](primitive-size-fix.zh-CN.md)、[高级属性英文规则](editor-advanced-properties.md)。
