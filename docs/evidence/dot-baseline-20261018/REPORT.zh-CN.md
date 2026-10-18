# 98baeb8 独立 dot 轻量真实 GUI 验收

2026-10-18 UTC。结论：本次约定的轻量 GUI 路径通过，最终三次编辑器正常退出均为 0，完整正常运行日志没有 ERROR、SCRIPT ERROR 或 leak。重型 G1/多 G1 按用户最新决定交由用户手测，未在本次重新启动。此结论不是所有历史要求的全量人工覆盖证明。

## 精确版本与运行条件

- 仓库 zdYukino/godot-mujoco，分支 codex/freebase-simulation-controls。
- commit `98baeb824a7aca6f55cfcd3019f86b58eecfec24`；tree `bfb0947f75762bcb9dcef27fc5b751bacc56faa2`。
- 团队独立 GitHub MCP 获取的 264 个源码、测试、文档、资产 blob 校验见 source-provenance。GUI 使用其 demo/addons；结束后 21 个已跟踪 addon 文件再次逐项 SHA256 校验一致，产品源码没有修改。
- Godot 4.7.2.NET 官方 ed1daf0bf，SHA256 `fc1bd592b5e771c65d52968f99835b4f2b7fe7b7cbc141e202cb63e01c95ec4d`。
- 所有 11 个产品 C++ 翻译单元重新编译，复用第三方 godot-cpp 库。GUI 实际 native SHA256 `08eecb11451c50090a54447242cdd4a68ae1018dce5995e8f2a8f1302cf25f38`。
- MuJoCo 3.16.0 SHA256 `d89b5532a1ec9c4ca8744449d648233a2f7ae5d9e7b2ccddd692e11955f6cb04`。
- Linux dot 云桌面。官方 Debian Mesa 25.0.7-2+deb13u1 包仅解包到工作区；包 SHA256 `caf2f7d296b7522efe74e40a74bce762a3ce84c33b53b5e54e1248ac2e0a13a5`，ldd 依赖满足。启动器仅给测试进程设置 VK_DRIVER_FILES 与 LD_LIBRARY_PATH。没有改系统驱动或引擎。
- 实际日志为 llvmpipe / OpenGL 4.5 compatibility，Dummy 音频。无 Vulkan ERROR。不把此结果称作 Vulkan 渲染模式验证。软件驱动不支持 VSync 的 WARNING 留存。

## 人工 GUI 与真实子进程结果

| 路径 | 实际观察及证据 |
|---|---|
| 新项目首次 GUI 初始化 | first/launch.txt 明确 .godot 不存在；真实编辑器导入 pendulum.xml、修改 hinge damping=0.2、Apply、保存 daily.gmj.json 和便携资源。没有用 headless import 预热此项目；共享 SDK/XDG 缓存仍存在。first/editor.exit=0，日志干净。 |
| 保存后独立重新打开 | 新 GUI 进程 Open document，hinge 仍为 0.2；reopen/verified-0.2.png、verified-state.json。正常退出 0。 |
| 已初始化 API 编辑 | 无窗口 api-edit 12 项、另一进程 api-verify 6 项，均 exit0/无错误；包括无效质量/路径拒绝、拒绝后状态和原文件字节保留、不可变资源发布。随后第三个真实 GUI 看到 damping=0.35 与 api_box。不是 cold headless pass。 |
| pending 树选择 | 输入 bad 后点击上方 arm、下方 arm_geom、重复上方并移开鼠标，原 hinge 高亮/选择与 pending 字段保留。Apply 无效输入被拒绝，模型 damping 仍 0.35；Discard 恢复 0.35、清 pending。tree-*.png/json、invalid-apply.json。 |
| 球/柱尺寸和 3D | 球 Size×1.1 得 [.275,0,0]，Ctrl+Z 回 [.25,0,0]，Redo 恢复；柱得 [.275,.275,0]。分别沿本地 X 移动 ±0.5，柱旋转 5°；真实 3D 点击球选中其 geom。sphere/cylinder/3d-*.json/png。 |
| F6 和 F5 嵌入画面 | 真实整桌面像素显示地面、摆杆、球、柱与控制面板。F6 当前场景与 F5 主场景都成功显示。不能再以 editor-only 截图遗漏子窗口作为灰屏证据。runtime-f5-main.png 等；本轮未复验独立窗口模式。 |
| 游戏时钟/仿真时钟 | 暂停时游戏秒数继续增长；Step N=9 后仿真 0.018s。捕获该快照、恢复运行后暂停到 9.268s，再 Reset 回 0.018s 和捕获姿态，保持暂停。runtime-step9/reset-snapshot/paused-after-resume.png。 |
| 相机/成功 Rebuild | 暂停中相机缩放有效；成功 Rebuild 回 0s、初始环境/相机，暂停保持。runtime-paused-camera/rebuilt.png。 |
| editor→runtime 结构事务 | 未保存结构被 Apply 明确拒绝、revision 仍 0；保存资源后 Apply，真实 runtime revision 0→1 Ready，Saved resource matches；恢复游戏窗口仍暂停。live-unsaved-rejected/revision1.png。 |
| editor→runtime 控制 | 编辑器 position_drive=0.6，Send selected control 到真实子进程；恢复仿真后摆杆实际倾斜，暂停在 14.350s。live-control-sent/motion.png。 |
| Rebuild 失败保留/恢复 | 独立轻量测试按钮把保存环境替换为无效根 Node，再点击产品 Rebuild。产品 UI 拒绝；前后 world_id 与完整模型 state 一致，原暂停保留。恢复有效资源后 Rebuild 成功，新 world_id，时间 0。before/after-*-rebuild.json 与对应截图。 |
| 正常收尾 | 两次独立夹具 Normal quit 后真实子窗口关闭，日志 LIGHT_GUI_NORMAL_QUIT，编辑器提示无 runtime 连接；最终 Ctrl+Q 正常退出，api-gui/editor.exit=0。没有杀进程。 |

