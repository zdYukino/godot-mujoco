# 独立世界摆杆 / Independent-world pendulum

这是原 `demo/` 中的旧版演示工程，现在与其他例程统一放在 `examples/`。

```bash
./boostup.sh
./em_run.sh --exp pendulum
```

F5 运行 `Main.tscn`。此工程直接创建 `MjWorld`、加载 `models/pendulum.xml` 并推进仿真，
由关节角驱动摆杆显示；它展示独立仿真接口。其他三个图形例程展示共享 MuJoCo 物理后端。
也可打开 `ChaosPendulum.tscn`、`VisualDebug.tscn`，用 F6 运行当前场景。
`HeadlessTest.tscn` 等场景用于诊断与测试。

The former `demo/` project now lives alongside the other examples. Press F5 to run
the main pendulum scene. It creates an independent `MjWorld`, loads its MJCF and maps
the simulated hinge angle to the visual rod. The other three graphical examples use
the shared MuJoCo physics backend. Run the chaos or visual-debug scene with F6.

`addons/` 由配置向导链接到根目录插件，`assets/` 链接到根目录原始资产；保留完整仓库结构。
Both addon and asset links refer to repository-root shared directories. Keep the
repository layout intact.
