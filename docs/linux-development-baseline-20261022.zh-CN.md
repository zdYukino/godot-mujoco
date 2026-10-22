# Linux 开发稳定基线（2026-10-22，带已知限制）

用户批准将 dot 独立验收的 `2340cc2e04b3e8234bb614409fc0aaa2e405faca`
及其严格 smoke 前序提交收口进入 main。该提交是本次功能代码基准；收口提交仅更新文档。
这是限定使用范围下的开发稳定基线，不是全环境、全功能稳定承诺或发行包。

## 支持矩阵

| 范围 | 当前支持与边界 |
| --- | --- |
| 工具链 | Linux x86_64，官方 Godot 4.7.2 .NET、MuJoCo 3.16.0；主线程物理 |
| 普通 Godot 物体 | 原生 box/sphere/plane、刚体及 ray；不是完整 PhysicsServer 替代 |
| 模型 | portable MJCF 资源、同空间多实例、已有编辑属性与安全事务 |
| 圆柱 | MJCF 圆柱可编辑/模拟；原生 CylinderShape3D 不支持 |
| 地形 | 专用 MjStaticHeightField 固定网格静态高度场，显式安全增删替换、匹配可见网格与碰撞；通用 HeightMapShape3D、雕刻/动态形变/大地图不支持 |
| C# | WorldHandle / InstanceHandle 类型化门面、继承脚本、状态/revision/请求完成与旧句柄保护；Call/Get 动态方式仍兼容 |
| 尚未加入 | 地形专用编辑面板和类型化 C# 地形门面；后续功能分支独立验收，不自动合入本基线 |
| 不在范围 | Area/CharacterBody/全关节、站立步行、Windows、打包及导出分发 |

## 验收依据及版本归属

依据父任务提供的 dot 独立验收结果（证据包已交用户），不冒充本次重新运行：

- 最终 `2340cc2`：typed_control 69、heightfield 65、runtime_clock 118 + C#、严格 smoke 通过。
- native 149、editor 160、独立地形补充 26 项：在相关代码未变的版本通过；不把各历史计数合并成最终 SHA 全量重跑。
- 实际桌面：C# F6/重开、地形修改/Apply/暂停/删除重加/保存重开通过。
- 最终 GUI 使用工作区官方 Mesa 临时环境，日志无 ERROR/SCRIPT ERROR/leak，仅 VSync warning；不外推其他驱动或宿主。
- 开发端的具体命令、结果和失败复现：见 [P1/P2 审查记录](evidence/typed-review/README.md)、[高度场记录](evidence/static-heightfield/README.md)、[严格 smoke](../tests/mjworld_smoke/README.md)。开发端检查与 dot 检查分别记录。

## 保留限制

冷导入 139 未根治，当前约定流程中非阻断；失败导入后的 smoke 必须 not_run，缓存重试不算 fresh pass。
强制 MuJoCo 候选编译失败及内存分配失败未注入；非法输入拒绝不等于该回滚路径已验证。
G1/多 G1、迁移重负载与压力由用户接管，未据轻量结果宣称通过。
同步候选编译可能短暂停顿。dot Debian 13 构建的 ABI 不证明 Ubuntu 22.04 或通用 Linux 兼容。
远端 CI 不是验收门槛，不更改 Actions 权限或凭据；不将“无 run”写作 CI 通过。

## 历史与依赖

本次链条包含 PR #1 的 `5cf7c45` 严格 smoke、P1、P2 和 `2340cc2` 审查修正。
合入采用保留这些提交的 fast-forward，不重写历史。PR #1 的内容随祖先提交进入 main；其旧“等待远端 CI”描述不再作为门槛。
原 `baseline/linux-editor-runtime-20261018` 冻结于 `dfdfbbac9cd3217e6c9df5bfb3fa17c92388dd3e`，保持不动。
[2026-10-18 记录](linux-editor-runtime-baseline.zh-CN.md)继续作为历史证据；本次没有覆盖任何旧冻结分支。
