# 作者资源、场景与搬迁

右侧 **载入 MJCF** 只接受 XML。导入会展开 include，将依赖副本及来源归档写入项目 `mujoco_models/`，建立 `MjAuthorResource` 和正式 body/joint/geom 节点。旧模型包及转换流程已移除。

Ctrl+S 保存 `.tscn`；自动化生成器使用 `author_builder.gd` 的 `import_file` / `save_document` 和 `scene_builder.gd`。作者资源可存为 `.tres`，其中包含完整作者树、稳定 UUID、初始关节/控制值和网格深度。它不是 MJCF 导入格式。

`MjRuntimeWorld.world_design` 决定全局选项；每个 `MjModelInstance.design` 持有作者数据。各实例的原生 RID、控制和动态状态独立。普通 Godot 刚体可以处于同一 space 并真实接触。六项碰撞选项由 World 覆盖，其他全局选项冲突仍明确拒绝。

搬迁时复制整个项目、addon 运行库和 `mujoco_models/`；运行不再依赖原始 XML、include 或外部网格路径。依赖缺失、哈希变化、未跟踪文件、目录重定向或未展开 include 会被诊断。原始文件路径只用于溯源。

`MjEnvironmentHost` 在独立 World3D 中后台编译候选，成功后替换旧环境，失败保留旧世界和游戏 UI。状态重置保留当前设计；环境重建恢复保存场景并明确丢弃运行时增删。

`tests/portable_runtime/run_assets.sh` 验证源文件与旧项目不可用后的重编译；`run_runtime.sh` 验证共享世界、控制隔离、接触、错误恢复、搬迁与 C#。PCK/ZIP 内依赖提取尚未验收。
