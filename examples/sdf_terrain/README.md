# 例程 3：闭合静态 SDF 地形

本例使用 **米、Y_UP、固定 seed 20261026**。三块独立封闭网格包含六级台阶、
中央洼地和固定噪声崎岖路面；底面及侧壁闭合。默认实际碰撞是 MuJoCo SDF
（mjGEOM_SDF = 8），不回退凸包。Python 标准库生成器检查退化三角形、
双面边使用、绕序及正体积。

程序化地形类别参考
[Isaac Lab 官方地形](https://isaac-sim.github.io/IsaacLab/v3.0.0/source/api/lab/isaaclab.terrains.html)；
没有安装 Isaac Sim，也未复制实现。天空和网格着色器复用形状 gallery，
天空素材来源见 gallery 的 assets/SOURCES.md。

## 保存独立项目并运行

在 GTR 仓库根目录执行，OUT 必须是新路径，已有项目不会被覆盖：

~~~bash
. ~/.config/godot-mujoco/gtr-env.sh
export OUT="$HOME/workspace/sdf-terrain-example-$(date -u +%Y%m%dT%H%M%SZ)"
bash examples/sdf_terrain/prepare.sh
"$GODOT_BIN" --path "$OUT/project"
"$GODOT_BIN" --editor --path "$OUT/project" res://Main.tscn
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
GUI 画面验收，不用旧云端截图替代 GTR 截图。
