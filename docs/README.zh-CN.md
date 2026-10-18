# 中文文档索引

当前目标固定为 Linux x86_64、Godot 4.7.2 .NET 官方二进制、MuJoCo 3.16.0。以下中文使用指南是本分支入口；历史报告保留原日期、原版本和原日志，不按当前结果重新解释。

## 使用指南

| 需要做什么 | 文档 |
|---|---|
| 构建、导入、插件启用、排查灰屏 | [Linux 安装与限制](linux-install.zh-CN.md) |
| 编辑质量/惯量/关节、视口操作、保存 | [编辑器使用](mjcf-editor.zh-CN.md) |
| 打包模型、建立场景、搬迁、多实例 | [模型资源与场景](portable-models.zh-CN.md) |
| 将已保存设计安全应用到运行实例 | [运行安全编辑](runtime-safe-editing.zh-CN.md) |
| 暂停、单步、快照、两种重置、C# | [独立仿真时钟](runtime-clock.zh-CN.md) |
| 自由 G1、坐标/状态维度、接触实验 | [自由基座 G1](freebase-g1.zh-CN.md) |
| 精确命令、退出码、原始日志、GUI 复验 | [本阶段验证报告](freebase-clock-validation.zh-CN.md) |

## 既有证据与历史记录

- [环境重建控件反馈修复](rebuild-feedback-fix.zh-CN.md)：实际按钮失败原因显示、重试成功及 host/world 信号生命周期；保留 dot 的 137/139 独立验收限制。

- [应用编辑阶段验证](application-editing-validation.md)：F5 调查、属性编辑、运行事务的分阶段结果。
- [嵌入显示调查](embedded-display-investigation.md)：独立窗口和嵌入窗口证据；不要将关闭嵌入称为修复成功。
- [原生后端](native-backend-validation.md)、[动态世界](dynamic-world-validation.md)、[刚体姿态稳定性](rigid-transform-stability.md)：对应历史提交的测试，非当前提交重新执行结果。
- [portable 运行验证](portable-model-runtime-validation.md)、[资源边界修复](portable-edge-fixes.md)、[负向用例隔离](portable-isolated-rejections.md)：故意 ERROR 子进程和正常日志严格门槛的区别。
- [Apply/Discard 生命周期修复](editor-apply-fix.md)、[树选择恢复](tree-selection-fix.zh-CN.md)、[球柱 Size 按钮修复](primitive-size-fix.zh-CN.md)：dot 发现问题、真实 UI 路径及复验步骤。
- [Linux 早期恢复记录](headless-baseline.md)、[旧稳定性记录](stability-2a17810.md)、[WIP 草稿记录](freebase-wip.zh-CN.md)：保留历史上下文，不能推导 cold-import 稳定通过。

英文技术细节仍保留于 [MJCF 编辑器](mjcf-editor.md)、[高级属性](editor-advanced-properties.md)、[portable 模型](portable-models.md)、[运行编辑](runtime-safe-editing.md)、[动态世界](dynamic-world.md)。当前限制以中文入口和本阶段验证报告为准。

原始日志、数字结果和截图不翻译或修饰：[当前证据目录](evidence/freebase-clock/)、[原始日志 ZIP](evidence/freebase-clock/raw-logs.zip)、[哈希清单](evidence/freebase-clock/raw-log-manifest.json)。任何普通运行日志出现 ERROR/泄漏，即使退出 0 也失败。只有事先定义的独立负向子进程允许精确匹配的预期错误。
