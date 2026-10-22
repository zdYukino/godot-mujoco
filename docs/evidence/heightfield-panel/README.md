# 地形面板阶段验证

从已合入 main 的 5d7b423 开发，未再次合入 main。无 native 源码变更，使用现有固定
Godot 4.7.2 .NET / MuJoCo 3.16 库。

命令均先 `source /workspace/shared/tools/env.sh`：
- `OUT=/workspace/shared/validation/terrain-panel-guard-final bash tests/heightfield_panel/run.sh`：exit 0，19 项，真实 EditorPlugin。
- `OUT=/workspace/shared/validation/terrain-bridge-final bash tests/heightfield/run.sh`：exit 0，73 项，运行接收入口与真实物理事务。
- `OUT=/workspace/shared/validation/terrain-panel-import bash tests/editor_plugin/run.sh`：exit 0，原编辑器 160 项（面板初版，后续改动由面板专用检查覆盖）。
- `git diff --check`：exit 0。

所有正向日志无 ERROR/SCRIPT ERROR/leak。完整临时项目在以上 OUT。
早期 terrain-panel-01 为失败：Discard 数字文本格式断言过严、headless 保存缩略图出现
texture null ERROR。已改为检查数值及无缩略图保存，原失败日志保留；不将 exit 0 或后续
通过覆盖该失败。terrain-panel-02 为修正后的 17 项通过，后增至 19 项。

实际调试会话消息传输与鼠标 GUI 待 dot；步骤见 docs/heightfield-editor.zh-CN.md。
未跑 G1/多 G1/迁移压力，不做打包、Windows、引擎冷导入修复或远端 CI 门槛。
