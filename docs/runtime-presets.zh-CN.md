# 运行实例整份控制预设事务

在 MuJoCo 主工作区选择一个运行实例，点击“应用整份运行预设”，打开 v2 JSON。文件选择器绑定打开时的实例与revision；选择切换、实例消失或revision变化会拒绝发送，需重新打开。取消文件选择器不发送任何请求。设计文档的 Apply/Discard 与加载仍独立，不会隐式发到运行世界。

请求契约：
1. UI只复制数据并排队，accepted/pending 不表示成功；同一实例的模型编辑/预设共享pending门禁。完整预设含全部 actuator 控制值与分类允许的 kp/kv。
2. native物理步边界验证world/RID生命周期与property revision，暂时暂停该space，基于当前native模型做完整v2兼容签名与所有字段/数值/控制范围/PD合法性验证。不使用可能落后的资源缓存作兼容判断。
3. 候选模型独立编译，复用原有重建/兼容状态迁移；失败保留旧模型与全部控制。成功在同一边界提交所有目标与PD，再增加revision，返回一致的原生state快照。其他实例的兼容状态保留；未暂停世界恢复运行，已暂停世界保持暂停，时间不因事务重置。
4. 反馈按session/live_id归属：accepted、completed、failed、cancelled和request/revision。状态展示随选择切换；Stop移除会话后清空。传输仅携带结果元数据，不发送含native RID的state；本地edit_finished结果包含提交快照。
5. “取消待提交运行预设”只取消仍在native队列中的请求，最终反馈cancelled。若已经执行或提交，取消失败；不伪称撤销。取消后如需恢复设计目标，应显式提交另一份预设。卸载/删除节点取消未执行请求，重建节点产生新live_id/RID，旧句柄不能写新实例。

脚本接口：`instance.request_control_preset(preset_dictionary, expected_revision)` 返回是否入队；等待 `edit_finished` 或检查 `edit_request`/`last_preset_result`，再判断success。`cancel_control_preset()` 仅返回是否接受取消；不等价于回滚已完成操作。pending期间 `instance.set_control` 拒绝，避免把单值操作混入正在提交的整份预设。

仍仅支持joint transmission；position kp>0/kv>=0，velocity kv>0，general/non-PD不提供PD字段。非joint传动不扩大。运行应用不修改model资源、编辑文档或磁盘文件；重启按原设计初始化。预设签名基于完整规范XML（只规范化可变PD），不是外部资产内容hash。含资产时应从同一已保存project model打开文档导出预设；路径/设计不匹配会保守拒绝。

## 自动及GUI验收

**native已改变，先从源码重建扩展**。固定Linux x86_64 Godot4.7.2.NET/MuJoCo3.16：

```sh
OUT=/absolute/new/runtime-preset bash tests/runtime_presets/run.sh
OUT=/absolute/new/runtime-preset-editor bash tests/runtime_preset_editor/run.sh
OUT=/absolute/new/document-preset bash tests/control_presets/run.sh
```

第一入口生成Environment.tscn、RuntimePresetDemo.tscn、good.json和bad-last.json，35项双实例断言；第二入口7项真实EditorPlugin目标反馈隔离检查。均记录真实退出/错误与日志。接收入口测试不是实际debugger桌面传输通过。

GUI：打开生成项目，在编辑器打开RuntimePresetDemo.tscn并F6。进入MuJoCo工作区，选First应用good.json；观察accepted→completed及revision增加，First两个控制/PD全部改变，Second不变。bad-last.json末项kv=0，应failed，之前所有控制与PD保持。重复点击不能重复排队；切Second时不显示First结果。打开文件选择器后切目标/取消应无发送。P恢复/暂停、S步进100；运行应用后保持原暂停状态。点击取消若来得及应cancelled且无变化，若已完成应明确不能取消，不能要求UI把已提交操作撤销。Stop/F6后从设计重新初始化，不继承上次运行预设。

本轮不注入内存耗尽或强制编译器失败，不运行G1重负载；冷导入139仍未根治，不把初始化失败后的未运行测试标通过。
