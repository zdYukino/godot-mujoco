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

## 运行保存的示例

先按仓库文档构建并在 `demo/addons/godot_mujoco/bin/` 放置匹配 Godot 4.7.2 .NET / MuJoCo 3.16 的扩展。下面从仓库根目录在独立工作目录运行，避免生成缓存污染示例源目录：

```bash
export GODOT_BIN=/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64
GALLERY_DIR=$(mktemp -d /tmp/gmj-gallery.XXXXXX)
cp -a examples/shape_gallery/. "$GALLERY_DIR/"
cp -a demo/addons "$GALLERY_DIR/"
bash scripts/import_headless.sh "$GALLERY_DIR"
"$GODOT_BIN" --editor --path "$GALLERY_DIR" res://Main.tscn
# 或直接运行已保存场景
"$GODOT_BIN" --path "$GALLERY_DIR"
```

编辑器保留一个原生 3D 视图；`MuJoCo 显示` 菜单独立勾选实体与碰撞网格，属性在右侧。运行场景顶部提供紧凑的实体/碰撞开关、暂停/继续、重置及“说明 / 帮助”。帮助默认收起，点击可展开，再次点击或用“收起说明”关闭；不绑定相机快捷键。打开或关闭帮助不改变物理状态，重开场景恢复默认收起。此运行 UI 由 `gallery.gd` 在 CanvasLayer 内动态创建，与编辑器右侧属性 dock 无关。切换四种显示组合不改变碰撞参与或视觉材质。橙色边线为碰撞表示，非实心替换材质。编辑真实节点使用 Godot 原生变换轴；未应用草稿仅提供可靠的右侧数值编辑，不绘制伪可拖动轴。

## 从空场景重新构建

`assets/gallery.xml` 是导入资产，`generate_source.py` 可确定性重新生成它（使用 Python 标准库）。在上述独立工作目录运行：

```bash
python3 "$GALLERY_DIR/generate_source.py"
"$GODOT_BIN" --headless --path "$GALLERY_DIR" --script res://prepare.gd
```

`prepare.gd` 导入 MJCF、保存带源快照的独立模型包，再从新的世界创建并保存 `Main.tscn`，加入 HDR 天空、相机和运行控件。保存模型的 source 使用 `res://assets/gallery.xml`，无机器绝对路径。已保存的模型包包含自身 XML 与源快照，原始 MJCF 缺失后仍可运行。重新生成会覆盖工作目录中的 `Main.tscn`；需要保留的手工改动请使用另一份工作目录。

## 验收

```bash
GODOT_BIN="$GODOT_BIN" OUT=/tmp/gmj-gallery-check bash tests/shape_gallery/run.sh
```

脚本分别运行仓库保存场景、重新构建后的场景、移走原始 MJCF 后的场景。每轮实际推进 600 个物理帧，并检查实际 mjModel 类型、7 个 freejoint、六个主体对共同地板的正接触力、盒与小球的正接触力、有限位置、最后半秒平移稳定、无 MuJoCo 警告，以及保存重开后的初态。也验证运行时 `scene_geometry` 与视觉材质中的真实 RGB/alpha 值（含非 1 alpha 探针），以及四种显隐组合不改物理状态、原始材质或颜色值。日志和 JSON 留在 OUT。这些物理/headless 检查不等于真实 dot GUI 最终验收；天空、线框深度与细节、窄屏操作由父任务另验。

素材来源、校验与许可见 [assets/SOURCES.md](assets/SOURCES.md)。

## 原创网格地板

`floor_grid.gdshader` 应用在原有 `floor_geom` 盒体的视觉材质上，没有额外共面 Plane、碰撞体、纹理资产或顶点位移。网格使用 Godot 世界 XZ 坐标，线位于 X/Z 为间距整数倍的位置；只有朝上表面显示，使用屏幕导数抗锯齿。物理尺寸、质量、接触参数和源 MJCF 均不变。

默认间距 **1 m**、线宽 **0.015 m**，深灰基底和低对比灰线。在 Main 场景选中 `DisplayControls`，修改 `grid_spacing_m`（0.1–10 m）和 `grid_line_width_m`（0.001–0.1 m）后保存即可。世界坐标使间距不依赖盒体 UV 或缩放；不是屏幕像素间距。地板底色继续读取 MJCF RGBA。示例脚本缓存一个 ShaderMaterial，编辑器和 runtime 重建视觉后重用它，只匹配本示例模型的 `floor_geom`，不改变通用模型渲染代码。

头部控制条保留必要操作，长技术说明与素材归属在本文及 SOURCES 中。自动测试验证帮助默认隐藏与重复开关、暂停/重置、四种显隐、网格配置不改几何/物理、保存重开，以及编辑器/runtime 重建后的材质复用。网格视觉、字体和窗口缩放的最终效果仍由实际 GUI 验收确认。
