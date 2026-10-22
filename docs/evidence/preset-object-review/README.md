# 独立审查两项修正

1. 预设不再使用不完整的 inspect 投影作签名。在隔离文档中规范化允许编辑的PD值后，对完整规范MJCF XML签名，覆盖axis/anchor等未显示字段。格式v2拒绝旧v1。非joint transmission整体拒绝；不以N/A目标字符串认为兼容。原生C++未改。
2. 创建前检查派生球直径、box半尺寸、圆柱半高的float32有效性。2e38球半径导致直径溢出时拒绝，节点数及Undo版本不变。

命令均在固定工具链 env.sh 下，全部入口 exit0，import/runtime无ERROR/SCRIPT ERROR/leak：
- `OUT=/workspace/shared/validation/control-presets-mapping-01 bash tests/control_presets/run.sh`：30项，包括axis/anchor修改、t1/t2两种tendon目标均拒绝且文档不变、签名不修改源文档。
- `OUT=/workspace/shared/validation/scene-objects-derived-01 bash tests/scene_objects/run.sh`：23项，包括派生溢出/归零无节点/Undo污染。
- `OUT=/workspace/shared/validation/preset-review-editor bash tests/editor_plugin/run.sh`：160项。
- `OUT=/workspace/shared/validation/preset-review-terrain bash tests/heightfield_panel/run.sh`：44项。

native沿用此前构建，未重建、无native改动；真实GUI尚待dot。PR4保持draft，不合main。冷导入/重负载/打包/Windows既有限制不变。
