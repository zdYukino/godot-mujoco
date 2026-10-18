# 已知问题与适用范围

## 冷导入退出 139：未解决，按用户授权非阻塞

历史在独立新项目、私有 XDG data/config/cache 下运行官方 `godot --headless --editor --path PROJECT --import`，两次退出 139；命令与结果见[历史报告](stability-2a17810.md)。dot 在 e16a4ec 上也报告 clock fresh import 139、未进入功能测试，见[独立验收记录](freebase-clock-validation.zh-CN.md)。这些历史失败不删除、不改写为通过。

[当前候选的日常路径验证](daily-paths-baseline.zh-CN.md)已证明：项目无 `.godot` 时直接 GUI 导入、编辑保存重开可用；初始化后的项目可以通过 headless 脚本/API 修改已有设计资源，另进程与 GUI 均读到保存结果。因此按用户明确调整的门槛，此项列为非主要、非阻塞遗留问题，允许继续基线评审。**并未修复 139，也没有证据证明它仅发生在无窗口模式。**

建议日常先使用正常图形编辑器初始化项目，再对已有项目运行 headless API 编辑。保留设计文件备份、失败命令及原始日志。若失败后在初始化项目中成功运行，须标为恢复/已初始化路径，不能将缓存重试称作 fresh pass。本轮不涉及引擎补丁、内存研究或替换官方 binary。

## 其他门槛仍保留

- dot 历史运行退出 137 的原因未明，不能猜测为 OOM；本次没有豁免这一独立结果。
- dot 的 preview limit 没有解除；云端真实 GUI 证据不等于 dot 对最终候选的独立 GUI 验收。
- 早期云端缺少 Vulkan ICD 的 ERROR 日志仍按严格失败保留。正常官方软件驱动配置后的云端 GUI/F5 验证通过，详见[图形宿主报告](mouse-gui-fix.zh-CN.md)，但不能推广为所有 Linux 宿主均通过。
- 任何新 ERROR、SCRIPT ERROR 或泄漏即使 exit 0 仍须判失败。本次门槛调整只针对已记录的 cold import 139，不豁免其他缺陷。
