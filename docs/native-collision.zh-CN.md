# MuJoCo 3.16 原生碰撞属性化候选

基线 `63c8841b7c4169f4a607eeb084a29553ea04100a`；首轮候选 `52867e4` 已保留。本文记录其后补齐的本地候选，**待父任务实际 dot 源码构建与 GUI 验收**。未推送、未 PR、未发布、未合并。HTML 保留已获取 main 的规划及地图验收记录，只更新碰撞阶段证据；P4 UE 暂缓。

## C0：精确版本、表示和配对

`mjVERSION_HEADER=3016000`，运行库 `3.16.0`。运行库全部 45 个无序配对中，只有 plane–plane、plane–hfield、hfield–hfield 无函数；其余有分发函数不代表任意资产、速度或组合可靠。`tests/native_collision/run_matrix.sh` 可复核。

| geom | 地图 UI 与实际路线 | 本地接触证据 |
|---|---|---|
| plane | 网格 AABB 中心的无限 +Y 平面，MJCF | 球落地 |
| hfield | 专用高度契约入口；普通网格不可直接选。原路径或显式原生接触 MJCF | 固定间距地形；新原生材质接触、保存重开 |
| sphere/capsule/cylinder/box | 默认保留原 Godot Shape；勾选“显式使用 MuJoCo 接触”后走 MJCF | 六基础几何对球；四类新增原生摩擦/优先级实际生效 |
| ellipsoid | 缩放后 AABB 三半轴，MJCF | 球接触、非对称层级缩放位置 |
| mesh | 内嵌顶点 MJCF，**凸包**碰撞 | 房间对照封门；真实编译凸包预览封门 |
| sdf | 内嵌网格、无插件 MJCF | sphere/box/capsule/mesh 穿门与目标墙阻挡；命名目标接触、法线、正法向力 |

`capability` 保存 schema、engine_version、requested_mode、actual_mode、status、reason、adapter；来源哈希、生成 XML hash 和 pose 单独保存。状态 `configured_unverified` 表示仍需该场景验收。失败尝试显示 disabled/reason 并保留之前有效配置与 Undo，不静默转凸包。普通静态地图不会因此获得完整 PhysicsServer 凸/凹 Shape 或查询兼容性。

nativeccd、multiccd 均默认开启；3.16 中分别以 `mjDSBL_NATIVECCD=1<<17`、`mjDSBL_MULTICCD=1<<19` 关闭。CCD 指 convex，不是 continuous。专用几何配对自动分发，不能强制所有形状使用统一 GJK。外部凸分解、flex/IPC 不是刚体碰撞下拉算法。插件实例在编译前拒绝，不加载任意外部库。

