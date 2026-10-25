> 本文保留地图 P0–P3 阶段的历史范围。后续本地碰撞候选已新增无插件 SDF/MJCF 路径，见 [原生碰撞候选](native-collision.zh-CN.md)；下文“未接入/拒绝 SDF”仅指 P0–P3 基线，不代表当前候选。

# 静态地图导入/查看：P0–P3 开发候选

本轮依赖 **PR #17 精确 310d2a425b131e6a0c25cb0204f3f8d322b264bd**，在功能分支组合 main 文档 dc8ff7c。没有合并远端 main 或 PR #17。固定 Godot **4.7.2 .NET**、MuJoCo **3.16.0**。

这是开发候选，**尚待父任务在实际 dot 重新构建及 GUI 验收**。新提出的“SDF 默认候选”只有原生可行性探针通过，尚未接入 Godot 地图运行链路；按用户最新顺序，全面碰撞选择/SDF 接入排在本任务之后，不作为本轮原计划验收门。P4 UE 暂缓。

## P0/P1：输入、来源与查看

启用 `mujoco_editor` 插件，打开底部「静态地图」：选择文件、显式选择 m/cm/mm、确认右手 Y_UP 或 Z_UP，然后导入。转换保留在 SourceCoordinates 节点及 contract 元数据；内部为右手 Y-up、米。未知单位拒绝，不猜测。

- GLB/glTF 2：直接 GLTFDocument 解析；保留静态层级、变换、受支持 PBR 材质。兼容编辑器产生的 ImporterMeshInstance3D，规范化为 MeshInstance3D。动画只取初始姿态并诊断；蒙皮、morph 明确拒绝。外部 buffer/图片缺失不替换旧地图。不读取网络 URI。
- OBJ/MTL：显式适配，支持三角面、正/负索引、对象/组、UV、法线、Kd/map_Kd。**必须预先三角化**，不猜测凹多边形分割。缺 MTL/贴图保留几何并列出诊断；不支持的材质属性明确提示。
- STL：显式 ASCII/二进制适配，几何-only；不宣称 Godot 原生支持，不臆造材质、层级或单位。
- 右键轨道、中键平移、滚轮缩放、聚焦全图/选中；节点树与三维三角面拾取联动，显隐不改源资产。显示网格/三角形/材质数量、世界包围盒/尺寸、源单位；绿色框与坐标方向线、橙色碰撞线框独立开关。
- 查看设置随包保存。包内相机也支持轨道/平移/缩放。资源诊断与碰撞配置分开；**导入或生成成功不会标为物理验证通过**。

来源追踪按内容 SHA256，不依赖 mtime。地图监视源几何及已发现的 MTL/贴图/buffer；MJCF 面板监视主 XML、递归 includes 和原生资产 manifest 中的 mesh/texture。每两秒检查，显示已对齐/源已变/本地脏/冲突/解析失败。

MJCF 「重导入来源」有明确确认；在独立候选中解析、编译、检查依赖后才替换当前文档，失败保留旧文档/待编辑字段。运行实例仍走现有显式 Apply。可保留本地并另存 `.gmj.json`。规范化导出复用 `Save project model`：include 展平的 `model.xml`、内容哈希资源与相对 assets；记录导入来源哈希和导出哈希。**不回写原 XML/include，不承诺注释/格式保真，不实现任意 include 原位实时双向同步。**

## P2：已验证路线与限制

当前导入默认是 **visual / 仅视觉**，随后显式选择碰撞。SDF 显示为未接入的禁用选项；“默认 SDF”目标尚未交付，不静默回退凸包。

