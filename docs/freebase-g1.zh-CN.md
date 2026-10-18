# G1 自由基座、重力与接触

36 个原始 Unitree `g1_29dof_mode_18` 资产保持字节不变。导入操作只创建派生模型；固定基座是默认流程，不会被无提示地改成自由基座。

## 显式选择

编辑器 **Import free G1 (relaxed)** 使用：

```gdscript
var doc = ClassDB.instantiate("MjEditorDocument")
var ok = doc.import_g1(urdf_path, true, true)
```

第二参数 free_base=true，在 pelvis 上加 `floating_base`；第三参数 relaxed=true，不创建合成位置驱动，所有 body 的 gravcomp=0。关节被动参数和限位来自导入模型。松弛 G1 在地面上倒下是预期行为；没有平衡/站立/步行算法。

`import_g1(path)` 保留固定基座与原合成 PD/重力补偿行为；`import_g1(path,true,false)` 显式选自由基座加合成位置 PD，但仍无重力补偿，也不是站立控制器。

## 状态和坐标

自由关节有 7 个 qpos：位置 xyz + 四元数 wxyz；6 个 qvel：线速度 xyz + MuJoCo 局部角速度 xyz。不要将 7 维位置当作 6 维速度，或将局部角速度当作 Godot 世界角速度。

Godot Y-up→MuJoCo Z-up 为 `(x,y,z)→(x,-z,y)`；反向位置为 `(x,y,z)→(x,z,-y)`。运行时 `robot.state().joints.floating_base` 保留 MuJoCo 数组语义，`robot.state().bodies.pelvis.transform` 是转换后的 Godot 世界位姿。根 Node3D 跟随真实 body；卸载/退出树时恢复保存的初始放置变换，避免同一节点重加时累计仿真位姿。网格世界位姿继续来自真实 geom，不重复叠加根位移。

## 可复现实验

```sh
export GODOT_BIN=/实际路径/官方Godot二进制
OUT=/tmp/freebase-fresh bash tests/freebase/run.sh
cp tests/freebase/prepare_playground.gd /tmp/freebase-fresh/project/
"$GODOT_BIN" --headless --path /tmp/freebase-fresh/project --script res://prepare_playground.gd
"$GODOT_BIN" --path /tmp/freebase-fresh/project --rendering-method gl_compatibility \
  --audio-driver Dummy res://FreebasePlayground.tscn
```

OUT 必须是全新目录。示例初始暂停，提供地面和普通 Godot 障碍；先观察初态，再单步、恢复到倒伏、暂停和重置。右键/滚轮相机应在暂停时响应。

物理测试使用原脚底碰撞球计算初始高度，比较摩擦 0.001 与 1.0 的水平运动，验证普通 Godot 障碍接触、有限 qpos/qvel、零 MuJoCo warning 和穿透界限。模型接触掩码继续排除机器人自碰撞；此结果不能推导自碰撞已验证，也不能推导任意地形/步行能力。报告给出的约 2.62 cm 最深接触属于松弛倒伏的软接触用例。

[完整数字/日志/截图](freebase-clock-validation.zh-CN.md) · [两种重置](runtime-clock.zh-CN.md) · [中文索引](README.zh-CN.md)
