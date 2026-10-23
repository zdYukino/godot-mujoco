# 运行整份预设事务阶段

依赖已合入main4637c33。本阶段改变native，必须源码重建，二进制hash见summary.json。固定Godot4.7.2.NET/MuJoCo3.16、Linux x86_64。

先 `source /workspace/shared/tools/env.sh`。以下命令实际exit0，正向import/runtime/build日志无ERROR/SCRIPT ERROR/leak；strict smoke的预期错误单独在其negative.log并经严格审计。

| 命令 | 结果 |
|---|---|
| `cmake --build /workspace/shared/builds/godot-mujoco-3.16 -j 2` | 源码构建；runtime-preset-build-02.log |
| `OUT=/workspace/shared/validation/runtime-presets-02 bash tests/runtime_presets/run.sh` | 35 |
| `OUT=/workspace/shared/validation/runtime-preset-ui bash tests/runtime_preset_editor/run.sh` | 7 |
| `OUT=/workspace/shared/validation/runtime-preset-document bash tests/control_presets/run.sh` | 39 |
| `OUT=/workspace/shared/validation/runtime-preset-native REPEAT=1 bash tests/native_backend/run.sh` | 149 |
| `OUT=/workspace/shared/validation/runtime-preset-typed bash tests/typed_control/run.sh` | 69 |
| `OUT=/workspace/shared/validation/runtime-preset-editor bash tests/editor_plugin/run.sh` | 160 |
| `OUT=/workspace/shared/validation/runtime-preset-heightfield bash tests/heightfield/run.sh` | 73 |
| `OUT=/workspace/shared/validation/runtime-preset-smoke bash tests/mjworld_smoke/run.sh` | strict smoke passed |
| `godot --headless --path /workspace/shared/validation/runtime-presets-02/project res://RuntimePresetDemo.tscn --quit-after 120` | GUI场景加载，无真实图形验收 |

状态机覆盖accepted/commit/failure/cancel、paused/running恢复、双实例目标/PD/revision隔离、提交快照、无早期写入、末项非法增益/范围/NaN/schema/映射/revision失败无部分覆盖、卸载重建旧ID拒绝、真实bridge接收入口及选择结果隔离。原生signature/候选验证与文档预设共用，防止两套规则漂移。

真实桌面debugger传输待dot，不能以接收入口测试代替。强制编译器/分配失败未注入，冷导入139未根治；未跑G1/迁移压力，不打包/Windows/远端CI。后端计划文档仅分析现有代码，不视作新增能力验证。
