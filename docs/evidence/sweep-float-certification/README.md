# Float sweep bracket 修复

父任务提供的普通旋转 box 最小复现：sphere radius .37，box half(.73,1.13,.91)，
body origin(2.3,-1.7,4.1)，local basis Euler(.17,-.26,.33)，local origin(.4,.8,-.6)，
目标沿 local X 加4，query从local(-5,.2,-.1)沿X运动12，margin0。
解析面接触 TOI (9-.73-.37)/12 = .6583333333。旧版返回空。

原因：float fraction 与 Vector3 乘加独立舍入，只对 fraction 向外移动1ULP不能保证实际
Godot位置在要求的接触侧。不是不支持形状，也不是退化切触。

修复在连续解已经找到首次接触后，向外查找最多256个邻接可表示fraction。
每一步仍分别严格检查双精度轨迹和实际float姿态；safe对全部未被初穿透策略忽略的目标检查，
unsafe对首次命中目标检查。不增加gap容差，不将邻接检查用于发现或判断连续碰撞。
若没有认证成功的分数，仍明确失败。极端数值仍可能需要超出该界限，暂不承诺覆盖。

before.log：相同sphere路径扩展24旋转×3margin×单/多目标，22次返回空；
after.log：扩展sphere和capsule共288条路径，864项断言通过（3新进程）。
GDScript独立面位置检查允许2e-6坐标变换roundoff；实现本身的gap符号检查无此容差。

固定Linux Godot4.7.2.NET/MuJoCo3.16源码构建通过。sweep76×3+5拒绝，
Capsule150×3+14负例，overlap154×3，witness325全部通过，错误/泄漏扫描通过。
没有改变之前非可表示切触/极窄区间拒绝测试。未跑sanitizer、Windows、package或G1heavy。
日志 `/workspace/shared/validation/sweep-precision-*`；构建日志
`/workspace/shared/sweep-precision-build.log`。实现只修改query cpp，可独立应用；
新回归包含Capsule，运行它需Capsule阶段提交db40796。
