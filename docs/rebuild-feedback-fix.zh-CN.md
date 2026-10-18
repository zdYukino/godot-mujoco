# 环境重建控件结果反馈修复

基于 e16a4ec，dot 静态审查指出真实应用层缺陷：重建按钮只显示请求入队，候选失败由 host.last_error / rebuild_finished 报告，而面板只读取保留下来的 world.last_error。因此旧环境正确保留时，面板反而看不到失败原因。

## 修复

- 面板订阅 host.rebuild_finished，分别显示“请求入队”“重建成功”“重建失败：具体原因”。成功重试会清除之前的失败反馈。
- host 重设时立即断开旧连接、连接新 host；绑定一个已经失败的 host 时读取其现有错误。旧 host 的完成事件不能覆盖新目标反馈。
- world 被替换时重新订阅 command_finished；只显示本控件发起的 command request 结果，候选世界自动捕获初始快照的完成事件不会覆盖重建结果。
- host/world 退出树时清理连接；控件自身退出/重入也清理并恢复连接，不重复注册。host 销毁时显示 no world，之后可以重新指定存活 host。

没有改变候选编译、提交或回滚算法，没有修改原生物理或 Godot 引擎。

## 实际控件回归

`tests/runtime_clock/acceptance.gd` 发出实际重建按钮的 pressed 信号，不以直接调用 host 方法代替主要失败路径：

1. 用错误根节点的 PackedScene 作为候选，点击按钮并重复点击。
2. 检查可见 status Label 包含 host 的具体失败原因；旧 world.last_error 为空时仍能看到错误。
3. 检查失败保留原 world、time 和机器人状态。
4. 恢复有效场景，再按按钮；检查显示最终成功，替换旧 world，自动快照完成后成功提示仍保留。
5. 覆盖 host 切换、旧 host 的迟到事件、重复刷新、控件移出/重入、host 销毁与重新绑定，以及晚绑定已有失败的 host。

命令：

```sh
source /workspace/shared/tools/env.sh
OUT=/workspace/shared/validation/rebuild-feedback-release bash tests/runtime_clock/run.sh
```

退出码 **0**，**118 项 GDScript 检查与 C# 回归通过**。本次新 OUT 的 import、runtime、C#、dotnet build 日志均无 ERROR/泄漏。首次实现的 `rebuild-feedback-01` 为 115 项；增加晚绑定错误场景后的 release 为 118 项，二者没有混标。

[结果](evidence/rebuild-feedback/results.json) · [导入日志](evidence/rebuild-feedback/import.log) · [运行日志](evidence/rebuild-feedback/runtime.log) · [C# 日志](evidence/rebuild-feedback/csharp.log) · [构建日志](evidence/rebuild-feedback/dotnet-build.log)

本次没有重新宣称 native/dynamic/freebase/G1 全套通过；改动范围是应用控件、相关 clock 回归和文档。

## dot 独立验收限制与复验

dot 对 e16a4ec 独立构建成功、36 个资产一致、90 个中文本地链接有效；自由基座运行退出 **137，原因未明**；clock fresh import 退出 **139，未进入功能测试**。这些独立结果保留，不能用本次云端 clock 通过覆盖，也不能猜测 137 是 OOM。没有开展引擎冷导入调试。此前编辑器 GUI Vulkan ERROR 的严格失败结论也不变。

dot 复验时在一个已加载有效环境的 playground 中，将 host.environment_scene 指向错误根节点的 PackedScene，再点击“重建已保存环境”。应看到具体失败文本，旧机器人/仿真时间保留；恢复有效场景后点击，最终应显示成功。重复点击、切换 host、移除再加入控件后重复上述步骤，确认没有旧消息覆盖、重复信号或泄漏。
