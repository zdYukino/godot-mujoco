# 地形类型化接口阶段验证

功能分支 codex/heightfield-editor-typed-api，依赖面板提交 2ae8f2d7；main 仍为
5d7b423。原工作区恢复后完成；未更换用户环境或扩大权限。无 C++ 改动或 native 重建。

固定 Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16，先 source
/workspace/shared/tools/env.sh，再运行：

| 命令 | 结果 |
| --- | --- |
| `OUT=/workspace/shared/validation/typed-terrain-final bash tests/typed_terrain/run.sh` | exit 0，50 项；C# 编译 0 warning/error |
| `OUT=/workspace/shared/validation/terrain-panel-completion bash tests/heightfield_panel/run.sh` | exit 0，20 项 |
| `OUT=/workspace/shared/validation/terrain-completion-runtime bash tests/heightfield/run.sh` | exit 0，73 项 |
| `OUT=/workspace/shared/validation/typed-model-regression bash tests/typed_control/run.sh` | exit 0，原门面 69 项 |
| `git diff --check`、两个新增 runner 的 bash -n | exit 0 |

全部正向日志扫描无 ERROR/SCRIPT ERROR/leak。完整临时项目与日志保留于上述 OUT。
初次 typed-terrain-01 测试错误地在工作线程 GetNode，Godot 输出 ERROR，runner 正确判为
exit 1，即使末尾有通过标记也未当作通过。已改为主线程先取 Node，再测试门面线程拒绝。
原失败日志单独归档。typed-terrain-02 修正后45项；增加提交窗口读取和两模型接触/状态保持后50项。

覆盖：不可变设计复制、非法网格/缩放拒绝、两地形 ID 与 revision 隔离、两个句柄的并发
门槛、box 和两个轻量关节模型真实接触、状态迁移保持、过期版本、分辨率失败、读取先获取
物理完成结果、成功移除后的旧句柄、继承节点、删除期间 pending 观察结果、同节点重入、
自动重新应用、保存重开和整个 world 释放。

本阶段同时将编辑器 completed/failed 与 accepted/pending 明确区分：运行节点发送完成
消息，EditorDebuggerPlugin 保存按实例 ID 隔离的结果，面板显示完成版本/错误；测试包含
接收完成消息后的状态更新。实际编辑器与游戏之间的调试会话及鼠标 GUI 仍需 dot 验收，
此处不冒充 GUI 端到端。

不合 main、不打包、不 Windows、不 G1/迁移重负载、不强制编译器/分配失败注入；冷导入139
仍为既有限制。用户之后批准合入前，main 的带限制开发基线保持不动。
