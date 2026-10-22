# 原生接触报告阶段

基线：8d3976e1d0fb71588b9b303d6c202708d6737bbe。仅现有原生 StaticBody3D / RigidBody3D、原生形状及与导入刚性 geom 的接触；不增加 CCD、sleep、深度阈值、debug contacts、Area 或 soft-body 支持。

## 报告契约

- `max_contacts_reported` 非负，默认 0。降低容量立即截断；0 禁用。负数拒绝，保留原值。
- 每个 Godot tick 清空报告。只报告该 tick **最后实际执行子步**的求解接触（`efc_address >= 0`），在 `mj_forward` 刷新前复制。不累计中间子步接触，因此短暂冲击可能不出现；无子步、暂停或 inactive 时没有新报告。
- 保留最后子步每个流形点，不按 Body 合并；采用 MuJoCo 接触顺序，达到容量后截断。多点同一碰撞方由 Godot 的 contact monitor 汇总进入/退出信号。改变容量可能造成监测对象退出。
- 所有向量使用 Godot Y-up 世界坐标，米、米/秒。`local` 表示报告的当前 Body，不表示 Body 局部坐标。双方位置均为 MuJoCo 接触中点（不提供各自表面投影点）；法线朝向当前 Body。法线与力统一 `(x,y,z)_MJ -> (x,z,-y)_Godot`。
- 冲量为最后子步 `mj_contactForce` 的法向及两个切向分量经接触 frame 转换后乘该子步 dt，单位 N·s，方向为施加到当前 Body 的方向。它不是整 Godot tick 的积分冲量；滚动/扭转力矩没有塞进线性冲量。
- point velocity 用 MuJoCo 世界 COM 线速度 + 角速度叉乘接触点到 COM 偏移。shape index 来自原生 `geom_owners`，不是 MuJoCo geom 编号。
- 导入模型没有原生 Body RID：其接触仍有位置、法线、冲量、速度，但 collider RID 为空、object ID=0、object=null、collider shape=-1。绝不返回模型实例 RID 冒充 Body；`contact_monitor` 不把它列为碰撞节点。
- 快照无 MuJoCo 指针。tick 开始、空间 dirty、成功 rebuild、Body 移动空间/删除和空间删除清除旧数据；回调期间 deferred free 提前清除关联报告，包括共享 shape RID 的所有 owner 和引用这些 owner 的 peer。对象由 ObjectDB 即时解析，getter 不触发 rebuild。越界 getter 返回零向量/空身份/-1。

共享接口改动：`MjBody` 增加容量/值快照；server 增加 `collect_contacts`；`dirty`、`rebuild`、`_free_rid`、`_step` 增加缓存失效/采样。force/query 算法未改；集成任务合并这些共享位置时须保留接触采样位于最终 `mj_step` 后、`mj_forward` 前。

## 自动验证

```sh
source /workspace/shared/tools/env.sh
cmake -S . -B /workspace/shared/builds/contact-source \
  -DGMJ_BUILD_MUJOCO_FROM_SOURCE=ON -DGMJ_BUILD_CORE_SMOKE=ON -DCMAKE_BUILD_TYPE=Release
cmake --build /workspace/shared/builds/contact-source -j 5
OUT=/tmp/contact-source-check bash tests/native_contacts/run.sh
```

脚本独立复制项目及刚构建 addon，导入和运行均超时保护；`executions.tsv` 保存各实际阶段退出码，`results.json` 保存扩展 SHA256；任意非预期 ERROR 或 leak 均失败。覆盖静态地面四点流形、刚体对撞相反冲量、每个 getter、容量即时截断与越界 getter、真实 contact_monitor（允许真实接触分离/重接触，检查当前列表与进入/退出计数平衡）、多个 shape、exceptions、mask、删除、跨 World、sync callback 内 Body/Shape RID free 后的立即快照失效、旋转偏移 COM 的切向接触速度和导入 geom 身份边界。旋转偏移 COM 速度测试只比较切向分量，因为快照采样于最后子步的求解状态，法向加速度更新与随后 direct state 读取不在同一时刻。使用 Linux Godot 4.7.2.NET / MuJoCo 3.16。

## GUI 步骤（需有桌面）

运行自动验证生成独立目录后：

```sh
godot --path /tmp/contact-source-check/project --script res://gui.gd
```

观察方块落地后 4 个红色接触点、`contacts: 4`、`monitored bodies: 1`。按空格重新落体，升空时计数归零，落地恢复。关闭窗口，确认日志无 ERROR/leak。此 GUI 步骤未在无 DISPLAY/Xvfb 的云端环境执行，不能视为真实 GUI 验收。

未覆盖：RK4 等非默认积分器的量化误差、巨大容量/负载、CCD/短暂中间子步碰撞、导入 flex/softbody、用户自定义删除回调的所有组合；不做 Windows、打包、G1 重载或远端 CI。

集成修正：Godot 原生刚体 linear_velocity 采用质心世界速度，MuJoCo free-joint 平移速度采用 body 原点速度；read/write、阻尼及预设候选迁移均显式转换。旋转偏心质心的接触点切向速度由数值回归验证，不能只验证中心对称形状。