- Box / Sphere / Cylinder / Capsule：手动选择支持的原生基础形状。由本地包围盒拟合；旋转/缩放烘焙到形状尺寸与无缩放刚性姿态。镜像、剪切、零厚度、非有限尺寸、球非等径、圆柱非等径等明确拒绝。
- `compound_boxes`：输入局部坐标 JSON `[{"center":[x,y,z],"size":[sx,sy,sz]}, ...]`，1..256 个 box。带门洞房间与楼梯实测采用这条路线，保留空洞，**不是自动凸分解**。普通整栋单 mesh 凸包会封住凹空间，不作为成功路线。
- 碰撞层/掩码、0..1 摩擦保存。线框显示实际生成形状；顶点到候选体表面最大采样距离是局部误差指标，**不是 Hausdorff 距离或碰撞正确性证明**。拒绝对象保持树选择，可聚焦定位。
- 高度输入通过 JSON 契约，支持 `float32_le` RAW、数值 JSON、明确指定缩放/偏移的原始 8-bit 灰度 PNG。PNG16/RGB 明确拒绝，避免隐式降精度。宽/深 2..256，行优先 +Z、X 最快；当前原生 HeightField **间距固定 1 m**。其他间距拒绝并要求外部显式重采样；不悄悄改变几何。不支持洞穴、悬空多层、洞/NaN。

高度契约示例：

```json
{"file":"ramp.raw","width":3,"depth":2,"spacing_x":1,"spacing_z":1,"unit":"m","row_order":"increasing_z","encoding":"float32_le"}
```

`png_u8` 另需 `height_scale`/`height_offset`，解码高度 = 灰度归一化值 × scale + offset，再换算米。`json_metres` 为历史编码名，仍按显式 unit 换算。

## P3：事务与可搬迁包

碰撞/摩擦草稿有 Undo/Redo；「Apply 到编辑场景」通过 EditorUndoRedoManager 一次替换地图，重复 Apply 不累加副本，Undo 恢复旧节点及其材质身份。地形生成使用已验收 `MjStaticHeightField`，保存独立 PhysicsMaterial，运行的地形修改仍复用地形面板的 revision/queue/失败回滚语义。原生普通对象摩擦混合与地形一致：normal 取较小值，rough 取较大值；MJCF 默认 max/priority 仍是另一条规则，不混为同一规则。

**整幅普通原生地图没有新的跨对象运行热更新事务**：Apply 只改编辑场景，运行地图需显式重新运行；地形运行 Apply 和现有 MJCF 运行 Apply 保留。这是当前明确限制。动态地图和运行时整体移动不在范围内。

保存到 `res://static_maps/map_<manifest SHA256>/`：

- `map.tscn`：视觉层级/变换、嵌入网格/材质/图片、原生碰撞、HeightField 设计/材质、相机、单位坐标元数据、原始来源哈希与诊断。
- `manifest.json`：内容哈希、来源、版本和后端契约。包仍需要目标项目安装同版本 `godot_mujoco` addon；不携带/复制引擎二进制。
- 此路线使用 Godot 原生基础体/HeightField，无额外 MJCF collision 资产需求；已有 MJCF 安全副本另由 portable builder 输出 XML/assets/model.tres。

视觉纹理转为嵌入 ImageTexture；脚本保持安装 addon 的稳定引用，不能用 BUNDLE_RESOURCES 将 class_name 脚本内联。包先在 staging 保存、验证依赖/哈希、重新实例化，再原子 rename 发布，不覆盖已有内容地址目录。失败清理 staging，旧包保留。缺包文件和哈希损坏明确诊断。原输入只读，删除原输入后查看/物理运行不依赖原路径；只有显式重导入仍需来源。

## SDF 可行性门（独立于已交付地图路线）

`tests/static_map/run_sdf_probe.sh` 对本机确切 3.16.0 分发运行：

- 官方 `cow.xml`：cow1/cow2 的 `type=sdf`、`geom_plugin=-1` 编译运行，示例里的 torus 使用官方 libsdf_plugin。
- 同一多部件门洞房间 OBJ：无自定义插件的单网格 SDF，球穿门、墙阻挡；对照 `type=mesh` 凸包封门，runner 要求该对照以 3 退出。
- 记录编译/运行 wall 与 CPU 时间、构建/总峰值 RSS、八叉树单元和接触数。**没有从 PhysX 移植 GPU 要求或参数；不是求解器切换。**

