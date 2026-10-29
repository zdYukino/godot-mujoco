# 控制预设

在 MuJoCo 层级模型面板选择模型，使用“导出当前设计控制预设”保存 v2 JSON。导出在独立 worker 中编译、计算完整设计签名，记录作者初始控制值及允许修改的 position/velocity kp/kv；general/non-PD 只记录控制值。它不记录 qpos/qvel/time，也不修改运行实例。

F5 后在同一面板的运行实例下拉框选定目标，点击“应用整份运行预设”。文件选择器固定目标与版本；选择切换、实例消失或版本变化会拒绝发送。状态按实例显示 accepted/completed/failed/cancelled；取消仅影响未提交请求。旧文档面板及旧实时协议已移除。

当前支持 joint transmission。签名将允许修改的增益标准化，再对完整规范 MJCF 求哈希；修改关节轴、锚点、传动、结构或资产路径会保守拒绝，不提供自动重映射。签名不替代依赖文件哈希检查。

所有字段先在 worker 验证，再由原生物理边界对独立的 combined model/data 候选应用整份控制与增益，验证当前动态状态后原子提交。源作者资源不变；失败无部分写入，其他实例保持独立。具体请求契约见[运行预设](runtime-presets.zh-CN.md)。

`tests/control_presets/run.sh` 验证签名、schema、非法增益/控制、不同设计和非 joint 传动；`tests/runtime_presets/run.sh` 验证实际原子提交、取消、实例隔离与数值失败；`tests/runtime_preset_editor/run.sh` 验证当前作者调试协议下的实例状态显示。
