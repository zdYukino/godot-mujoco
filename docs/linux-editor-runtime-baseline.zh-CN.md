# Linux 编辑运行开发基线 · 2026-10-18

本基线保存用户批准范围内的 Linux 编辑与运行成果：**日常编辑、轻量真实 GUI 与运行编辑路径验收通过；重型 G1/多 G1 压力交由用户手测，不计为通过。** 这是开发基线，不是稳定 release。先更新开发分支并创建 `baseline/linux-editor-runtime-20261018`；用户随后明确授权将 main 非强制快进到同一文档提交，前提是远端 main 仍为 `bb1294e4f1d074d2a7c6a3852b428d83020ae5b3` 且是最终提交祖先。

验收产品来源为 `98baeb824a7aca6f55cfcd3019f86b58eecfec24`，tree `bfb0947f75762bcb9dcef27fc5b751bacc56faa2`；最终基线分支指向在其上增加本说明与证据的文档提交。该提交不修改产品或测试代码。固定 Linux x86_64、Godot 4.7.2.NET 官方 `ed1daf0bf`、MuJoCo 3.16.0；不修改引擎或 36 个原始 Unitree 资产。

## 验收范围及来源

**dot 原始报告直接核验：**通过 Library 正式取得[独立报告原文](evidence/dot-baseline-20261018/REPORT.zh-CN.md)和完整 ZIP，并核对 ZIP SHA256。dot 独立获取 264 个文件 blob，重新编译 11 个产品 C++ 单元（复用第三方 godot-cpp），GUI 后复核 21 个 addon 文件均未修改。[最终审计](evidence/dot-baseline-20261018/final-audit.json)记录三次编辑器、两个 API 进程实际退出码全为 0，正常日志 ERROR/SCRIPT ERROR/leak 均为 0。

**父任务核验转交的自动化矩阵：**36 资产核验、native 447、dynamic 86、editor 160、clock 118 及 C# 补充 33、G1 三绑定、资产迁移三轮、smoke 精准负例通过。此摘要来自父任务交接，不能将本页轻量 GUI ZIP 称为这些完整矩阵的原始证据。两次 SIGKILL 保留为未通过，未重跑或改写；不推测原因。

| dot 真实操作 | 已核验结果 |
|---|---|
| 首次 GUI 与重开 | 无项目 `.godot`、无 headless 预热；导入、damping=0.2、Apply、设计及资源保存；独立 GUI 重开保持 0.2。共享 SDK/XDG 缓存仍在。 |
| 已初始化 headless API | 编辑 12 项、独立重读 6 项通过；第三次 GUI 核对 damping=0.35、新增 api_box。无效输入/发布保护原状态与文件。 |
| pending、球柱与视口 | 上下重复点击并移开鼠标仍保留草稿及原选择；非法 Apply 拒绝，Discard 恢复；球柱 Size、undo/redo、移动/旋转、真实 3D 选择通过。 |
| F5/F6 | 整桌面捕获显示真实嵌入场景。不能用仅截编辑器父窗口的灰图认定子窗口未渲染。本轮未复验 standalone。 |
| 时钟、暂停与快照 | Step 9 得 0.018s；游戏时钟独立前进；运行再暂停、Reset 恢复快照及暂停状态。 |
| editor→runtime | 未保存设计 Apply 拒绝；保存后 revision 0→1；control=0.6 后摆杆运动，目标运行实例保持正确状态。 |
| 环境重建 | 无效候选失败后 world_id、完整模型状态及暂停不变；恢复有效资源后重建成功，时间归零。 |
| 正常收尾 | 子窗口正常关闭、Normal quit 标记、日志干净；编辑器外部脚本捕获 exit0。子进程 OS wait 退出码未独立捕获，不声称它们均有独立 exit0 证据。 |

运行采用工作区解包的官方 Debian Mesa 25.0.7-2+deb13u1，进程级环境配置；实际是 llvmpipe/OpenGL 4.5 compatibility、Dummy audio。没有修改系统驱动或引擎，也不是 Vulkan 渲染模式验收。配置说明见[图形宿主报告](mouse-gui-fix.zh-CN.md)。

## 保留失败、警告与使用约束

首次只读测试观察器在退出时访问已释放 plugin，产生 SCRIPT ERROR，即使 exit0 仍判失败；原始日志保留。仅修正独立观察器生命周期后，重新创建无 `.godot` 项目并复验，最终正常路径通过；产品代码未变。[观察器差异](evidence/dot-baseline-20261018/observer-lifecycle.diff)作为证据归档，不应用到本仓库测试代码。

VSync 不支持及独立夹具 UID 回退文本路径 WARNING 保留，不声称零警告。cold import 139 未解决，按用户授权非阻断；不能证明仅发生于无窗口模式，GUI 后已初始化 API 成功不等于 cold headless pass。重型 G1/多 G1 恢复压力未通过，用户手测前不承诺该规模性能、资源峰值或长期恢复稳定性。

保存的模型资源是设计状态；运行快照不自动导出为设计。F5 使用已保存主场景，不自动切换为刚修改的模型资源。运行 world 仍要求主线程物理模式，同步候选编译可能暂停 UI，不承诺后台无停顿。无需恢复受阻引擎研究；不扩展其他物理节点、地形或站立步行。

## 证据与后续入口

- [已知问题](known-issues.zh-CN.md)、[用户手测清单](linux-baseline-manual-checklist.zh-CN.md)、[中文使用指南](README.zh-CN.md)。
- [本地归档来源](evidence/dot-baseline-20261018/source.json)、[文件哈希清单](evidence/dot-baseline-20261018/manifest.json)、[原始日志目录](evidence/dot-baseline-20261018/)。
- [Library 原报告](https://chatgpt.com/api/library/files/libfile_e6858ea480cc81919825ffd26a9a2481/download)、[完整证据 ZIP（含截图、状态及脚本）](https://chatgpt.com/api/library/files/libfile_987db9e8dbac819195db14fc7bd7fed4/download)。ZIP SHA256：`116f63271d9790e62871cfb3417a54d278030edca684ec64db724d25136edd14`，2,801,447 字节。仓库保存必要文本证据；完整 ZIP 保持 Library 原件。
- [云端日常路径 24 项验证](daily-paths-baseline.zh-CN.md)与[此前完整回归记录](mouse-gui-fix.zh-CN.md)按各自版本、宿主及范围阅读，不能合称本轮全量人工验收。

本次只保存开发基线。dot 独立轻量验收已完成，不再标记为待验；不据此宣称 preview limit 已解除，也不将历史压力失败转为成功。用户已独立明确授权 main 快进；执行时使用 expected_sha 并禁止 force，若远端发生变化或不是快进则停止，不覆盖他人工作。此授权不改变上述验收边界，也不授权稳定 release。