本机单次房间 SDF：构建约 145 ms，750 步约 455 ms，构建峰值 RSS 约 65.6 MiB，82,553 八叉树单元。普通凸包约 1.55 ms / 2.11 ms、5.1 MiB，但几何语义错误。进程峰值含模型、库、数据，不能当纯资产内存；并行宿主和模型结构会影响成本。不能据此承诺大建筑性能。

尚缺：SDF 在 Godot 编辑器/运行文档中的受控接入、可视化/碰撞预览、包中派生 SDF/网格资产、默认候选失败状态、对应事务/迁移/GUI 验收。当前 `MjEditorDocument` 对 SDF 的拒绝保持不变。

## 开发与 dot 验收

```bash
# 按仓库已有配置重建，MuJoCo 必须为 3.16.0
cmake --build <build-directory> -j 4
GODOT_BIN=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  OUT=/tmp/static-map-dot bash tests/static_map/run.sh
GODOT_BIN=/path/to/Godot_v4.7.2-stable_mono_linux.x86_64 \
  GUI=1 OUT=/tmp/static-map-dot-gui bash tests/static_map/run_editor.sh
MUJOCO_ROOT=/path/to/mujoco-3.16.0 OUT=/tmp/static-map-dot-sdf \
  bash tests/static_map/run_sdf_probe.sh
# 轻量既有回归，不运行含 G1 的 run_runtime.sh
GODOT_BIN=/path/to/godot bash tests/portable_runtime/run_assets.sh
GODOT_BIN=/path/to/godot bash tests/heightfield_panel/run.sh
```

GUI runner 在真实显示上触发编辑器导入、选取、显隐、碰撞草稿、保存重开、场景 Apply/Undo/Redo。还需父任务人工确认视口渲染、输入手感、线框与门洞视觉、重开后的真实运行。无显示的开发环境使用 headless 编辑器自测；headless 的场景保存通过 PackedScene，避开 Dummy renderer 无法生成相机缩略图的问题，**不替代 GUI Save 验收**。所有 runner 仅小型几何/刚体，不使用 G1 或多机器人。

## dot 审查后的 P0/格式窄修复

初版 e6db312 未通过总体 dot 审查：原 Import 可覆盖已 Apply 的 dirty 文档，来源哈希没有跟随 Undo/Redo。失败先行回归实际复现 6 个失败。现统一普通 Import、专用 reload、文档/模型打开入口的 dirty/pending 保护；只有明确确认丢弃的调用可覆盖。文档和来源身份/哈希/导出版本统一保存在 editor_state 快照中，Undo/Redo 同步恢复。Undo 后保存旧文档也不会把新来源错误标为已对齐。

MJCF 首次编译只用于发现依赖；在哈希记录前后第二次编译候选并比较完整依赖集合/内容，期间变化则拒绝。地图适配器提交前复核解析时哈希与记录哈希一致。此为乐观稳定读取检查，**不是操作系统级原子文件快照**，不能保证检测读取过程中瞬时改变再恢复的 ABA 情况；原文件始终只读。

高度契约 JSON 文件本身纳入来源依赖；JSON 解析得到的合法整数值 float 宽深转换为 int，严格拒绝小数/非有限/越界。RAW/契约读取前后比较哈希。ASCII STL 支持空格、Tab 和 CRLF。glTF 临时导入树在转换前清除旧 owner，完成后统一设置规范所有者。

地图包打开在加载资源前检查实际外部 Script 引用、文件存在、允许的 addon 脚本与 Visual/Physics 结构，拒绝内联脚本；实例化后再次检查必需节点/元数据，失败保留旧视图，不无保护 get_node。它只接受本工具的原生包子集，不是任意 Godot 场景导入器。

修复后开发自测：核心 78/0、重开 8/0、迁移 8/0、依赖/结构诊断 6/0；编辑器 45/0（来源事务 20/0），既有编辑器 160/0。摩擦试验现使用地图 Session 配置→Package 保存→重新加载→实际刚体接触，替代原先手建静态体路径。以上仍需父任务在实际 dot 对修复提交独立复验。
