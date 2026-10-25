# 普通 HeightMapShape3D 与地形摩擦

本功能分支面向 Linux x86_64、Godot **4.7.2 .NET**、MuJoCo **3.16.0**，待 dot 独立重建和图形验收。
普通 `StaticBody3D → CollisionShape3D → HeightMapShape3D` 可直接使用 MuJoCo 后端，不需要挂专用地形脚本，也不要求 MjRuntimeWorld。已有专用 `MjStaticHeightField` 的显式 Apply / revision 接口保持原语义。

## 支持边界

- 宽、深各 2..256，数据恰好 width × depth 个有限 float，范围 ±10000 米。按 Godot 原生行序：列沿 X、行沿 Z、居中、一米间隔。支持负高度、平地、非方形网格。
- 支持 body 与 CollisionShape 的平移、旋转和组合；节点及祖先必须无缩放、无镜像、无剪切。非单位缩放明确报错并保留最后有效物理姿态，不要忽略错误继续使用视觉节点的位置。间距暂固定为一米。
- 仅静态刚体；RigidBody3D、AnimatableBody3D/kinematic、Area3D 地形形状不支持，设置时明确报错。孔洞/NaN、无穷、越界高度/尺寸拒绝并保留最后有效数据。后端拒绝不会自动回写 Inspector 的无效设计，须修正后再运行。
- 普通资源编辑会触发后端 dirty，在下一物理边界重建；可改分辨率、共享资源、禁用/启用、释放。普通 Godot 编辑不使用专用地形 Apply/revision 事务。
- 普通 PackedScene/ResourceSaver 保存尺寸、高度、刚性变换、碰撞层及 PhysicsMaterial；重开重新构建。资源本身不生成可见网格；示例脚本生成匹配网格，仅作演示。
- 高度场用 MuJoCo 实体：含侧面和最低点以下一米底座；不是无限薄双面三角网格。碰撞及 ray 支持，保持 collider/RID/shape index；原有 overlap、point、continuous sweep / CharacterBody 对高度场限制未扩展，Area 监测不覆盖地形。不要将该支持解释为完整 Godot Physics 兼容。

## 在 Inspector 调节摩擦

选择 **StaticBody3D → Physics Material Override → New PhysicsMaterial**，展开资源：

- `Friction`：滑动摩擦，建议 0..1；资源 changed 信号会更新后端并重建接触参数。
- `Rough`：沿用已有原生材质组合；普通原生刚体间使用 `abs(min(signed_friction_a, signed_friction_b))`，rough 的值带负号，双方 rough 时较大摩擦优先。
- `Bounce` 必须保持 0；已有后端不支持非零反弹，会提示不支持，不能认为它已生效。滚动/扭转摩擦、solref/solimp 不在本轮入口范围。

普通原生接触对使用 condim=3；与导入 MJCF 模型接触继续采用 MuJoCo 的 geom/priority/solmix 组合，可能由对方材质决定最终摩擦，不保证等于地形单方数值。本轮不修改导入模型的材质规则。专用 `MjStaticHeightField` 现在也有 `Physics Material Override` 导出属性，复用同一种 PhysicsMaterial。其材质变更属于设计：编辑 Inspector 后保存场景；运行中先改材质，再通过既有地形面板 Apply 或 `request_apply()` 提交。Apply 入队时复制 friction/bounce，后续材质编辑保持 dirty，不修改已入队请求；成功重建后才生效。默认未赋材质仍为 friction=1、bounce=0。保存重开重新应用；错误返回 `last_error`/`edit_finished`，保持旧物理及 revision。专用节点要求 friction 为 0..1（native snapshot 用负号表示 rough），bounce 必须为 0。

专用 snapshot 的可选 `friction`/`bounce` 字段分别默认 1/0；通过节点的旧式 snapshot（包含 C# TerrainDesign）不提供这些字段时保留节点当前材质。C# 类型化数值设计本轮未增加材质字段，可通过节点 Inspector 配置。raw native 请求没有字段时使用默认值。

轻量共享世界测试同时覆盖两种地形与普通 box/MJCF sphere 的实际接触摩擦：MJCF fixture 显式设为 0.15，地形从 0.23 改为 0.67，验证两次最终值。该 fixture 不代表能覆盖任意导入 MJCF 的 priority、solmix 或显式 pair 覆盖。

## 自测与 dot 验收

```bash
cmake --build /path/to/build -j2
GODOT_BIN=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  OUT=/tmp/native-heightmap-check bash tests/native_heightmap/run.sh
GODOT_BIN=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  OUT=/tmp/dedicated-heightfield-check bash tests/heightfield/run.sh
```

runner 复制隔离项目和当前 native 库，检查正常阶段无 ERROR/leak，负例单独进程精确计数；失败日志保留，不将退出 139 视为通过。结果在 results.json、executions.tsv 与各阶段日志。无 G1 或多机器人重负载。

在 dot 重新构建后，用固定 .NET 编辑器打开生成的 project，打开 Main.tscn：选择 Terrain 的材质，将 friction 从 0.23 改到 0.67，保存、关闭再打开，确认值保留；选择 Collision 的 HeightMap 修改高度数组与尺寸，观察网格更新，保存重开；F6 观察小球落在地形并滚落边缘。专用地形 GUI 验收还需打开 tests/heightfield runner 生成的 HeightfieldDemo.tscn：选择 Terrain 的 Physics Material Override 配置/保存摩擦；运行后通过地形面板或脚本明确 Apply，再观察 revision/dirty 和完成结果。

自动脚本独立验证实际接触摩擦 0.23→0.67 和 rough 组合，并对照相同初速度盒子的零摩擦滑动与高摩擦停止，而非仅检查 Inspector 数字。运行时更改 Remote Inspector 材质，验证下一步重建；运行编辑不自动保存。不要把开发环境的 headless 自测当作 dot 图形验收。

编辑器到运行的专项入口为 `tests/heightfield_panel/run.sh`：检查面板材质草稿、Inspector 同步/冲突、Undo/Redo/保存，以及实际发送 payload 在独立运行进程中的应用与接触摩擦。48da065 候选漏发材质字段的问题已由后续修复覆盖，不能仅凭直接改 runtime node 的 96 项测试认定编辑器链路通过。