设计保存资源与运行状态分别保留：最终设计保存 `model_1fca0dfd4cc8b19b46f8e6f17f0f7bff3865f5da0eaab1985cc4eccd8ce7e430/model.tres`，控制 0.6；运行快照和运行中位置没有被当作设计导出。lightplayground.tscn 是此前保存的初始场景，F5 只用于该场景渲染验证，不声称自动变成最新设计资源。

## 严格日志与测试观察器修正

首次尝试 first-attempt1 正常保存退出时，独立只读观察器调用已释放 plugin，产生 SCRIPT ERROR；该次即使 exit0 也判为失败，原日志完整保留。随后只在独立测试观察器增加实例有效性检查及 plugin tree_exiting 断开 process_frame；未修改产品 addon。重新创建无 .godot 的项目，重跑首次 GUI 保存/退出、独立重开及后续退出。修正后的三个 GUI 进程与两个 API 进程均实际 exit0，日志无 ERROR/leak，详见 final-audit.json、observer-lifecycle.diff。

失败夹具第一次加载存在 ext_resource UID 无效、回退文本路径 WARNING；这是独立夹具资源元数据警告，未屏蔽，产品正常日志里完整保留。其功能加载成功。除此与 VSync 提示外，不声称完全无警告。

编辑器启动的 runtime 子进程没有独立捕获 OS wait 退出码，因此只报告实际窗口关闭、Normal quit 日志标记及干净日志；不把夹具调用 quit(0) 意图冒充独立捕获的退出码。编辑器和 API 的退出码则由外部启动脚本实际记录。

## 未测与边界

- 用户手测：G1 自由基座/接触摩擦/碰撞长时行为、多 G1/多 world 重负载。此前其他独立组的 SIGKILL/137 没有被本报告改写为通过。
- 本轮未逐项人工复验 joint limit、body inertia 自动/手动、全部 friction/framefromto 边界、scene 赋值 undo/save、stale request、多实例隔离、实例删除重加及 standalone 显示模式。应结合其他自动化证据，不标为本轮手工通过。
- cold import139 仍未解决，按用户决定是非阻断遗留。本次只证明正常 GUI 初始化与随后已初始化 API 编辑路径。
- 小型球/柱/摆杆能渲染并仿真，不外推 G1 规模的性能或资源峰值。
- 当前约定轻量范围没有发现剩余产品 ERROR 或 leak；是否提交基线由主任务结合其余证据判断。

## 证据索引

截图均来自真实 dot 整桌面，不是无窗口渲染。first/reopen/api-gui 为按顺序独立 GUI 运行；api-edit/api-verify 是无窗口。evidence ZIP 包含原始日志、实际退出码、状态 JSON、所有截图、独立测试脚本、保存的轻量资源、版本与校验记录；不含大型二进制或 .godot 缓存。原失败尝试也包含，不能与最终正常运行混为一谈。
