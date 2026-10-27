# 例程目录 / Examples

在仓库根目录完成 `./boostup.sh` 后，执行 `./em_run.sh --exp` 选择例程，或按表中名称直接打开。
每个可直接打开的例程都有自己的 `project.godot`；在编辑器中按 F5 运行。

After running `./boostup.sh` from the repository root, use `./em_run.sh --exp` to choose
an example, or pass its name directly. Each ready example has its own `project.godot`.
Press F5 in the editor to run it.

| 目录 / Directory | 启动 / Launch | 内容 / Purpose |
|---|---|---|
| [shape_gallery](shape_gallery/README.md) | `./em_run.sh --exp shape_gallery` | 共享物理世界中的形状下落与碰撞 / Falling shapes and collisions |
| [g1_passive](g1_passive/README.md) | `./em_run.sh --exp g1_passive` | 无控制自由基座 G1 倒地 / Uncontrolled free-base G1 |
| [sdf_terrain](sdf_terrain/README.md) | `./em_run.sh --exp sdf_terrain` | SDF 台阶、洼地与崎岖地形 / SDF terrain |
| [pendulum](pendulum/README.md) | `./em_run.sh --exp pendulum` | 独立 MjWorld 的旧版摆杆及诊断场景 / Independent MjWorld pendulum and diagnostics |
| [light_workflow](light_workflow/README.zh-CN.md) | `bash examples/light_workflow/run.sh` | 开发者 C# 例程，需生成模型、构建 C# 后打开脚本输出的工程 / Generated C# developer workflow |
| [_shared](_shared/README.md) | 共用素材，无工程入口 / Shared resources, no project entry | 天空、地板着色器和界面脚本 / Sky, floor shader and UI script |
| [templates/new_project](templates/new_project/README.md) | `./em_run.sh --new project-name` | 新工程模板，由启动器填入名称并复制插件 / Template populated by the launcher |

插件源码和编译产物统一位于根目录 `addons/`，原始机器人资产位于根目录 `assets/robots/`。
四个可直接打开的例程通过向导生成的 `addons -> ../../addons` 链接共享插件；天空、地板和
共用脚本的相对链接指向 `_shared/`，例程不再相互依赖，也不依赖旧 `demo/` 目录。
`pendulum/assets -> ../../assets` 让旧诊断工程也能访问共享机器人资产。

Addon source and binaries live in the repository-root `addons/`, and original robot
assets live in `assets/robots/`. The four ready projects share the addon through links
created by setup. Common visual assets link into `_shared/`; projects no longer depend
on another example or on the former `demo/` directory.

保留完整仓库后直接打开例程；需要独立的新工程时使用 `./em_run.sh --new project-name`，
它会复制插件。`.godot/`、生成的插件链接和 .NET 构建产物被 Git 忽略，源码、模型包及必要资源继续维护。

Keep the repository layout intact when opening examples. Use `--new project-name` for
a separate project with copied addons. Import caches, generated addon links and .NET
build output are ignored; source, model packages and required assets are maintained.
