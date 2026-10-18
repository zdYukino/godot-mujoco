# Linux 开发基线：用户手测清单

入口：[开发基线范围与证据](linux-editor-runtime-baseline.zh-CN.md)、[已知问题](known-issues.zh-CN.md)。以下是交给用户的待验证清单，不代表已执行或通过；本轮文档归档不启动这些测试。

使用 `baseline/linux-editor-runtime-20261018`，记录实际 commit、官方 Godot/MuJoCo 版本、宿主驱动、启动参数。先备份设计文件；原始 Unitree 资产不修改。保留每次原始日志、整桌面截图、耗时、运行次数与退出码；进程被 SIGKILL/137 或出现 ERROR/SCRIPT ERROR/leak 即记为失败，不从 exit0 或后续重试推导通过。

## 重负载与恢复（用户负责）

- [ ] 按[自由基座 G1 指南](freebase-g1.zh-CN.md)观察长时间接触、摩擦与碰撞；分别记录固定/自由基座配置，不将此解释为站立或步行控制。
- [ ] 逐步增加 G1 数量及多个 world，记录模型数、运行时长、帧耗时和内存峰值；达到宿主资源边界时保存失败证据，不推测 SIGKILL 原因。
- [ ] 多实例循环删除/重加、暂停/恢复、保存设计并 Apply；核对实例标识、revision、控制和兼容状态连续性，确认其他实例不串扰。
- [ ] 重负载下非法结构/惯量候选及环境重建失败保留原 world/state/暂停状态；纠正后重试，记录每一步反馈。
- [ ] 多机器人场景保存、正常退出、重新启动，核对设计资源与仿真快照的区别；验证运行现场不会被误写为设计。

## 尚未逐项人工覆盖的边界

- [ ] joint limit、damping/friction、body inertia 自动/手动规则与非法物理参数；frame/fromto 派生字段和只读属性不被错误回写。
- [ ] 场景资源赋值、undo/redo/save/reload 一致；过期请求、选择切换、重复 Apply/Discard、多实例隔离和删除重加。
- [ ] 在自己的桌面分别核对 F5 嵌入及 standalone；捕获整桌面，避免仅截父窗口遗漏游戏子窗口。

轻量 pending 树选择、球柱尺寸/3D、API 保存重读、运行 revision/control、单步快照及环境失败回滚已有 dot 证据，可作对照；不是以上重负载与边界项的替代证明。冷导入 139 继续作为非阻塞遗留，不要求本次手测开展引擎调试。
