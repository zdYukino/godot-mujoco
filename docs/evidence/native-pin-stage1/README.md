# 原生 Pin 阶段验证

源码build3 exit0。Pin正例49、负例21（11条精确预期拒绝）、GUI脚本headless smoke均exit0；executions.tsv/results.json记录进程与断言。含实际PinJoint3D节点PackedScene保存重开、锚点收敛/自由旋转、碰撞开关、回调FIFO、删除重加与有限但危险候选拒绝后的旧定义/姿态/速度/暂停/时间保持。

关键回归 native_contacts68、native_semantics98+31、native_area53+22、native_backend149、runtime_clock118+C# runner exit0。原始回归完整日志保留在 /workspace/shared/validation/native-pin；本目录包含runner摘要及Pin完整日志。正常日志无非预期ERROR/SCRIPT ERROR/leak，负例独立核对。

复跑 source /workspace/shared/tools/env.sh；cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2；OUT=<fresh directory> bash tests/native_joints/run.sh；regression-exits.tsv各suite同样调用tests/<suite>/run.sh，native_backend设置REPEAT=1。

真实GUI待dot；Pin参数不是GodotPhysics求解器等价实现，详细边界见 ../../native-pin-stage1.zh-CN.md。Hinge未实现。基础集成2442976新发现的sphere/rotated-box sweep认证拒绝缺陷由queryworker处理，本阶段未修改查询也不宣称该场景通过。冷导入139、重负载/Windows未验证限制保持。
