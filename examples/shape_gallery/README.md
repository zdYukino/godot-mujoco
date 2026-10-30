# 动态形状示例

这是已保存、可重开的单一 `MjRuntimeWorld` + `MjModelInstance` 示例。七个带 freejoint 的 **MuJoCo 动态刚体**和静态地板编译进同一个 PhysicsServer3D space；它们不是 Godot `RigidBody3D` 节点，也没有使用旧的独立 `MjWorld`。天空采用 Isaac Lab 示例引用的同款原作者 HDRI。地板采用原创纯色基底与固定世界间距网格，参考常见 MuJoCo 调试地板的简洁风格；没有复制 MuJoCo 原纹理，也没有包含 NVIDIA Flat Grid USD。

| 对象 | 实际 MuJoCo 碰撞类型 | 说明 |
| --- | --- | --- |
| 球 | sphere (2) | 原生球体 |
| 正方体 | box (6) | 原生盒体 |
| 圆柱 | cylinder (5) | 原生圆柱 |
| 圆锥 | mesh (7) | 原创 32 边闭合凸网格，由 MuJoCo 编译凸包；不存在原生 cone |
| 胶囊 | capsule (3) | 原生胶囊 |
| 椭球 | ellipsoid (4) | 原生椭球 |
| 额外小球 | sphere (2) | 落到盒上，验证同世界物体互碰 |
| 网格地板 | box (6) | 静态；不是动态刚体 |

不依赖尚不支持的 Godot `ConvexPolygonShape3D` 后端，也不引入动态 SDF。`nativeccd` 是 MuJoCo 的凸碰撞算法开关，不是 PhysX 连续碰撞。

## 在 Godot 中直接打开

前提：已完成[原生插件构建](../../docs/linux-install.zh-CN.md)。例程直接使用仓库中 addons 的构建产物。

1. 启动 **Godot 4.7.2 .NET 项目管理器**，点击 **导入（Import）**，选择当前仓库里的 **examples/shape_gallery/project.godot**，点击 **导入并编辑**。
2. 等待首次资源导入完成，点击 **运行项目**（F5）。主场景已经配置为 **Main.tscn**，模型包、相机、天空、地面和运行控件均已保存。
3. Tab / Shift+Tab 开关原版左右面板，Rendering / Group enable 调整运行显示。F1 帮助、F2 MuJoCo Info；Space 暂停 / 继续、Backspace 初始重置。**F11** 仅提供 Godot 渲染选择、独立 FPS/系统性能、工具和示例扩展。
4. 点击编辑器的 **停止**（F8）返回。修改场景后点击 **保存场景**（Ctrl+S），下次直接从项目管理器重开。

无需复制项目或 addons，无需运行 prepare.gd。保持完整仓库目录结构，共享插件通过相对链接连接。项目已经配置 MuJoCo 后端、编辑插件和 GL Compatibility。需要从源模型练习导入时，在右侧 **MuJoCo → MJCF 文档** 展开 **文档 / 导入 / 发布**，开启草稿显示，再点击 **Import MJCF** 选择 **assets/gallery.xml**。

编辑器继续使用 Godot 3D 视图、变换轴和右侧属性，`MuJoCo 显示` 菜单管理编辑显示。游戏使用共享 MuJoCo 相机、拾取和扰动逻辑；初始视角沿用活动场景相机，Ctrl+A 切换模型默认取景。Godot 和 MuJoCo 原生后端使用相同原版面板和快捷键；F11 仅为附加功能，显隐不会暂停。`gallery.gd` 只提供网格材质和示例说明，不再创建旧工具条。操作、后端限制见[运行查看器](../../addons/godot_mujoco/viewer/README.md)。

## 开发者：重新生成与验收

**assets/gallery.xml** 是已保存的导入资产，generate_source.py 可确定性重新生成。日常打开例程无需重建资源；需要验证源模型重新导入时，下面的隔离测试会创建独立项目、执行 prepare.gd、保存模型和场景，并验证重开，不改 examples 中的设计。

```bash
GODOT_BIN="$GODOT_BIN" OUT=/tmp/gmj-gallery-check bash tests/shape_gallery/run.sh
```

脚本分别运行仓库保存场景、重新构建后的场景、移走原始 MJCF 后的场景。每轮实际推进 600 个物理帧，并检查实际 mjModel 类型、7 个 freejoint、六个主体对共同地板的正接触力、盒与小球的正接触力、有限位置、最后半秒平移稳定、无 MuJoCo 警告，以及保存重开后的初态。也验证运行时 `scene_geometry` 与视觉材质中的真实 RGB/alpha 值（含非 1 alpha 探针），以及四种显隐组合不改物理状态、原始材质或颜色值。日志和 JSON 留在 OUT。这些物理/headless 检查不等于真实 dot GUI 最终验收；天空、线框深度与细节、窄屏操作由父任务另验。

素材来源、校验与许可见 [assets/SOURCES.md](assets/SOURCES.md)。

## 原创网格地板

`floor_grid.gdshader` 应用在原有 `floor_geom` 盒体的视觉材质上，没有额外共面 Plane、碰撞体、纹理资产或顶点位移。网格使用 Godot 世界 XZ 坐标，线位于 X/Z 为间距整数倍的位置；只有朝上表面显示，使用屏幕导数抗锯齿。物理尺寸、质量、接触参数和源 MJCF 均不变。

默认间距 **1 m**、线宽 **0.015 m**，深灰基底和低对比灰线。在 Main 场景选中 `DisplayControls`，修改 `grid_spacing_m`（0.1–10 m）和 `grid_line_width_m`（0.001–0.1 m）后保存即可。世界坐标使间距不依赖盒体 UV 或缩放；不是屏幕像素间距。地板底色继续读取 MJCF RGBA。示例脚本缓存一个 ShaderMaterial，编辑器和 runtime 重建视觉后重用它，只匹配本示例模型的 `floor_geom`，不改变通用模型渲染代码。

网格设置保留在编辑器，示例运行说明移至 F1 帮助。`tests/shape_gallery` 检查网格与物理保留、共享显示和场景重开；统一交互及 F5 后端另由 `tests/runtime_viewer/run.py`、`tests/native_view/run.py` 验证。
