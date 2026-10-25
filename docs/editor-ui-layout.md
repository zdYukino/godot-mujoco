# 原生 3D 视图与右侧属性布局

本次仅重构编辑器表现层。基线为 `6e68d90f7440b44fae53c28faef3d6923d591ef7`。

## 结构

- Godot 原生主 3D 视图是唯一绘图入口。插件不注册主屏、不创建 SubViewport、相机或底部属性面板。原生场景树、Inspector、场景 gizmo 和导航继续可用。
- 右侧 MuJoCo dock 统一提供 MJCF 文档、静态地图草稿、地形、场景对象创建四个作用域。纵向滚动与单列分组适应窄 dock；没有属性回落到底部的路径。
- MJCF 保留实体树，支持没有可见几何的 body/joint/actuator；选中实体的基本与高级/编译结果分组折叠。未 Apply 字段阻止实体切换，显式 Run/Pause 不受页签隐藏影响。
- 地图将导入/独立包、视图/历史、选中对象基本碰撞、高级接触/组合、全局 world、全局 pair/exclude 分开。能力不支持的控件明确禁用；高级接触 JSON 覆盖摩擦时基本摩擦禁用并解释原因。
- 原生 Inspector 根据场景选择显示模型、地图、地形入口及独立 World 作用域说明。载入场景地图或模型包为显式操作，不通过选择自动覆盖脏草稿。载入后的场景地图网格选择可定位对应草稿属性。
- `nativeccd` 指 MuJoCo 凸碰撞算法开关，不是 PhysX 连续碰撞。没有加入凸分解、USD/PhysX API 或 P4 UE 功能。

## 草稿与生命周期

草稿根挂在 `EditorInterface.get_editor_viewport_3d(0)` 下，和编辑场景共享 World3D，但不属于编辑场景子树、不设置 owner。地图线框/SDF 距离切片与 MJCF、地形预览都走该桥；左键命中草稿才消费输入，右键/中键导航交给 Godot。

地图 Apply 清除临时显示节点，场景只保留正式设计节点；碰撞显示按钮可重新生成叠加层。场景切换清理旧显示并重新创建独立文档的显示。地形 Discard/Apply/关闭清除临时节点。插件关闭清除所有显示根；编辑器会话保留地图历史与各类待应用字段，重新启用恢复。编辑器退出显式关闭地图 UndoRedo，避免绑定方法引用环。

来源冲突、原子导入、显式 Apply、独立包保存/重开/缺源使用、场景和文档 Undo/Redo、地形共享材质、运行实例 Apply 均沿用原有事务。地图 Apply 后仍需明确重启 runtime。编辑器会话内的未保存草稿保留不替代独立包或场景保存。

## 验证与边界

`tests/native_collision/layout.gd` 现在在真实 EditorPlugin 生命周期中运行，覆盖无额外视口、共享原生 World3D、保存隔离、地图/地形场景选择、脏草稿保护、Undo/Redo、重复页签切换、禁用/重新启用及待应用字段恢复。尺寸矩阵为窗口 1180×812、900×600，dock 宽 320/360/420；检查横向无强制滚动以及控件宽度。

这些是 headless 编辑器集成与测量，不是图形验收。实际 dot 的鼠标操作、可见叠加层、窗口布局、关闭编辑器后重开独立包，以及主视图视觉效果仍由父任务验收。没有运行重负载 G1。

原生相机由 Godot 管理；原来的插件自动取景/轨道镜头不再接管相机。“主视图 / 范围”只切到主 3D 并计算范围信息，导航使用 Godot 原生操作。用户自行选择的 Godot 多视图布局不由插件改写；插件本身不增加任何第二预览。复杂 world/contact/relations 参数仍保留高级 JSON 入口。

设计参考：[Omniverse Property Panel](https://docs.omniverse.nvidia.com/extensions/latest/ext_core/ext_property-panel.html) 的选择作用域与分组；实现使用 [Godot EditorInterface](https://docs.godotengine.org/en/stable/classes/class_editorinterface.html) 原生视图、选择与 Inspector API。
