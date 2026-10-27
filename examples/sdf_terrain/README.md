# 例程 3：闭合静态 SDF 地形

本例使用 **米、Y_UP、固定 seed 20261026**。三块独立封闭网格包含六级台阶、
中央洼地和固定噪声崎岖路面；底面及侧壁闭合。默认实际碰撞是 MuJoCo SDF
（mjGEOM_SDF = 8），不回退凸包。Python 标准库生成器检查退化三角形、
双面边使用、绕序及正体积。

程序化地形类别参考
[Isaac Lab 官方地形](https://isaac-sim.github.io/IsaacLab/v3.0.0/source/api/lab/isaaclab.terrains.html)；
没有安装 Isaac Sim，也未复制实现。天空和网格着色器复用形状 gallery，
天空素材来源见 gallery 的 assets/SOURCES.md。

## 在 Godot 中直接打开

前提：已完成[原生插件构建](../../docs/linux-install.zh-CN.md)。

1. 启动 **Godot 4.7.2 .NET 项目管理器**，点击 **导入（Import）**，选择当前仓库里的 **examples/sdf_terrain/project.godot**，点击 **导入并编辑**。
2. 等待首次资源导入完成，点击 **运行项目**（F5）。主场景已设为 **Main.tscn**，包含保存的地图、三颗测试球、相机、天空和显示工具条。
3. 观察三颗球分别接触台阶、洼地和崎岖路面；中央球应进入坑内，球心接近 **-0.23 m**。
4. 在运行画面勾选 **实体 / SDF 距离切片**，点击 **说明 / 帮助**。黄色轮廓是原生距离场的水平切片。
5. 点击编辑器的 **停止**（F8）返回。工具条当前没有暂停 / 重置按钮，再点击 **运行项目** 可恢复初始落球状态。

无需复制文件或执行地形生成脚本。完整 Main.tscn 和独立地图包已经保存；共享插件、天空和着色器通过仓库内相对链接连接。保持完整仓库目录结构即可。

## 通过界面重新导入和编辑地图

1. 新建 **3D 场景**，以 **Node3D** 为根，保存为 **TerrainHost.tscn**，保持这个宿主场景打开。
2. 右侧 **MuJoCo** 页签选择 **静态地图草稿**，在 **导入 / 独立包** 中点击 **浏览**，选择本项目 **assets/terrain.obj**，选择 **m、Y_UP**，点击 **导入（保留脏数据）**。
3. 在地图树逐个选择 **stairs、depression、rough**，在 **选中对象 · 基本碰撞** 中选择 **sdf**、深度 **6**，每块分别点击 **验证并应用碰撞草稿**。深度 0 使用默认，显式值允许 3..8。
4. 点击 **聚焦全图**，使用中央 3D 视图上方的 **MuJoCo 显示** 菜单查看实体和碰撞。
5. 点击 **保存独立地图包**，记下状态中的包路径。之后用 **打开地图包** 选择包内的 **manifest.json**；随例程保存的地图包位于 **models/map_…/**。
6. 点击 **Apply 到编辑场景**，宿主下会出现 **StaticMap**。点击 **保存场景**（Ctrl+S），再运行当前场景查看。地图包与宿主场景分别保存。

这条流程适合编辑自己的地图。初次查看落球演示直接运行已保存的 Main.tscn 即可。要比较凸包和 SDF，先另存宿主和地图包，将 depression 改为 **mesh**，验证、Apply、保存并停止重跑；切回 **sdf** 后再比较球能否落到坑底。

## 开发者：重新生成完整落球项目

下面的脚本用于重新生成和隔离验证，日常打开已经保存的例程不需要执行。

先按[通用安装指南](../../docs/linux-install.zh-CN.md)运行 `bash scripts/setup.sh build`。然后从仓库根目录执行，OUT 必须不存在或为空，已有项目不会被覆盖：

~~~bash
export GODOT_BIN="/absolute/path/to/Godot_v4.7.2-stable_mono_linux.x86_64"
export OUT="$(mktemp -d "${TMPDIR:-/tmp}/gmj-sdf-terrain.XXXXXX")"
bash examples/sdf_terrain/prepare.sh
"$GODOT_BIN" --path "$OUT/project" --rendering-method gl_compatibility
"$GODOT_BIN" --editor --path "$OUT/project" --rendering-method gl_compatibility res://Main.tscn
~~~

输出可独立重开的 project/Main.tscn、project/models/map_* 地图包、
project/assets/parameters.json 和 sdf_manifest.json。地图包保留自己的碰撞、
源快照及配置，原始 terrain.obj 缺失时仍能重开。只写新的 OUT。
图形会话锁屏时继续 headless 验收；不解锁、不修改显示安全设置。

编辑器保留一个原生 3D 视图及右侧 MuJoCo 地图属性。导入 terrain.obj，选择网格，
设置 sdf 与八叉树深度，点击“验证并应用碰撞草稿”，再保存独立包或 Apply
到宿主场景。支持 Undo/Redo。深度 0 保持引擎默认，显式值只允许 3..8；
超出单元/内存预算会拒绝。参数通过版本化 native snapshot 保存，不写不存在的
XML 属性。实体与 SDF 距离切片分别显示，切片是采样可视化，不冒充完整三维边界。

## 几何与验收

- 台阶：6 级，级深 0.5 m，级高 0.18 m，28 顶点/52 三角形。
- 洼地：2 × 2 m，12 × 12 单元，中央平底宽 0.9 m、底高 -0.35 m，
  外沿高 0.30 m、封闭底面 -0.60 m；338 顶点/672 三角形。
- 崎岖路面：2 × 2 m、12 × 12 单元，固定 seed；338 顶点/672 三角形。
- 默认 SDF 深度 6，三块分别编译，避免巨量单网格。
- 落球半径 0.12 m。洼地球心应接近 -0.23 m；明确标记的凸包对照接近
  +0.42 m。软接触允许小量穿透，不要求绝对零误差。
- 记录实际 mjModel 类型、正接触力、contact position/normal/geom、
  台阶独立支撑、坑底射线、显示不改查询、源离线包重开、
  真实编辑器配置/Apply/保存/另进程重开。深度 3/4/6 独立测量坑底。
- 查询不推进主仿真。已加入实际八叉树场的有界连续扫掠认证；常规及薄障碍路径通过，
  台阶棱边、斜向崎岖面和精确切触仍有未完成边界，不标为完整支持；见
  [空间查询矩阵](../../docs/development/spatial-query-matrix.md)。

~~~bash
python3 tests/spatial_queries/run.py --out /absolute/new/evidence --godot "$GODOT_BIN"
~~~

headless、编辑器逻辑和真实 GUI/截图是不同验收层级。锁屏期间不声称完成
GUI 画面验收；真实截图应来自当前被测宿主，不用历史截图替代。
