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
