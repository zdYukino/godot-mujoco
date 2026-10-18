# Linux 安装与故障边界

使用 Godot **4.7.2 .NET 官方二进制**、MuJoCo **3.16.0**。本分支只验收 Linux x86_64；不要根据旧 CI 平台列表宣称其他平台可用。

## 构建和导入

准备 CMake ≥3.24、C++17 编译器；首次配置需要联网下载固定依赖。C# 需要 .NET SDK 8。

```sh
cmake -S . -B build -DMUJOCO_VERSION=3.16.0
cmake --build build -j4
export GODOT_BIN=/实际路径/官方Godot二进制
"$GODOT_BIN" --version
GODOT_BIN="$GODOT_BIN" scripts/import_headless.sh demo
"$GODOT_BIN" --editor --path demo
```

期望引擎版本为 `4.7.2.stable.mono.official.ed1daf0bf`。扩展与 MuJoCo 运行库放入 `demo/addons/godot_mujoco/bin/`；库通过相对路径加载。godot-cpp 的 API 目标 `godot-4.5-stable` 与实际验收引擎版本不同，不要换成旧引擎进行“等效验收”。不同 MuJoCo 版本使用不同 build 目录。

要在另一 Godot 项目使用，复制 `demo/addons/godot_mujoco` 和 `demo/addons/mujoco_editor`，包括 bin 中的库。选择项目 3D Physics Engine 为 MuJoCo，重启，再启用 `mujoco_editor` 插件。模型资源目录及 assets 必须一起复制。导入结束后顶部会出现 MuJoCo 工作区。

## 首次导入与 F5

cold-import 139 是已知独立限制。辅助脚本只对一次官方引擎导入增加 frame delay；它不是引擎修复。每次验收使用新 OUT 目录，保留首次命令、退出码和完整日志；缓存后的成功重试不能替代首次失败。不要修改引擎或接手此前受阻的内存补丁研究。

无声卡云主机的这些物理示例使用项目 `audio/driver/driver="Dummy"`，确保 F5 子进程也继承设置。GL Compatibility 是已验证的渲染选项。分别记录最小普通 Godot 场景、MuJoCo 场景、嵌入和独立窗口的启动参数与截图；关闭嵌入只能作为独立窗口使用路径，不能据此宣称嵌入问题修好。

本阶段实际独立窗口无 ERROR/泄漏，退出 0；编辑器 GUI 仍报告宿主 Vulkan surface 探测 ERROR，严格 gate 失败。详见 [报告](freebase-clock-validation.zh-CN.md) 和 [早期嵌入调查](embedded-display-investigation.md)。

## 运行模式

`MjRuntimeWorld` 要求 `physics/3d/run_on_separate_thread=false`。暂停 MuJoCo 请使用其仿真 API，不要暂停整个 SceneTree 或把 Engine.time_scale 设为零，否则游戏 UI、输入和命令处理也可能停止。

目前验证的是文件系统项目搬迁；未承诺 PCK/ZIP 内 MuJoCo 外部资产直接加载。先完成普通项目独立运行，再考虑未验证的导出路径。
