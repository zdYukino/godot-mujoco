# 原生后端集成验证（Linux）

基于已独立验收 P0/contact fe35dd9，集成 overlap 0bc54e2、sweep c39bb79、witness 修复 62fb00a，以及 Area af40f02/FIFO 修复 0a42c4a。共享服务器合并保留 COM 速度转换、实际步回调、暂停同步与 deferred shape 接触失效保护。

固定 Godot 4.7.2 .NET / MuJoCo 3.16.0。源码构建 exit0；exits.tsv 和 extra-exits.tsv 为本次每套 runner 退出码，全为0。native_area 包含53+22顺序检查；contacts68；semantics98+31负例；overlap154×3；witness325；sweep76×3+5负例；native149；cylinder35+9负例；heightfield73；clock118+C#；presets48；typed69；editor160；严格 core smoke。独立数值 sweep1048。负例日志独立，正常日志无非预期 ERROR/SCRIPT ERROR/leak。

复跑：source /workspace/shared/tools/env.sh；cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2；对 exits.tsv/extra-exits.tsv 各 suite 执行 OUT=<fresh absolute directory> REPEAT=1 bash tests/<suite>/run.sh。数值：g++ -std=c++17 -O2 tests/native_sweep/numerics.cpp -o /tmp/sweep-numerics && /tmp/sweep-numerics。

本次 GUI smoke 仅 headless，最终集成真实 GUI 待 dot。先前 P0/contact 的 dot GUI 通过不替代新增 Area/query 验收。冷导入139未根治，沿用明确的初始化缓解，不称全冷稳定。未跑 G1、迁移重负载、Windows、远端CI或打包。

能力边界：contact impulse 仅最后实际子步，不累计整帧短暂接触。Area 仅 box/sphere/cylinder 监测，不提供环境覆盖或 Area 空间查询。Overlap 不含 MJCF/专用高度场。Sweep 仅球对原生有限体及有限体/平面组合、固定朝向平移，未知组合明确失败；不是 CCD、CharacterBody 或 body_test_motion。查询临时模型编译吞吐未优化。Pin/Hinge 仍未实现。
