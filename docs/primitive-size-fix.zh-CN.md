# 新建球和圆柱的视口尺寸修复

dot 在 c3ca583 发现真实 UI 缺陷：`+ sphere` 创建的 size 为 `[.25,.25,.25]`，但写入验证要求球为 `[r,0,0]`。随后视口 `Size ×1.1` 保留无效的尾部值，导致提交被拒绝。圆柱同样存在第三分量不规范的问题。

修复统一三个入口：创建时使用球 `[r,0,0]`、圆柱 `[r,half_height,0]`；读取属性时规范化 MuJoCo 忽略的分量（兼容旧文档）；尺寸按钮只缩放有效分量并清零其余分量。球始终保持球形，禁止用非零尾部尺寸模拟椭球的原验证仍保留；fromto 派生尺寸仍只读。

新增回归按真实 UI 路径发出 `+ sphere` / `+ cylinder` 的 pressed 信号，再向视口发送鼠标选择事件，最后按 `Size ×1.1`。测试检查面板初值、编译尺寸、球形网格、undo/redo、保存重开，不用手工规范输入替代 UI 路径。

验证：`OUT=/workspace/shared/validation/primitive-ui-01 tests/editor_plugin/run.sh`，退出码 0，160 项通过。构建退出码 0。原始日志和结果见 [evidence/primitive-size-dot-fix](evidence/primitive-size-dot-fix/)。日志严格检查 ERROR 与泄漏。

dot 人工复验：

1. 新建球，在视口点球，确认右侧 size 为 `[0.25,0,0]`。
2. 连续点击 `Size ×1.1`，球均匀变大，字段和物理尺寸同步，无 unsupported 提示。
3. 撤销、重做、保存重开，确认尺寸一致，球未变为椭球。
4. 对圆柱重复以上操作，初值为 `[0.25,0.25,0]`，前两维同步变化，第三维保持零。

本修复不改变 cold-import 与宿主图形诊断的已知限制；自动测试不替代 dot GUI 复验。

原生回归：`OUT=/workspace/shared/validation/primitive-ui-native tests/native_backend/run.sh`，退出码 0，9 个独立进程共 447 项通过。dot 已报告 Box Move/Rotate/Size/undo 与 automatic→manual→automatic 惯量切换人工通过。dot 原始球问题截图：Library `libfile_f8ca951eafb8819186f88008d41160cb`；树高亮问题截图：`libfile_644e831c6dec81918811cc0daae78356`。这些为 dot 提供的证据标识，本次未重新抓取或修改。
