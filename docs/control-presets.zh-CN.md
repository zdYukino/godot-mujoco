# 控制参数预设（编辑文档级）

MuJoCo 主工作区新增“保存控制预设 / 加载控制预设”JSON 文件入口。保存 actuator control（position-compatible 为目标位置、velocity-compatible 为目标速度，单位受 joint/gear 传动影响）和已有分类允许编辑的 kp/kv。general/non-PD 仅保存控制值，不捏造 PD 参数。

这不是当前 qpos/qvel/time 的仿真 checkpoint，也不是自动运行广播。没有 actuator 的模型保存空控制集合；导入器会为原始未命名 actuator 生成名称，预设保存这些实际名称；若仍有空名称/重复映射则拒绝，避免字段丢失。指纹包含 inspect 的模型实体与属性，但排除 qpos/control/kp/kv：关节类型、限位、名称、目标映射、gear、控制范围以及其他设计发生改变会拒绝。采用保守兼容规则，不提供跨机器人自动重映射。

加载需先暂停编辑模型、Apply/Discard 属性草稿。先完整检查 schema、映射、数值，然后在独立候选 MjEditorDocument 验证全部增益与目标；全部成功才替换当前文档，形成一次 Undo/Redo。任一目标越界、负增益、非法/超大文件、缺失 actuator 均不部分覆盖原文档。其他文档/运行实例不修改。重复加载同一预设结果一致。

运行应用明确分开：
1. 加载成功只表示编辑文档更新；状态栏明确“运行实例尚未改变”。
2. PD 属于模型设计：Save project model 后，选定一个运行实例，使用既有 Apply saved model to runtime 安全事务，并查看 pending/error/revision 结果。不要把发送请求当作完成。
3. 控制目标：选定对应 actuator，使用已有 Send selected control to runtime，逐项发送并查看实例反馈。结构应用可能保留兼容运行控制状态，不能假设保存模型会覆盖当前控制。
4. 本轮**不提供运行实例的整套预设原子批量应用**；加载不会自动发以上任何请求。需要批量运行预设事务时作为后续独立功能，不能用逐项发送冒充批量原子成功。

验收：`OUT=/absolute/new/path bash tests/control_presets/run.sh`，21项真实 EditorPlugin 检查。GUI：设置两个目标与适用PD，保存预设；改值再加载；Ctrl+Z/Redo；无效JSON/不同模型/未Apply字段应拒绝且保留原值；关闭重开文档后加载同一预设。F5开两个实例，加载预设应不改变任一运行实例，后续显式选择/应用只影响目标实例。真实GUI由dot独立执行。
