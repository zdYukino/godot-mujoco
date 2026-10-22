# Overlap witness 修复验收

基点 `c39bb79957141be563794b5c1880a44386732c69`；原始失败证据：
`fe35dd92875b7463e63611ded9a753c9dad1d9e7` 的 `docs/evidence/overlap-witness-blocked`。
原始 18 组 127 项中的表面归属 48 项失败已消除；保持原始 surface tolerance 0.003，
扩展到 36 组 325 项，额外覆盖偏心、深穿透距离保留及目标外向法线锥。

Linux Godot 4.7.2.NET / MuJoCo 3.16.0，源码构建通过。
最终输出校验补齐后，三个独立 witness 进程各 325/0；完整首轮结果见 results.json，
重复运行计数、真实退出状态、二进制 SHA256 和最大表面误差见 runs.json。

交叉回归：native_overlap 154×3，native_sweep 76×3 + 5 个明确拒绝场景，
native_backend 149（3 个新进程），全部通过。独立 sweep 数值 1048、core smoke 通过。
测试脚本 ERROR/leak 日志检查通过；未运行 sanitizer、GUI、Windows、打包或 G1 heavy。
本机日志在 `/workspace/shared/validation/witness-certified-*`，构建日志在
`/workspace/shared/witness-certified-build.log`。

复现：源码构建后 `source /workspace/shared/tools/env.sh`，运行
`bash tests/native_overlap_witness/run.sh`、`bash tests/native_overlap/run.sh`、
`bash tests/native_sweep/run.sh`。

修复只涉及 query cpp、私有 BSD MPR support-witness helper 和 CMake 三个 C 编译单元。
不改变 MuJoCo 仿真或公共接口；不保证旧流形点数或全局最小平移恢复。
既有 sweep 支持范围和明确失败策略不变，heightfield/MJCF 不扩围。
