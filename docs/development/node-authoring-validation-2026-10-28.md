# MJCF 作者节点第一阶段验证（2026-10-28）

工作区候选已实现正式 body / geom / joint 场景树、完整作者 XML 与稳定身份、Inspector / Gizmo / Undo / 保存、隔离编译以及编辑器到共享运行世界的原子更新。五个例程和新工程模板已迁移，原场景的相机、灯光、材质、地形及 G1 摆放保留。用户已有 shape_gallery 的 UID 修改经基线比对保持。

## 已执行结果

| 范围 | 结果 |
|---|---|
| 作者数据与编译服务 | 42 检查通过：旧文档/包依赖复制及初态、默认类、fromto、Euler、依赖闭包、复制/改名、无效保存、进程超时/强杀/恢复/过期结果 |
| 共享世界异步重建 | 33 检查通过：暂停、时间/状态迁移、带显式初态的稳定 ID 改名、无效候选回滚、轴/类型重置、checkpoint 迁移、取消/恢复 |
| 实际 EditorPlugin | 15 检查通过：旧场景整体升级、正式节点所有权、typed Inspector、原生 Undo/Redo、保存重开、被动显示不产生编辑循环、F5 gate |
| 实际 debugger 编辑器/游戏连接 | 16 检查通过：源修改暂停真实物理、原子提交、手动继续、游戏复制/地形命令、编辑器 Undo/Redo 和保存 |
| 五个直接打开例程与模板 | 109 检查通过：shape 15、单 G1 21、SDF 15、三种 pendulum 演示 38、C# light 9、模板 11 |
| 原生物理后端回归 | 149 检查通过，三个独立进程，无 ERROR / 泄漏 |
| 既有时钟与 C# API | 118 检查及 C# binding 通过 |
| 独立 MjWorld | 严格 smoke、负向与审计测试通过 |
| 安装/启动器 | 42 个 unittest 通过，包含第五例程与新模板 |
| 实际 GUI | 9 类操作通过，见下文 |

汇总及原生库 SHA256：[results.json](node-authoring/results.json)。GUI 在独立 X11 显示会话、真实 Godot 编辑器和 llvmpipe 渲染下使用 XTEST 鼠标/键盘完成，未用 headless 或直接调用作者命令替代鼠标操作：

- 点击右侧载入按钮和原生文件对话框导入 MJCF。
- 检查正式场景层级；Ctrl+D、Ctrl+Z、Ctrl+Shift+Z 复制/撤销/重做。
- 实际拖动胶囊几何的原生 X 轴 Gizmo，只提交一次作者修改；形状种类和未选中副本保持正确；撤销/重做还原源位姿。
- 展开原生 Inspector 参数组，通过鼠标和键盘把关节 damping 改成 0.3。
- Ctrl+S 后关闭编辑器，以独立新进程重开；层级、设计位姿、damping 和身份全部保留。

[Gizmo 截图](node-authoring/gizmo.png) · [Inspector 截图](node-authoring/inspector.png) · [GUI 结果](node-authoring/gui-results.json)

## 可重复入口

```bash
python3 tests/node_authoring/run.py --godot "$GODOT_BIN" --out /tmp/gmj-author-check
python3 tests/example_projects/run.py --godot "$GODOT_BIN" --out /tmp/gmj-example-check
OUT=/tmp/gmj-native-check REPEAT=1 bash tests/native_backend/run.sh
OUT=/tmp/gmj-clock-check bash tests/runtime_clock/run.sh
python3 tests/mjworld_smoke/run.py /tmp/gmj-independent-check
python3 -m unittest discover -s tests/setup -p 'test_*.py'
OUT=/tmp/gmj-light-check bash examples/light_workflow/run.sh
```

使用新输出目录；node authoring 的 live 阶段会由真实编辑器启动游戏进程，需要图形会话，可用 `xvfb-run -a` 隔离显示。CI 已加入该验收入口。GUI 观测与鼠标驱动在 `tests/node_authoring/gui_probe.gd` / `gui_actions.py` / `desktop.py`；固定 1600×1000 显示尺寸，import、duplicate、gizmo、inspector、save、独立重开后的 reopen 分阶段执行。

原始日志目录：`/tmp/gmj-node-authoring/final4`、`/tmp/gmj-direct-examples/final2`、`/tmp/gmj-node-regression/`、`/tmp/gmj-node-gui/v3`。各阶段记录真实退出码，ERROR / SCRIPT ERROR / 泄漏判失败。前期失败排查使用了不同隔离目录，保留原失败日志；这些是新项目缓存测试，共享工具和宿主仍复用，不等于独立冷环境稳定性认证。

## 保留边界

单 G1 是必验项；双 G1 热加只提供可取消、默认 120 秒超时的诊断，不宣称跨宿主热加通过。原有超过 150 秒的双 G1 失败与旧冷导入 139 未被标记修复。复杂 frame 缩放/继承、SDF/heightfield 专用编辑路径、共享世界不接纳的插件/flex/skin/mocap/userdata/keyframe 等边界见[使用指南](../node-authoring.zh-CN.md)和既有已知问题。
