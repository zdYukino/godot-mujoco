# 原生 Hinge：受限被动阶段（历史阶段说明）

后续[独立 Hinge 限位与速度电机](native-hinge-drive.zh-CN.md)已新增有界实现；本页以下未实现项描述被动阶段当时的边界，不替代当前能力矩阵。

继承原生 Pin 的 free-body、forest、candidate验证和生命周期契约。支持两个原生自由刚体，或自由刚体连接世界/静态体的被动转轴。Godot hinge frame 的局部 Z 为轴，origin 为锚点；simple API 的轴归一化。初始世界轴必须近似平行或反平行（abs(dot)>=.9999），反平行时内部翻转 B 轴；斜交初始轴明确拒绝，保留旧连接。frame 必须无缩放、剪切和镜像。

实现为两组独立 site equality/connect：第一点是锚点，第二点是沿轴 **1 米** 的辅助点；两者均 `solref=.02 1`、默认阻抗。辅助点必须能在 float 坐标中表示，否则拒绝。它保留轴向旋转，约束平移和非轴向旋转，但属于有柔度的冗余约束，不是 MuJoCo 标量 hinge，也不是 GodotPhysics 参数等价求解器。间距是物理响应的一部分，不可隐藏为无关实现细节。

## 尚未完成

**limits 与 motor 均未实现。** enable=true 明确报错且服务器flag仍false；自定义 response/limit/motor 参数同样拒绝。官方 HingeJoint3D 的八项默认参数仅用于节点初始化兼容，不声明这些参数已实现。节点自身 Inspector 可能缓存拒绝值；须查看服务器flag与错误日志。

- 不能通过直接钳制姿态伪装限位，这会破坏速度/反作用/能量和回滚语义。
- 两connect没有标量角度qpos。MuJoCo equality/joint只能耦合已有scalar joints，不能直接给当前两freebody实现角度限位。
- Godot固定实现 motor以角冲量钳制，MuJoCo actuator force range是力/力矩；直接照抄数值不是正确映射。
- 下一方案需要选择原生树式关节加统一状态投影，或具备可验证角度、冲量预算及反作用的独立约束路径。前者需改写当前freejoint读写/状态迁移，后者不能仅凭被动实验声称可靠。未声称这些功能不可能，只是本阶段没有实现。

Pin/Hinge组成的连接图仍只支持forest；静态端和world合并为固定端，无闭环/重复边。collision exclusion、clear/free、端点移除/space或mode变化清连接、暂停和重建与Pin一致。保存的是场景设计，checkpoint不撤销关节设计。

## 可复现实验与验证门槛

`docs/evidence/native-hinge-passive/feasibility/` 留存官方MuJoCo3.16公开API小实验。球体1kg/r=.2，轴向.01Nm、1s得到world .625rad/s、双body相对1.25rad/s，符合惯量；spacing .1→1使横向柔度约下降百倍，说明不能承诺与任意硬hinge等价。实验使用±spacing/2站点，插件使用anchor与anchor+axis，软约束耦合不同，不能将实验横向误差直接当插件验收值。实验没有Godot生命周期，不替代实际插件回归。

插件测试独立覆盖轴向/横向、旋转frame与偏置、双body、非法输入/enable拒绝和保存重开。具体执行与未测边界见阶段证据。真实GUI仍待dot；大质量比、长时大载荷、全时间步矩阵未验证。完整limits/motor必须另有数值、反作用、暂停/子步和非法原子拒绝测试才可标完成。
