# 被动 Hinge 阶段验证

源码构建exit0。Hinge44正向/19负向断言通过（16条精确预期拒绝），import/positive/negative/gui-smoke全exit0。覆盖world/双dynamic、旋转与反平行轴、偏置frame、横向抑制/轴向自由、真实HingeJoint3D保存重开、limits/motor启用与非法frame/有限不安全candidate拒绝。

升级后的Pin49+21、contact68、Area53+22、native149回归exit0。正常日志无非预期ERROR/SCRIPT ERROR/leak；负例隔离核对。命令 source /workspace/shared/tools/env.sh；cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2；OUT=<fresh> bash tests/native_hinge/run.sh；tests/native_joints/run.sh及regression-exits各suite同样运行，native_backend REPEAT=1。

真实桌面GUI待dot。仅被动软连接，不是完整Hinge；limits/motor明确未实现，完整数值边界见 ../../native-hinge-passive.zh-CN.md。官方公开API实验放在feasibility，仅为可行性证据，不能当插件功能验收。

上游2442976查询仍有独立发现的17 empty casts，待queryworker修复。本阶段未改查询，不覆盖该失败。未跑G1/重负载/Windows/打包；冷导入139未根治。
