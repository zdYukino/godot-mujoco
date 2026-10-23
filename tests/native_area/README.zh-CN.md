# Area3D 第一阶段：无冲量监测

依赖：contact 分支 `fce6d0a9245903369827926080ea412ea6be08d8`；overlap
`0bc54e2d5f365baf3388cc4dbee8b2d9f2b4442b` 无冲突 cherry-pick 为 `a5add5a`。
不包含重力/阻尼/priority 覆盖场，不修改 P0 刚体动力学。

## 支持与边界

- 原生 Area RID、object ID、space、形状列表、刚性 transform、layer/mask、monitorable；
  `Area3D.monitoring` 通过安装/清除 body/area monitor callback 控制。
- Area 与原生 Body、Area 与 Area 的 box/sphere/cylinder 配对。支持 shape 局部位置/旋转、
  多 shape、禁用、替换/移除；无缩放/剪切/镜像。Area shape 不接受 plane、heightfield、mesh 等形状。
  Body 的非上述三种形状、专用 heightfield、导入 MJCF 不纳入本阶段监测；不伪造其身份。
- 检测方 mask 与目标 layer 相交即可；目标 mask 不反向过滤。Area 目标还须 monitorable，
  但目标 monitoring 可以关闭。Body exception 是实体碰撞过滤，不用于 Area 检测。
- 每个有向 `(receiver RID, target RID/object ID, target shape, self shape)` 配对只通知一次进入和一次退出。
  Godot 自己把多个 shape 配对汇总为 body/area 节点事件及 overlapping 列表。
  原生裸 RID 未附加 object ID 时，shape 信号的对象可为 null，不生成虚假节点。
- 持续交叠不重复通知；删除/禁用 shape、mask/monitorable 变化、换 World 和资源删除产生退出。
  删除低索引 shape 时先退休所有受索引压缩影响的旧配对，再报告新索引。
  关闭 monitoring 时 Godot 自身清理列表并发出退出，backend 清除相应配对，不重复发送。
- 精确相切采用 MuJoCo 窄相的零 margin 容差，跨形状不承诺相切完全一致。检测当前固定步姿态，
  不做 sweep/CCD；一个 tick 内穿过且最终不相交可能没有通知。
- 位置/尺寸使用 Godot 米及 Y-up，转换到 MuJoCo `(x,-z,y)`；只接受有限刚性姿态。
- 本阶段 **不提供 direct-space 的 collide_with_areas 查询**，该接口仍显式 unsupported；
  ray_pickable 保存属性但不宣称 Area 可被射线拾取。

## 无副作用窄相与生命周期

Area 永远不加入活动 MuJoCo 模型，没有质量、自由度、接触约束或冲量。
独立两 primitive scratch model/data 复用 overlap 阶段相同的 dispatch/MPR 回退策略；每个 server
惰性编译一次并串行复用，只更新 scratch geom type/size/pose。完全不对 live data 调用 collision/step。
最终测试验证刚体以恒速穿越 Area 且 direct-state 接触数为 0。

普通事件在 `_flush_queries` 统一计算差分后发送；记录只保存 RID、ID、shape index，不跨回调保留指针。
Area setter 在回调中排队，整批结束后执行。Body 换 space 及所有形状列表修改（add/remove/clear/set/transform/disabled）同样排队；索引在出队时依据前序命令结果解析。队列严格 FIFO，退出回调中新追加的修改排在已有命令之后，禁止递归 drain 插队。回调内 getter 读取尚未执行修改的原状态。
free 沿用 pending-free 协议；已销毁的接收者停止收到后续事件，已释放目标的未发送 enter 被撤销。
World detach 同步退休旧配对，解除 Godot tree-entered 订阅，避免同帧重挂时虚假的 enter/exit。
此 detach 的退出回调也受 flushing/修改队列保护。

覆盖场参数可以保存供 getter 读取，但不会作用到刚体；非 DISABLED 的 gravity/linear-damp/angular-damp
覆写模式会明确告警并保持 DISABLED。priority 不参与求解。wind/softbody 不在本阶段支持范围内。
默认 space 环境路径保持原有实现。

共享改动：`MjArea` / pair cache / command queue；`_free_rid` 依赖清理；Body detach/remove/clear shape 的
监测退休钩子；`_flush_queries` 的 Area 批次及队列 drain；`_area_set/get_param` 区分真实 Area 与默认 space。
未改刚体力、积分、质量惯量、运动查询或 contact 采样算法。新增 `mj_area.cpp` 加入 CMake。

## 验证

固定 Linux Godot 4.7.2.NET / MuJoCo 3.16；源码构建：

```sh
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/contact-source -j 5
OUT=/tmp/native-area-final bash tests/native_area/run.sh
OUT=/tmp/native-area-contact-regression bash tests/native_contacts/run.sh
OUT=/tmp/native-area-overlap-regression bash tests/native_overlap/run.sh
REPEAT=1 OUT=/tmp/native-area-backend-regression bash tests/native_backend/run.sh
```

独立项目导入/正例/GUI headless smoke 均不得有 ERROR/leak；负例严格匹配 2 个预期错误
（不支持的 Area shape、非刚性 transform）及环境 override 的明确拒绝告警。

GUI（需桌面）：

```sh
godot --path /tmp/native-area-final/project --script res://gui.gd
```

蓝色透明盒是 Area；球反复穿越。每轮 enter/exit 各增加 1，内部列表数为 1、外部为 0；速度 X 恒为 2 m/s，
无反弹/停顿。关闭窗口后检查无 ERROR/leak。云环境无 DISPLAY/Xvfb，GUI 仅运行 headless smoke；
真实视觉验收交父任务，不能将 smoke 当作桌面验收。

未覆盖大负载/并发服务调用、CCD、复杂形状/MJCF、环境覆写、Area 空间查询；不做 Windows、打包、G1 重载或远端 CI 门槛。

本阶段最终实测：Area 53 passed / 0 failed（加 2 个精确拒绝 ERROR、1 个 unsupported WARNING）；
contact 48 passed；overlap 三个新进程各 154 passed；原生后端 149 passed；core smoke PASS。
全部脚本 exit 0，正例日志无 ERROR/leak。证据见 `docs/evidence/native-area/`。

### Body shape 回调顺序修复（基于 af40f02）

`body_shape_order.gd` 精确复现 `[分离 shape0, 重叠 shape1]` 在 enter 回调中
`remove_shape(0)` → `set_shape_disabled(0,true)` 的索引压缩路径，并覆盖 remove→set/transform/disabled、
clear→add→set/transform/disabled、add→set/transform/disabled，以及 remove 触发的退出回调追加修改。
旧产物 22 项中 9 项失败（含错误重入和被 clear 清空的即时 add）；修复后 22/22 通过。
原有 Area 53 项、contact 48 项、原生后端 149 项亦通过；正例日志无 ERROR/leak。
本修复没有修改 query/witness；顺序 API 请求不等同于非法请求的事务回滚。
证据：`docs/evidence/native-area-body-shape-order/`。
