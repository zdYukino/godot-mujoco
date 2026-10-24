# 静态高度场编辑面板

启用现有 MuJoCo Model Editor 插件，打开底部 **MuJoCo 地形** 面板。范围仍为
Linux x86_64 / Godot 4.7.2 .NET / MuJoCo 3.16；复用专用静态高度场，不支持
通用 HeightMapShape3D、雕刻、动态形变或大地图。

打开 Node3D 场景，未选地形时设置宽/深并点「创建地形」。选择场景树中的
MjStaticHeightField 后，在文本框按行输入高度（米）。已有节点分辨率固定，
高度数量必须为宽×深，允许有限的 ±10000 米数值。Layer/Mask 为 32 位掩码。

- 「预览草稿」只显示临时网格，不改场景设计。草稿未应用时切换选择会拒绝并保留原目标。
- 「应用到场景」将资源副本及掩码写入选中节点，进入 EditorUndoRedoManager；重复应用无变化不产生动作。
- 「撤销场景编辑」使用该场景的撤销历史，可能撤销其最近一次其他场景动作；也可使用编辑器原生 Undo/Redo。
- 「Discard」恢复当前场景设计，移除临时预览；不撤销已经接受的运行请求。
- 「保存场景」保存设计，不保存仿真状态；首次场景路径使用编辑器另存为。保存省略缩略图以支持 headless 验收。

启动 F5/F6 后，在运行实例下拉框按路径和唯一 ID 选择目标，再点「应用到运行实例」。
它发送当前草稿、姿态及掩码；不要求先保存项目，也不会自动保存运行修改。
「移除运行地形」仅请求移除该运行实例的碰撞/网格，不删除编辑器节点。
状态行同时显示设计 dirty、运行 revision、pending 和 error。接受入队与完成不同；
pending=false 且无 error 表示最近请求已完成（或实例初始空闲），active 状态见运行节点。
切换运行目标后回包仍按唯一 ID 隔离，重复点击 pending 目标被拒绝。

通信使用 Godot 原有 EditorDebuggerPlugin 会话；运行节点复制请求后走已有物理步边界事务。
显式 revision 和 native owner 检查不跳过。删除/重加会更换 live ID，过期消息不能修改新实例。
节点 state() 会先获取已完成的结果，保证显示的已提交设计和 revision 对应。

## 轻量验收

使用已构建的固定 native 库，无需为本阶段重建 C++：

```sh
OUT=/tmp/terrain-panel-new bash tests/heightfield_panel/run.sh
OUT=/tmp/terrain-runtime-new bash tests/heightfield/run.sh
```

前者真实加载 EditorPlugin，检查创建、预览不改设计、选择切换、重复应用、撤销、
Discard、非法文本/数量、保存重开及 pending/会话停止的拒绝。后者包含运行桥接入口、
复制请求、重复请求、过期/缺失 revision、移除后的旧 ID 拒绝及新 ID 重加。
运行桥接自动测试直接调用接收入口；实际编辑器↔游戏调试会话传输仍由 dot GUI 验收，
不能将它表述为已测网络/调试器端到端。

dot GUI：打开轻量高度场示例或保存的运行场景，选中地形打开底部面板，编辑一个角点，
预览、应用到场景、Undo/Redo、保存重开；启动运行，选择正确实例应用相同草稿，重复点击，
切换两个实例，暂停后应用、移除/重加；确认 dirty/pending/error 与可见碰撞一致。
验证 Discard 不会撤销已入队事务，停止游戏后运行目标消失。保留截图与日志。
冷导入 139 和强制候选编译/分配失败未注入等既有限制不变。

## 外部编辑、冲突与运行反馈

面板按当前场景设计快照检测原生 Undo/Redo、Inspector 属性及资源内数组修改；不依赖
自定义 Resource 必须发出 changed 信号。无草稿时自动同步字段和基线；Apply/保存前也
同步检查，避免同一帧里的旧字段被误当作无变化。

已有草稿时外部变更不会覆盖文本，面板清除临时预览、显示 conflict 并阻止 Apply/保存。
可 Discard 采用当前场景，或明确点击「保留草稿并采用当前基线」，再 Apply 覆盖当前设计。
后者产生的撤销恢复外部编辑后的值；外部改变分辨率时不自动裁剪草稿，需要先复制文本再
Discard。原生 Undo/Redo 与面板操作使用同一场景历史。

运行结果每次按选中的 session/实例 ID 读取：pending 优先，无结果显示 idle，结果属于
其他目标时不显示。实例移除后仅为当前选择保留明确标注“已移除”的完成项；session 停止
后清除结果与选择。场景草稿错误和运行结果分别显示，不复用同一个全局错误后缀。

操作区自动换行，长状态行折行，目标菜单固定最小宽度且不随最长 ID 撑宽；显示 ID 尾部，
完整路径/ID 在提示中。dot 请补验 1152px 宽度下所有按钮可点击、长 ID 列表、Stop 清理，
以及原生 Ctrl+Z/Ctrl+Shift+Z 后再次 Apply/Save 的显示与磁盘一致性。

## 地形摩擦

选择场景里的 MjStaticHeightField，在 Inspector 的 Physics Material Override 新建 PhysicsMaterial，设置 Friction（0..1）和 Rough，Bounce 保持 0。保存场景可持久化材质；运行中的修改需沿用本面板 Apply 或 request_apply() 才提交，等待完成结果和新 revision。普通 HeightMapShape3D 则使用所属 StaticBody3D 的相同材质入口，资源变化自动触发物理边界重建。详见[地形材质规则与验证](native-heightmap.zh-CN.md)。

面板现有独立的 Friction / Rough 草稿控件。Inspector 改材质时，干净面板同步新值；已有未提交草稿时标记冲突并保留草稿，必须 Discard 或明确“保留草稿并采用当前基线”。后者保留旧草稿材质，下一次 Apply 将有意覆盖当前场景材质。应用到场景将网格、掩码和材质放入同一 Undo/Redo 动作；面板保存前必须提交草稿。运行 Apply 显式发送带符号 friction 与 bounce，不再依赖运行实例旧材质补全；它不会自动保存场景。

编辑器到运行回归：`GODOT_BIN=/path/to/godot OUT=/tmp/terrain-panel bash tests/heightfield_panel/run.sh`。包含 fake-debugger 实际 payload 检查，并在独立运行进程通过真实 Bridge/Apply 将运行旧值 0.23 替换为编辑器发送的 0.67，检查最终 MJCF 接触值。dot 仍应在真实 F5/F6 会话用 Inspector 从 0.23 改为 0.67 后点击“应用到运行实例”，确认 revision、完成结果与运行材质；检查 Undo/Redo、草稿冲突、保存关闭重开。
