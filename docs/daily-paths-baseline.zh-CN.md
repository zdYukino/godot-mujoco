# 日常编辑路径与基线门槛调整

验证对象：`ce7378f24c3b56e2baaa2b3867a77cf60abe7b73`，Linux、官方 Godot 4.7.2.NET、MuJoCo 3.16.0。此次仅增加测试与文档，没有修改应用、引擎或 Unitree 资产。按用户最新授权，两条日常路径通过后，cold import 139 作为**未解决、非阻塞遗留问题**保留，允许进入基线提交评审；这不是自动发布稳定版本或合并 main。

不能断言 139 只发生在无窗口编辑器。历史明确复现的命令是 `godot --headless --editor --path PROJECT --import`；本轮 GUI 成功只证明所测条件下的路径可用，不能排除其他 GUI/宿主/模型条件下的问题。历史失败与完整冷环境压力结果保留在[旧稳定性报告](stability-2a17810.md)；本轮不开展引擎调试，也不重跑该研究。

## 实际验证

| 路径 | 操作和独立验证 | 检查 | 退出码 |
| --- | --- | ---: | --- |
| 首次 GUI | 项目无 `.godot`，直接打开图形编辑器，无 headless 预导入；真实鼠标键盘 Import MJCF、选 hinge、改 damping 为 0.2、Apply、保存设计 JSON 和项目资源，正常退出 | 3 | Godot 0、输入程序 0 |
| GUI 重开 | 新进程真实 Open document，核对 damping 0.2，正常退出 | 1 | Godot 0、输入程序 0 |
| 无窗口 API 编辑 | 已初始化项目加载已有 `.tres`；改 damping 为 0.35、新增 api_box/api_box_geom；发布新资源版本并保存设计 JSON；负质量和非法发布路径拒绝后核对文件哈希不变 | 12 | 0 |
| 无窗口独立重读 | 另一个进程重新加载新 `.tres` 与 JSON，核对属性和新增实体一致 | 6 | 0 |
| API 后 GUI 核对 | 新图形进程实际打开设计文档，核对 0.35 与 api_box，正常退出 | 2 | Godot 0、输入程序 0 |

合计 **24 项通过、0 失败；8 个入口进程全部 exit 0，全部日志零 ERROR/泄漏**。GUI 使用 X11 :91、1600×1000、gl_compatibility、Dummy audio 和[已记录的正常软件驱动配置](mouse-gui-fix.zh-CN.md)。首次项目缓存不存在，但共享 SDK/XDG 缓存保留；使用轻量 pendulum MJCF，因此不是所有缓存清空的冷环境压力证明，也不是本轮重新验证完整 G1 矩阵。

API 编辑是 GDScript 程序对已有设计资源的读写，不是无窗口交互界面。资源包采用不可变哈希版本：成功编辑发布新包，原 `.tres` 保持字节不变；设计 JSON 使用临时文件和原子替换更新。保存的是**设计状态**，不是仿真快照。失败检查覆盖编辑前后文档快照及已保存文件 SHA256；独立进程验证实际落盘结果。

## 复现与证据

- [测试与 GUI 操作步骤](../tests/daily_paths/README.md)、[API 测试](../tests/daily_paths/api_edit.gd)、[真实输入脚本](../tests/daily_paths/gui.py)。
- [命令、参数、环境与退出码](evidence/daily-paths/commands.json)、[首次缓存条件](evidence/daily-paths/fresh.json)、[汇总](evidence/daily-paths/summary.json)。
- [API 编辑断言](evidence/daily-paths/api-edit.json)、[独立重读断言](evidence/daily-paths/api-verify.json)、[全部日志和 UI 状态](evidence/daily-paths/logs-and-states.zip)、[SHA256 清单](evidence/daily-paths/manifest.json)。
- 截图：[首次保存](evidence/daily-paths/first.png)、[GUI 重开](evidence/daily-paths/reopen.png)、[API 后 GUI](evidence/daily-paths/api-gui.png)。

本轮没有重复无关全量测试；此前 native/dynamic/editor/portable/G1/C# 等矩阵仍见[上一报告](mouse-gui-fix.zh-CN.md)。其他缺陷、dot 独立验收与 preview limit 未被豁免或解除，历史 137 原因仍未明。基线提交及 main 决策由父任务按剩余门槛评审；本分支不自行合并 main。具体遗留事项见[已知问题](known-issues.zh-CN.md)。
