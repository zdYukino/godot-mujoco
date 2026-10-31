# 新工程 / New project

按 **F5** 开始仿真，**F8** 停止。平地顶面 y=0，球半径 0.5m、质量 100kg，
球心初始高度 1.5m（球底离地 1m），初速度为零。

Press **F5** to simulate and **F8** to stop. The ground is at y=0. The 100kg ball
has radius 0.5m and starts at center height 1.5m (bottom 1m above ground), at rest.

此工程已复制完整插件及 Linux x86_64 开发运行库，可以移到仓库外使用。
插件不会随仓库重新编译自动更新；升级时关闭编辑器后更新工程的 addons。
不包含其他平台或发布导出库。

The complete addons and Linux x86_64 development libraries are copied into this
project. It can be moved outside the repository. Rebuilding the repository does
not update this copy; close the editor before updating its addons. Other platforms
and release export libraries are not included.

场景显式保存与 `Runtime` 并列的 `RuntimeViewer` 和 `GodotExtras`：前者负责原版面板、F1–F4、相机和扰动；后者独立负责 F11、性能及示例工具。两者各自绑定 World/Host，可单独添加、禁用或删除，仿真与所选渲染继续；只保留 Extras 时由游戏控制相机。布局、Theme、功能和个人偏好分别定制。右侧 MuJoCo 栏的“添加 MuJoCo 运行面板”预设只添加原版组件；Extras 在添加子节点中单独添加。详见插件的 `viewer/README.md`。
