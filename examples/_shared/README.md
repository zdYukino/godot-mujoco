# 例程共享资源 / Shared example resources

这里没有 `project.godot`，由例程通过相对链接复用：

- `gallery.gd`：形状例程界面及 G1 界面的基类。
- `floor_grid.gdshader`：地板网格着色器。
- `assets/`：天空 HDR 与素材来源、许可说明。

This directory has no Godot project. Examples link to the gallery UI base script,
floor-grid shader and sky assets here. Asset attribution is in [assets/SOURCES.md](assets/SOURCES.md).

资源的 `.import` 配置保留在各工程自己的 `assets/` 下，导入缓存由该工程的 `.godot/` 管理。
Per-project `.import` settings stay with each project; its `.godot/` holds the import cache.
