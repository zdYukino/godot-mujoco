# 原生 CylinderShape3D 阶段证据

依赖综合示例提交 77b4eef410908ea76b99f0fb2856fe9e792aa5bf，基于 main 8157253。仅 Linux x86_64 固定工具链，源码增量构建扩展；见 summary.json 的真实二进制 hash。

命令均先 `source /workspace/shared/tools/env.sh`：

| 命令 | 退出 | 结果 |
|---|---:|---|
| `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2` | 0 | native 源码构建 |
| `OUT=/workspace/shared/validation/native-cylinder-02 bash tests/native_cylinder/run.sh` | 0 | 35 正例、9 隔离预期拒绝 |
| `OUT=/workspace/shared/validation/cylinder-native-regression REPEAT=1 bash tests/native_backend/run.sh` | 0 | 149；3独立进程 |
| `OUT=/workspace/shared/validation/cylinder-heightfield-regression bash tests/heightfield/run.sh` | 0 | 73 |
| `OUT=/workspace/shared/validation/cylinder-workflow-regression bash examples/light_workflow/run.sh` | 0 | 7，含 C# 重新编译 |
| `OUT=/workspace/shared/validation/cylinder-smoke-regression bash tests/mjworld_smoke/run.sh` | 0 | 严格正/负日志审计与单元测试 |
| `godot --headless --path /workspace/shared/validation/native-cylinder-02/project --quit-after 120` | 0 | GUI 场景加载；非桌面验收 |

通过阶段正例全部无 ERROR/SCRIPT ERROR/leak。预期错误仅在 cylinder/negative.log 和 smoke/negative.log；smoke verifier/audit 记录依既有格式。第一轮 native-cylinder-01 三进程虽然各 exit0，import 含缺失 Main.tscn 的 ERROR，入口最终 exit1；在 failed-first-import/ 原样保留，不能计入通过。

未复跑 G1、多G1、迁移压力、全量编辑器/C#独立套件；本次不改编辑面板及类型化 API。GUI、独立源码重建交 dot 复验。无打包、Windows、CI门槛或引擎修改；冷导入139仍未根治；强制候选编译/分配失败未注入。
