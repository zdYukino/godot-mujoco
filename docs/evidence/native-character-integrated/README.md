# Character 最终集成验证

基于已验收集成 `1e2d10e`，合入 `37d202b` 与 `0909781` 的 Character 实现及三项复审修复；保留 Area/FIFO、接触、P0、Pin/Hinge 与 query 修复。Pin/Hinge 明确拒绝 kinematic 端点。

额外复审发现 world reset 将 mocap 重置到编译位置、Godot 缓存却保留新位置。隔离测试修复前 8/11、修复后 11/11。现在 reset 保留当前外部控制的 mocap 姿态；不是把 kinematic 姿态纳入关节 checkpoint。

## 最终产物与结果

Linux x86_64；官方 Godot 4.7.2.stable.mono.official.ed1daf0bf；MuJoCo 3.16.0；.NET 8.0.426。
源码构建退出 0，最终扩展 SHA256 `9b6e3626a53184c8b9f3b5eef78d5c475ca476c28deb3477e15a980f0b15303b`。
`exits.tsv` 中 21 套全部退出 0；`extra-exits.tsv` 中 5 项全部退出 0。每套严格检查正常日志与预期拒绝日志，未出现非预期 ERROR/SCRIPT ERROR/leak。
Character：RID 52×3，Character 23×3，reset 11，negative 12；额外 Area 38、跨功能 22、数值 1048 与 capsule 数值 445。
修复前第一轮 21 套虽通过，但被 reset 修复后的本轮完整重跑替代；旧原始日志保留 `/workspace/shared/validation/character-final`。

## 可复用命令

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
# 对 exits.tsv 的每个 suite（第二列为真实退出码）：
OUT=/tmp/verify-$suite REPEAT=1 bash tests/$suite/run.sh
OUT=/tmp/motion-negative bash tests/native_motion/run_negative.sh
OUT=/tmp/area-extra bash tests/native_area_environment/run_supplemental.sh
OUT=/tmp/cross bash tests/native_backend_integration_cross/run.sh
g++ -std=c++17 -O2 tests/native_sweep/numerics.cpp -o /tmp/numerics && /tmp/numerics
g++ -std=c++17 -O2 tests/native_sweep/capsule_numerics.cpp -o /tmp/capsule-numerics && /tmp/capsule-numerics
```

本目录保存构建、runner、各套结果与顶层原始日志。完整生成项目在 `/workspace/shared/validation/character-final2`。GUI 步骤参见 `tests/native_motion/README.zh-CN.md`，本环境无桌面，最终独立 dot/GUI 待执行。

## 限制

仅 sphere/capsule 平移主体；kinematic 为单向查询障碍，不推动动态刚体。非完整移动平台/楼梯/旋转 sweep/CCD，heightfield/MJCF body motion 未支持；无法认证实际 float 端点明确拒绝。Pin/Hinge 仍为受限 forest/passive，Hinge limits/motor 未支持。接触仅最后实际子步，非全帧累计。
冷导入 139 未根治；缓存/已有导入流程不构成 fresh cold-import 通过。未运行 G1 重负载、Windows、打包或远端 CI。未合 main。
