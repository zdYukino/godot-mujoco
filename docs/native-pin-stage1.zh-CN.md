# 原生 Pin 第一阶段：自由刚体软连接

基于集成提交 `2442976827fa1590de1777143ecc41cdac227025`，Linux x86_64、Godot 4.7.2 .NET / MuJoCo 3.16.0。此功能不将自由刚体重排为 MuJoCo 树式关节。

## 实际能力与参数边界

原生 Pin 使用两个独立 site 的 MuJoCo equality/connect，约束两端平移并保留旋转。A 必须为原生 body，B 可为同空间原生 body 或空 RID（世界）。至少一端为 Rigid；支持 Static 端；新增KINEMATIC明确不能作为Pin/Hinge端点，拒绝不改变旧连接。专用高度场与导入 MJCF 实例不作为端点。局部锚点分别使用各 body 坐标；世界端锚点使用世界坐标。初始不重合时由软约束逐渐拉合，不瞬移。

固定响应 `solref=".02 1"`，使用 MuJoCo 默认阻抗。它有有限约束误差，不承诺等同 GodotPhysics 的 bias/damping 求解。默认 Godot Pin 参数 bias=.3、damping=1、impulse_clamp=0 仅作为节点初始化兼容值；非默认值及非默认 solver_priority 明确报错、服务器值不变。**这些 Godot 求解参数尚未映射，不是可调支持项。** Godot 节点自身可能缓存被拒绝的 Inspector 值；以错误日志与服务器支持矩阵为准。现已另提供[受限被动 Hinge](native-hinge-passive.zh-CN.md)；limits/motor 与可调求解参数仍未实现。

只接受无环连接图。静态体与世界均作为同一固定端点处理；重复边或闭环在候选编译前拒绝，不部分改动。不是任意约束图支持声明。

## 提交、碰撞和生命周期

创建/修改连接先验证端点、锚点、图结构，在隔离模型迁移当前状态并 forward 检查有限动力学，成功后提交。失败保留旧模型、定义、碰撞排除和暂停状态。同步 API 不返回事务票据：正常调用完成后可读取服务器状态；回调内请求先进入现有 FIFO，在安全回调结束后按序执行。它不是运行模型编辑器的异步 revision API。

连接碰撞开关独立于用户 body collision exception；过滤同时覆盖显式摩擦 contact pair 和隐式 MuJoCo碰撞。清除连接不会删除用户 exception。查询过滤不把连接碰撞排除等同查询 exclude。

关节 clear 保留 RID 但变为未配置 `JOINT_TYPE_MAX`；free 释放 RID。端点删除、离开/切换 space 或改变 body mode 会清除关联连接，不能自动重绑。静态端改变 transform 后重建，局部锚点随之移动。回调中 joint 操作与 body mode/space/shape 修改复用 FIFO；执行时重新校验所有权。

自由刚体保留同名 freejoint，重建迁移 qpos/qvel，保持既有 COM 速度约定；此阶段不提供独立 equality 激活开关或运行时关节参数快照。设计由场景 PinJoint3D 保存；世界 checkpoint 是仿真状态，不撤销连接设计。

## 官方依据

- [MuJoCo 3.16 XML 参考源码](https://github.com/google-deepmind/mujoco/blob/3.16.0/doc/XMLreference.rst)：site1/site2 保留独立锚点，body/anchor 形式会推导另一端。
- [Godot 4.7.2 Jolt Pin 实现](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/jolt_physics/joints/jolt_pin_joint_3d.cpp)：默认参数兼容而拒绝自定义参数的后端先例；并非本实现数值等价性证据。

测试结果另见阶段证据；本说明不是运行通过声明。真实 GUI、保存重开须独立验收。冷导入139仍未根治。
