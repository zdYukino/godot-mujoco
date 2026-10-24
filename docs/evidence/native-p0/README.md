# P0 原生刚体语义验收

开发基于 `8d3976e`，本证据对应 P0 阶段源码；以 summary.json 的 native SHA256 识别二进制。源码构建和所有记录的 runner 均 exit 0。每组保留导入、执行日志与机器结果。`semantics` 负例 21 条、`cylinder` 负例 9 条预期拒绝独立存放；不把预期错误混入正向通过日志。

```bash
source /workspace/shared/tools/env.sh
cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2
OUT=<fresh-directory> bash tests/native_semantics/run.sh
OUT=<fresh-directory> REPEAT=1 bash tests/native_backend/run.sh
OUT=<fresh-directory> bash tests/native_cylinder/run.sh
OUT=<fresh-directory> bash tests/runtime_clock/run.sh
OUT=<fresh-directory> bash tests/runtime_presets/run.sh
OUT=<fresh-directory> bash tests/heightfield/run.sh
OUT=<fresh-directory> bash tests/typed_control/run.sh
```

clock 另含 C# build/run 通过。GUI 步骤在 tests/native_semantics/README.md，本环境未执行真实桌面验收。禁止将 headless 测试视作 GUI 通过。未跑 G1 重负载；冷导入139仍独立记录，使用已有 import helper 不代表冷导入修复。
