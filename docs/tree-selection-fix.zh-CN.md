# 未应用字段的树选择恢复

此页为同步信号修复的历史记录；后续真实鼠标缺陷及修复结果见[最新GUI验收报告](mouse-gui-fix.zh-CN.md)。

dot 验收发现：joint 的 damping=0.2、frictionloss=0.1、range=[-1,1] 尚未应用时点击 body:arm，属性面板正确拒绝切换，但树高亮已经切换。

修复在拒绝切换的同一信号回调中恢复实际编辑对象的 TreeItem，并使用现有 refreshing 标志阻止重入；不重建表单、不丢弃草稿、不修改物理文档。

自动测试模拟真实 Tree 选择信号，覆盖连续两次拒绝、保留原输入控件与文本、文档不变，以及 Discard 后正常选择。

验证命令：`source /workspace/shared/tools/env.sh && OUT=/workspace/shared/validation/tree-selection-dot-fix tests/editor_plugin/run.sh`，退出码 0，147 项检查通过。原始 [导入日志](evidence/tree-selection-dot-fix/import.log)、[运行日志](evidence/tree-selection-dot-fix/runtime.log) 与 [结果](evidence/tree-selection-dot-fix/results.json) 保留；本次日志无 ERROR 或泄漏。

dot GUI 复验：选 hinge，输入上述三个值；连续点击 arm，树应仍高亮 hinge、输入保持原值；点击 Discard 后再点 arm，树和属性面板应同时切换。自动测试通过不替代 dot 的独立 GUI 验收，也不改变已知 cold-import/宿主图形限制的结论。
