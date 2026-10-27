# 两条日常设计编辑路径

本测试不调试引擎。固定Linux/Godot4.7.2.NET/MuJoCo3.16.0，使用正常图形驱动配置。XTEST输入需要python-xlib和1600×1000 X11桌面；复用`tests/editor_plugin/mouse_acceptance.py`的坐标观测/输入工具。

1. 新目录复制`tests/editor_plugin`和`addons`，将`probe.gd`复制为项目`acceptance.gd`。必须断言项目`.godot`不存在，**不要先运行headless import**。
2. 正常启动`godot --editor --path PROJECT --rendering-method gl_compatibility --audio-driver Dummy --resolution 1600x1000 -- --mj-editor-test --probe-dir=OUT/first`；另一个终端执行`python3 tests/daily_paths/gui.py OUT/first first PROJECT`。通过真实Import/Apply/Save操作保存`daily.gmj.json`和项目`.tres`，正常退出。
3. 新编辑器进程以`--probe-dir=OUT/reopen`启动；执行`gui.py OUT/reopen reopen PROJECT`核对保存值。退出后把OUT的`resource-path.txt`复制为项目`original-resource.txt`，把`api_edit.gd`复制进项目。
4. 已初始化项目直接执行`godot --headless --path PROJECT --script res://api_edit.gd -- --mode=edit --report=OUT/api-edit.json`。再启动独立进程执行相同命令但`--mode=verify --report=OUT/api-verify.json`。不执行新的导入、不删除缓存。
5. 新GUI进程以`--probe-dir=OUT/api-gui`启动；执行`gui.py OUT/api-gui api PROJECT`，打开设计文档，核对0.35阻尼及api_box结构。

路径必须使用绝对路径。`probe.gd`只观测UI，不预先导入夹具；GUI文件导入和打开均为真实鼠标键盘操作。API路径是GDScript程序处理已有设计文件，不是无窗口可交互界面。

资源包不可变：API从已有.tres打开设计，发布新哈希版本，原包不覆盖；设计JSON使用临时文件+原子替换更新。验证负质量、非法发布路径被拒绝；拒绝前后文档快照和文件SHA256相同。独立进程同时重开新.tres与JSON，验证属性和实体，再由GUI核对。

每个进程应exit0，所有检查通过，所有日志无ERROR/泄漏。保留首次GUI项目无缓存证明，后续重开是已初始化项目，不能标为fresh import。此代表性轻量MJCF用例不证明所有模型/宿主的冷导入都稳定。
