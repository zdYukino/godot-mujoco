# 运行实例控制预设事务

MuJoCo 层级模型面板提供运行实例选择、整份预设应用和待提交取消。选择器固定打开时的实例身份与 property revision；目标变化后需重新打开。保存/加载作者场景与运行预设互相独立。

1. `instance.request_control_preset(preset, expected_revision)` 只表示请求被接受，同一实例 pending 时拒绝重复请求及单值控制。
2. 可终止的 worker 根据当前作者源和有效世界碰撞上下文验证完整 v2 签名、schema、命名传动、控制范围和增益。取消或超时会终止该 worker。
3. 原生物理边界再次检查世界、实例和 revision。在独立的 combined model/data 副本上应用全部目标与增益，并对当前 live 状态 forward，检查 qpos/qvel/qacc、力和激活的有效性及新增 warning。通过后同时提交并增加 revision；失败保留全部活动状态。
4. 请求完成后发出 `edit_finished(result)`；`last_preset_result` 分别记录 completed、failed、cancelled。运行中的世界保持运行，暂停的世界保持暂停，时间不重置。其他实例的控制、增益和状态独立。
5. `cancel_control_preset()` 取消编译或仍在提交队列中的请求；已提交操作不能伪装成取消。卸载节点会丢弃未执行请求，新 RID/live identity 不接受旧身份的消息。

position 要求 kp>0、kv>=0；velocity 要求 kv>0；general/non-PD 不提供 PD 字段。仅支持 joint transmission。运行预设不修改作者资源或磁盘文件；重新启动按作者初始控制值加载。普通物理对象导致的世界重编译会携带当前运行增益。

```gdscript
if robot.request_control_preset(preset, robot.state().property_revision):
    var result: Dictionary = await robot.edit_finished
    if not result.success:
        status.text = result.error
```

`tests/runtime_presets/run.sh` 覆盖双实例、控制与增益原子性、陈旧版本、取消、身份隔离、暂停/运行状态，以及 live qpos=2 下的过大增益拒绝。`tests/typed_control/run.sh` 覆盖 C# 的 `ApplyControlPreset` 和完整原生完成状态；`tests/runtime_preset_editor/run.sh` 覆盖面板状态隔离。