官方参考：[XML option](https://mujoco.readthedocs.io/en/stable/XMLreference.html#option)、[碰撞检测](https://mujoco.readthedocs.io/en/stable/computation/index.html#collision-detection)。距离切片调用固定发行版公开 `mjc_distance`，读取编译后的原生八叉树。

## C1：九类对象的属性与资产

`compound_boxes` 是保留的 Godot 组合工具，不是第十类原生 geom；原生接触勾选禁用，API 与已保存配置构建均拒绝 `native_contact=true`，不静默忽略参数。

旧基础体/hfield 默认继续使用 Godot PhysicsMaterial `[0,1]`/rough。**显式勾选**才用 MuJoCo 接触参数，不改变旧资产语义。新四类本来就走 MJCF。JSON 可配置 friction 三分量（非负、允许大于 1）、condim 1/3/4/6、priority、solmix、solref、solimp、margin、gap。原生过滤位仅 0..2147483647，最高位明确拒绝，不截断；旧 Shape uint32 语义保留。

单位、层级缩放烘焙进形状/网格，刚性 pose 单独保存；拒绝镜像、剪切和非有限数。mesh 至多 20000 三角形。hfield 保持 2..256、固定 1 m 间距、有限高度、静态刚性变换；新生成 snapshot 路线只接收内嵌 elevation（通用文件 import_file 仍拒绝 hfield，保持旧入口边界），不声称新增任意外部高度资产包适配。

SDF 是**按需验证候选**，导入保持仅视觉，不自动烘焙。产品准入预算（不是 MuJoCo 的原生硬限制）：

- 至多 2000 三角形；焊接边相反绕序平衡；闭合部件有正确有向体积。
- 部件 AABB 最小厚度至少 2 cm、最大跨度不超过 100 m；拒绝检测到的非相邻面自交、自折叠/反向体积、开口、退化面。
- 自交检查至多 200000 个候选对；允许闭合部件之间的相交组合（房间样例），不把这种检查声称为完整网格拓扑证明。
- 编译结果最多 500000 八叉树单元、64 MiB model buffer。此项是**编译后准入检查**，不是进程硬内存沙箱。窄局部特征不一定等于部件 AABB 厚度，仍需切片与实际接触验证。

薄于 2 cm、自交拒绝等输入保留旧地图，给出用户可选基础体/凸包/显式分块，不自动改表示。已有房间测试的 0.2 m 墙、0.2 m 球、2 m/s、0.002 s 步长不能推广为任意薄壁/高速安全保证。

## C2：真实碰撞预览和持久化

基础 Shape 使用实际形状 debug mesh，高度场使用与后端同采样及单元对角线的网格；原生基础体为解析边界绘制（无限 plane 仅画有限显示区域）。mesh 使用 `mesh_poly*` 编译凸包多边形，**不是源三角面**。

SDF 使用 65×65 原生有符号距离切片：红色内部、蓝色外部、黄色线性插值零轮廓；高度比例可调并保存。它是有限分辨率切片，不是完整高精度 3D 等值面。测试直接检查墙内距离为负、门洞距离为正和零轮廓存在。公开采样接口限定 3..129，不接受无界分辨率。

对象/世界/关系配置分别持久化，原子草稿拒绝、Undo/Redo、场景资源身份 Undo、来源同步和包完整性保留。地图包使用内嵌网格/高度数据，移除原输入后仍可运行；`map_contact_relations`、`map_world_settings`、原生 snapshots 均包含在场景哈希保护内。

## 世界设置、显式 pair/exclude

单独世界 JSON：solver Newton/CG/PGS、cone pyramidal/elliptic、jacobian；nativeccd/multiccd/midphase/filterparent/warmstart/island/override；iterations/ccd_iterations/sdf_iterations/sdf_initpoints/noslip_iterations/ls_iterations、tolerance/ccd_tolerance/noslip_tolerance/ls_tolerance、impratio；contact override 的 o_friction(5)、o_solref(2)、o_solimp(5)、o_margin。

真实 UI `JSON.parse_string` 的整值 float 接受后规范化成 int；小数、字符串、NaN/Inf 拒绝。迭代数支持 0..1000（上限是产品预算），0 迭代/0 容差保留其原生含义；noslip_iterations=0 关闭 noslip。容差允许 0，impratio 必须正；通用数值上限 100 是产品约束。空配置保留默认，项目 timestep 仍 0.002。已有 MjRuntimeWorld 保持权威，原生模型以既有全量 option conflict 检查拒绝不一致。

独立关系 JSON 的 `pairs`/`excludes` 使用面板显示的节点路径 `first`/`second`，仅作用于**地图内两个显式原生接触对象**，不猜测外部机器人/实例名称。pair 支持 friction 五分量、condim、solref/solimp、margin/gap；exclude 指定两个 body。生成单个原生集合保证引用随包移动、重命名内部前缀后仍有效。错误端点或旧 Shape 端点明确拒绝并保持旧关系。关系存在时，单对象编辑（包括 visual、关闭原生接触、切换几何类型）与高度场原生接触编辑会在创建 Undo action 前校验完整候选场景。失败恢复原容器/资源身份，保留关系、Undo 版本、dirty 与导出记录。plane–plane、plane–hfield、hfield–hfield 显式 pair 无分发函数，产品明确拒绝，不依赖编译器拒绝；对应 exclude 仍合法。静态地图 exclude 的动态效果有限：本轮验证编译排除表和无接触，未声称跨机器人运行实例的排除管理已实现。

示例：`{"pairs":[{"first":"SourceCoordinates/OBJ/Object","second":"SourceCoordinates/OBJ/Other","condim":4,"friction":[0.7,0.7,0.02,0.001,0.001]}]}`。pair 与 exclude 同时指定同一对时保留 MuJoCo 原生规则，不额外伪造优先级。

## C3/C4：测试、成本与交验

产品 runner：基础 51 项、扩展 30 项、属性/关系 42 项，关系端点事务/不支持配对/UI 窄回归 67 项；迁移后独立进程复验 SDF 目标墙法线/力、CG/elliptic/disable 位、原生摩擦/priority、JSON 世界设置、hfield 接触和 pair 表。扩展测试通过**实际面板 JSON parse→按钮 apply→mjModel.opt**，不以 GDScript literal 替代入口。

材质测试包括 priority=3 的摩擦 1.6、hfield 1.8；同 priority 下 solmix=3 对默认 solmix=1 得到实际 contact solref=.035；世界 override 摩擦 .3 覆盖对象值；显式 pair 产生实际 condim=4/friction=.7 接触。原地图回归 78+8+8+6、headless 编辑器集成 46 项继续通过。`scene_info.runtime_options` 直接读取最终 `mjModel.opt`；`authored_option_values` 为配置缓存，旧 `options` 仅保留兼容别名并标注来源，不能作为运行证据。`scene_geometry` 的参数直接读取最终 geom 数组。`scene_info.contact_details` 提供双方 geom/body、法线、接触坐标系六分量力、solref/solimp、condim、五分量摩擦。

同一门洞、3 次独立进程、每次 750 步的开发机测量（各统计的试验间中位数）：

| 表示 | 编译 ms | step 平均 μs | step P50/P95 μs | 进程峰值 KiB | model buffer bytes |
|---|---:|---:|---:|---:|---:|
| SDF | 142.551 | 668.422 | 589.460 / 1608.924 | 67428 | 12248175 |
| 单凸包 | 1.576 | 3.025 | 2.194 / 5.159 | 10240 | 30255 |
| 多 box 组合 | .885 | 2.320 | 2.074 / 3.707 | 10240 | 13871 |

凸包封门，几何不等价；组合保留门洞。RSS 含整个进程，data buffer 另记且不等于完整 arena；不是通用速度基准。父任务实际 dot 的独立单样本 SDF 246.7 ms 编译/750 步 425.1 ms/RSS 约69 MB，进一步说明宿主差异与 SDF 成本。当前预算不是“低成本”保证，也不据此自动开启所有资产。

```bash
# 先使用本环境原有构建命令编译扩展
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 4
MUJOCO_ROOT=/path/to/mujoco-3.16.0 bash tests/native_collision/run_matrix.sh
MUJOCO_ROOT=/path/to/mujoco-3.16.0 bash tests/native_collision/run_cost.sh
GODOT_BIN=/path/to/godot bash tests/native_collision/run.sh
GODOT_BIN=/path/to/godot bash tests/static_map/run.sh
GODOT_BIN=/path/to/godot bash tests/static_map/run_editor.sh
```

HTML C3 仍是正确性/成本，C4 是门控；世界设置保持独立子节点。所有新增能力仍待父任务实际 dot 最终验收，不将有分发函数标成全配对可靠，不将本地 headless 自测标成 GUI 验收。

地图面板采用自动换行说明、可滚动流程区和窄 dock 上下排列预览；保存、Apply 与原生接触入口保留。布局 runner 在 1180×812、900×500、640×400、420×360、320×240 测量全部 31 个流程控件，逐个滚动后验证完整边界位于视口内，不发送按钮信号。该结果是 headless 布局可达性证据，实际鼠标 GUI 验收仍由父任务完成。

JSON 整数入口复核：对象/高度场 `condim`（1/3/4/6）、`priority`（-2147483648..2147483647，signed int32）以及 pair `condim` 均先校验有限整值和范围，再转 int 和检查枚举；不截断 3.9。世界迭代字段沿用 0..1000 产品预算。过滤位接受整值 JSON 数但保留原生 MJCF 0..2147483647、旧 Godot 0..4294967295 的不同范围。对象、地形与 pair 草稿保存规范化 int。exclude 只接受两个节点路径字符串，无数字索引或接触整数属性；不将数字转成路径。高度契约 width/depth 已按 2..256 有限整值规范化，组合 JSON 的坐标/尺寸为连续数值，未新增整数转换。

回归通过真实面板接触 JSON 输入及最终 geom 读取，SDF 三摩擦/condim/priority 与 pair 配置经 JSON.parse_string 后保存，独立重开进程验证目标墙力/法线/摩擦和 pair 的实际 condim/friction。小数、字符串、NaN/Inf、超范围和 exclude 非法字段均拒绝并保留旧状态；这仍不替代父任务实际 dot 鼠标复验。
