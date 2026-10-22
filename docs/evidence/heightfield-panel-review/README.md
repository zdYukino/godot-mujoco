# 地形面板独立审查修正

基于 3958e26，仅修改面板、面板测试及文档；不改 native/C#，不合 main。

旧实现真实复现：直接调用编辑器场景 UndoRedo 历史 undo（不是面板 undo 回调），
等待编辑帧后场景设计已回退，面板 draft 仍旧。terrain-external-repro exit 1，失败日志
隔离保留在 negative/；与 dot 鼠标 Ctrl+Z/Apply/Save 的独立复现一致。

修正：快照轮询覆盖不发 changed 的资源数组修改，动作前同步校验；干净面板自动同步，
有草稿则保留文本并阻止冲突 Apply/保存，可显式采用当前基线后覆盖。同尺寸重新基准化
的 Undo 恢复外部编辑值。运行结果按 session/实例读取，选择时立即重新计算，无结果
不显示其他目标的结果，Stop 清除。Flow 布局、可收缩目标与状态折行避免长 ID 撑宽。

命令：source /workspace/shared/tools/env.sh，然后
`OUT=/workspace/shared/validation/terrain-external-final2 bash tests/heightfield_panel/run.sh`
exit 0，44 项，真实 EditorPlugin。import/runtime 日志无 ERROR/SCRIPT ERROR/leak。
`git diff --check` exit 0。完整临时项目及日志留在上述 OUT。

覆盖：原生 undo/redo，undo 后 Apply/保存并重新从磁盘加载核对；Inspector 使用的属性
setter、原地资源数组修改、资源替换、mask 修改；有草稿时冲突、保存阻止、显式 rebase、
Undo 恢复、不同尺寸拒绝和 Discard；非法 Inspector NaN 可修复且不会陷入假冲突；
跨 session 的 A/B success/failure/pending 与无结果目标切换、未选中目标完成、Stop 清理；
布局最小宽度不超过800且菜单不按最长条目撑宽。

程序化场景历史/属性 setter 和布局检查不冒充实际键盘鼠标 GUI。dot 需复验 1152px
编辑器中按钮可达、Ctrl+Z/Redo/保存以及真实 debugger A/B/Stop。此次未重跑无关 native、
C#、重负载或引擎初始化研究；既有已知限制不变。
