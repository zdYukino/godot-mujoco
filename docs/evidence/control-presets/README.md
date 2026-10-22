# 对象入口/控制预设最终轻量验证

固定 Linux Godot4.7.2.NET/MuJoCo3.16；native未改。以下实际入口均 exit0，正向 import/runtime 无ERROR/SCRIPT ERROR/leak：

- `OUT=/workspace/shared/validation/control-presets-05 bash tests/control_presets/run.sh`：21项；完整文件验证、候选编辑、原子提交与undo、实例隔离、控制范围/非法增益/文件拒绝。
- `OUT=/workspace/shared/validation/scene-objects-03 bash tests/scene_objects/run.sh`：20项；增加单精度尺寸溢出/归零拒绝。
- `OUT=/workspace/shared/validation/presets-editor-regression bash tests/editor_plugin/run.sh`：160项。
- `OUT=/workspace/shared/validation/presets-panel-regression bash tests/heightfield_panel/run.sh`：44项。

failed-parser 保留第一轮新函数混用缩进导致的脚本加载失败；该轮无可运行测试，主动终止失败编辑器后shell返回139。不能把它当作正常通过或无证据归因于已知cold-import问题。修正缩进后新OUT重跑，非缓存伪通过。
failed-object-assertions 保留首轮三项单精度精确比较失败；改近似比较后通过。其余历史证据不覆盖。

真实鼠标GUI未运行，待dot。未做运行整套预设原子批量应用；本轮提供文档级预设，运行设计和控制继续通过已有显式操作。未跑重G1/迁移压力、未打包/Windows/远端CI，冷导入139未修复。

failed-name-assumption 保留新增测试的错误假设：导入器已有 assign_names，会为未命名 actuator 分配唯一名，因此原测试“应拒绝原始未命名”失败。最终改为核对全部自动命名 actuator 字段均保存，21项通过；没有移除生产空名称/重复映射防护。
