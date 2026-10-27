# 图形化使用：文档问题与程序缺口

[返回首页](../README.md)

结论：**原 README 和例程组织都有问题。** 模型和地图已有导入、编辑、保存按钮，原说明却主要引导用户运行终端脚本；同时，仓库例程也缺少直接从 Godot 项目管理器打开所需的项目配置、依赖连接或保存的场景。

本次以“在 Godot 项目管理器选择 examples 下的 project.godot，打开后点击运行”为目标，已补齐三个图形例程。完整源码仓库仍需完成一次原生插件构建；日常打开这些例程不再需要复制文件或执行准备脚本。

## 原先哪些是文档的问题？

| 使用障碍 | 程序已有的能力 | 本次文档调整 |
|---|---|---|
| 导入步骤主要是命令和手填路径 | MJCF、G1、静态地图及模型包都有文件选择器 | 写清页签、分组、按钮、文件和完成后应出现的结果 |
| 导入后看不到模型 | 导入分组默认折叠，MJCF 草稿显示默认关闭 | 先展开“文档 / 导入 / 发布”，开启草稿显示，再导入和聚焦 |
| 说明写成“顶部 MuJoCo 工作区” | 当前是右侧页签，使用中央原生 3D 视图 | 统一入口位置，区分 Godot 场景树与面板内模型树 |
| 生成场景后可能没有相机 | Create simulation playground 已有相机、光照和仿真面板 | 首次体验推荐 playground，说明初始暂停及 Resume |
| 保存后不知道用什么文件重开 | 编辑文档、模型包、地图包和场景有不同保存入口 | 分别说明 .gmj.json、model.tres、manifest.json 和 .tscn |

源码依据：[插件入口](../addons/mujoco_editor/plugin.gd)、[模型按钮和文件选择器](../addons/mujoco_editor/panel.gd)、[默认草稿显示](../addons/mujoco_editor/editor_state.gd)、[折叠分组](../addons/mujoco_editor/property_layout.gd)、[地图面板](../addons/mujoco_editor/map_panel.gd)、[场景生成器](../addons/godot_mujoco/model/scene_builder.gd)。

## 哪些是程序或例程本身缺东西？本次补了什么？

| 例程 | 改动前 | 本次补齐 |
|---|---|---|
| 形状下落 | 有 project.godot、Main.tscn 和模型包，缺插件连接，需要复制 addon | addons 相对链接连接仓库共用插件，原目录即可导入运行 |
| 无控制 G1 | 有 G1.tscn 和模型包，没有 project.godot，依赖形状例程的控件、着色器和 HDR | 独立项目配置，主场景设为 G1.tscn，插件和共用素材通过相对链接连接 |
| SDF 地形 | 有 terrain.obj 和生成脚本，没有可直接运行的项目与保存主场景 | 独立项目配置，保存完整 Main.tscn、三球、地图包与参数，连接共用插件和素材 |

项目入口：[形状](../examples/shape_gallery/project.godot)、[G1](../examples/g1_passive/project.godot)、[SDF 地形](../examples/sdf_terrain/project.godot)。地形[保存的主场景](../examples/sdf_terrain/Main.tscn)由现有生成器产出，不修改碰撞表示、网格或物理参数来简化运行。

共用素材的相对链接随源码保存，统一指向 `examples/_shared/`；`addons` 链接由 `boostup.sh` 生成，指向根目录 `addons/` 并被 Git 忽略。用户无需在文件管理器中操作链接，但需要保留完整仓库结构和有效的 Linux 符号链接；单独移走一个例程文件夹仍不构成独立发布包。

自动化脚本仍保留独立输出目录，复制夹具时排除共享 addon 链接和编辑器缓存，再复制真实 addon，避免测试回写共用插件。例程 .godot 缓存加入忽略规则。

## 仍未实现的体验

| 需求 | 当前状态 |
|---|---|
| 图形化安装 native 插件 / 解压即用 | 原生库仍由构建流程生成。现有通用 setup 检查、构建与 smoke 是命令行入口；仓库不包含完整编译产物 |
| 在 MuJoCo 页签内浏览所有例程、显示缩略图并导入副本 | 尚无专用例程浏览器；本次使用 Godot 自带项目管理器，满足直接打开现有 examples 项目的需求 |
| 任选一个例程文件夹就能独立分发 | 当前共用插件和大素材依赖仓库布局。独立交付包需另行打包，不等于已有的项目入口 |
| 编译进度、安全取消、不中断界面的重型热加 | 底层仍同步编译。G1 第二台热加在既有 dot 宿主记录中仍超时，不能据单机可用宣称热加通过 |
| 对所有独立草稿拖动三维操作轴 | 正式场景节点支持 Godot 原生操作轴；MJCF / 地图独立草稿仍主要使用字段和步进按钮 |
| 轻量 C# 例程也直接打开运行 | 该开发者例程仍需生成资源与构建 C#，未纳入本次三个 GDScript 图形例程的直接运行范围 |

依据：[构建产物配置](../CMakeLists.txt)、[通用安装说明](linux-install.zh-CN.md)、[G1 实现及失败记录](../examples/g1_passive/README.md)、[C# 例程](../examples/light_workflow/README.zh-CN.md)。命令行环境向导和例程选择已通过根目录 `boostup.sh`、`em_run.sh --exp` 提供；Godot 内的图形化安装与浏览器仍未实现。

## 验证与后续优先级

[直接导入回归](../tests/example_projects/run.py)在全新临时仓库布局中保留同样的相对链接，逐一执行四个项目的首次资源导入，按 application/run/main_scene 加载默认主场景并推进真实仿真，验证形状接触、单台 G1 倒地、SDF 洼地球落到坑底及独立 MjWorld 摆杆运动。四个项目共 37 项断言通过；它不覆盖 G1 第二台热加，也不替代真实鼠标操作和画面验收。

后续若要进一步接近独立软件的体验，先提供匹配平台的原生插件及独立例程发布包，再增加例程浏览和首次使用向导；耗时编译的反馈与 G1 热加运行缺陷需要在程序层解决。仅更换 README 措辞不能实现这些能力。
