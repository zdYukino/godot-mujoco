# 共享世界原生视图

Linux x86_64 / X11 / Compatibility OpenGL 的可选显示后端。使用锁定的官方
Godot 4.7.2，普通 GPU 纹理合成不需要定制引擎。历史 R17 的直出屏幕实验仍见
[开发记录](../../../docs/development/native-view-r17/README.md)，编辑器选择器不启用该路径。

## 启用与交互

构建时使用 `-DGMJ_NATIVE_VIEW_EXPERIMENTAL=ON`，需要 OpenGL/X11 开发库。
生成的 `native_view/bin/bridge.gdextension` 随插件加载；OFF 构建会移除该注册文件。
编辑器右侧 MuJoCo 面板与 3D 显示菜单中的 **F5 渲染**选择保存到项目设置
`rendering/mujoco_native_view/renderer`：0 为 Godot，1 为原生，未设置沿用场景默认值。

两种渲染共用相机、拾取、选择、跟踪、施力及暂停姿态操作，使用 MuJoCo 3.16 的
`mjv_*` API。Tab / Shift+Tab 独立开关原版左右面板；**F11** 只打开 Godot 附加功能
（渲染选择、独立 FPS/系统性能、工具和示例）。F1 帮助，F2 仅 MuJoCo Info，
F3 Profiler，F4 Sensors。完整操作、状态语义、性能口径与 C# 接口见
[共享运行查看器](../viewer/README.md)。编辑器的设计操作及 Godot 快捷键保持原有行为。

`start_native_view()` / `stop_native_view()` 保留显式控制接口，浮窗也能临时切换后端。
启动失败显示实际原因并保留 Godot 画面。EnvironmentHost 的候选世界在提交前不会
争用显示租约；生成 playground 的 SubViewport 也使用相同交互核心。

## 数据与所有权

- 权威模型/数据始终属于 `MjPhysicsServer3D`，运行交互在安全命令边界执行。
- 主线程以 `mjv_copyData` 冻结真实可视化数据，生成包含接触诊断的 CPU `mjvScene`。
  拾取使用实际显示帧对应的数据；模型版本过期的输入会被拒绝。
- 渲染线程只拥有显示资源、共享纹理及值类型场景帧。它不会运行 `mj_forward` 或
  `mj_step` 来重新推导显示状态，也不独立处理相机或拾取。裸模型/数据指针不跨 DSO/队列。
- 模型修订变化时才传输受限 MJB。场景包包含 ABI 检查后的 geom、light、camera、flag
  等无指针值，以及可视化参数。积分状态仅保留兼容诊断与校验用途。
- GPU 共享纹理保留双向 fence、generation 确认和旧纹理延迟释放。确认画布替换后
  才释放旧导入；`finish()` 排空渲染队列。停止后同步回退姿态、相机和 viewport 状态。
- 打开/关闭浮窗不会暂停仿真；松键、失焦、后端切换及世界替换会取消扰动。
  扰动力作为独立贡献合成，不清空业务代码已有的外力。

底层 `scene_native_view_snapshot(space, known_revision, include_model, viewer_options)`
保留兼容入口，正常调用使用 include_model=true；只获取模型准入信息时可设 false。
桥接组件的修改方法要求主线程，提交前使用 `acquire_transport()` 与
`ready_for_request()`。邮箱只保留一个请求，不缓存模型数据包。`snapshot()` 是互斥保护的读取。
`step_ms` 仍是旧诊断字段，表示显示状态恢复/场景装载耗时，不能当作真实物理步耗时；
Profiler 使用权威积分步骤的毫秒计时。

## 能力与资源限制

支持一个系统游戏窗口、主线程物理和当前刚体模型范围。仅 F11 使用内嵌 Window，
原版左右面板和 F1–F4 使用同一视口内的 Control 及叠加，
不会创建第二个系统窗口。独立运行支持 F5 全屏；嵌入式 GameView 提示编辑器管理限制。
原生画面不混合 Godot 3D 深度、材质、Shader、粒子或天空；Godot 2D 控件继续叠加。

原生模型准入保持原有界限：最多 9000 geom、60 万网格顶点、100 万网格面、64 MiB
纹理，不包含 plugin、skin、flex。模型传输默认 64 MiB，可显式配置
`rendering/mujoco_native_view/max_model_mib` 为 1..192。显示模型/数据准入估算上限
256 MiB，积分状态载荷上限 8 MiB。解码后会独立复核数据大小。

G1 示例的模型传输超过默认 64 MiB；需要原生显示时，可显式将上述设置提高至 192 MiB。
未调整时会回退 Godot 并显示超限原因，不影响共享交互。

共享查看器在主线程借用当前版本的只读模型数组，自有模型头/三槽冻结场景/历史准入预算
为 256 MiB；历史最多 2000 个状态
且不超过 100,000,000 字节。输入在处理前固定对应显示帧，队列满时背压，不无限分配。
这些自有缓冲区限制不代表整个进程 RSS 或 GPU 驱动内存的硬上限。

GPU/CPU/内存指标是整机或整卡指标，ms 是耗时。不能根据原生模式保证更快：两种后端
都有公共场景生成成本，原生另有 GLX 切换、纹理合成与同步成本。请用实际场景比较。
不可恢复的 GL 上下文故障仍会终止游戏进程；这不是设备丢失恢复方案。

## 验证与来源

- `tests/runtime_viewer/run.py --native`：真实窗口、共享输入、权威状态操作、分析、输出与
  SubViewport 重载。省略 --native 测试 Godot；--headless 测试无图形路径。
- `tests/native_view/run.py`：编辑器选择器、真实 F5、设置持久化、实际渲染及失败回退。
- `bridge_step_calls` 由链接包装器记录桥内真实 mj_step/step1/step2 调用，正常值为 0。
  `GMJ_DIAGNOSTIC_STATE=1` 仍能比较积分状态恢复；原先 forward/故意显示步进阳性对照
  已退出正常显示路径。
- `GMJ_NATIVE_MEMORY_TRACE=1` 与 `GMJ_DIAGNOSTIC_MEMORY=1` 是诊断开关，性能采样时关闭。

MuJoCo simulate 适配版本和许可证见 `src/viewer/UPSTREAM.md`。
固定 godot-cpp 的 Dictionary 移动赋值问题继续由 `replace_dictionary` 规避；队列中的
模型数组使用 COW，显示模型用 `mj_loadModelBuffer` 直接解码。
