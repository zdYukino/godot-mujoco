extends RefCounted
## MuJoCo 3.16 simulate shortcut adaptation (Apache-2.0; src/viewer/UPSTREAM.md).
## Visibility/group flags are extended from the linked SDK catalog at runtime.
const ACTIONS := [
	[KEY_SPACE, "pause", "Space", "运行 / 暂停"],
	[KEY_LEFT, "history_back", "←", "暂停并后退历史"],
	[KEY_RIGHT, "history_forward", "→", "前进历史 / 最新位置单步"],
	[KEY_BACKSPACE, "reset_initial", "Backspace", "初始重置"],
	[KEY_BRACKETLEFT, "camera_previous", "[", "上一个固定相机"],
	[KEY_BRACKETRIGHT, "camera_next", "]", "下一个固定相机"],
	[KEY_ESCAPE, "free_camera", "Esc", "自由相机"],
	[KEY_PAGEUP, "parent", "PageUp", "选择父级"],
	[KEY_MINUS, "slower", "-", "降低速度"],
	[KEY_EQUAL, "faster", "=", "提高速度"],
	[KEY_F1, "help", "F1", "说明 / 帮助"],
	[KEY_F2, "info", "F2", "MuJoCo Info"],
	[KEY_F3, "profiler", "F3", "Profiler"],
	[KEY_F4, "sensors", "F4", "Sensors"],
	[KEY_F5, "fullscreen", "F5", "独立运行全屏"],
	[KEY_F6, "frame", "F6", "循环坐标系"],
	[KEY_F7, "label", "F7", "循环标签"],
]
const CTRL := {KEY_A: "align", KEY_L: "reload", KEY_C: "copy_state", KEY_M: "print_model", KEY_D: "print_data", KEY_P: "screenshot", KEY_Q: "quit"}
const SECTIONS := {KEY_F: "File", KEY_O: "Option", KEY_S: "Simulation", KEY_W: "Watch", KEY_P: "Physics", KEY_R: "Rendering", KEY_V: "Visualization", KEY_G: "Group enable", KEY_L: "Logging", KEY_J: "Joint", KEY_C: "Control", KEY_E: "Equality"}
static func help_text() -> String:
	var text := "左拖旋转 · Shift 调整方向；右拖平移；中键拖动 / 滚轮缩放。\n左双击选择；右双击居中；Ctrl+右双击跟踪；Alt 交换左右键。\nCtrl+左拖旋转物体；Ctrl+右拖平移物体；运行时施力，暂停时按 MuJoCo 规则调整自由关节 / mocap。\n\n"
	for row in ACTIONS: text += "%s  %s\n" % [row[2], row[3]]
	text += "\nCtrl+A 默认取景；Ctrl+L 重载最后保存的设计。\nCtrl+C 复制状态，Ctrl+Shift+C 高精度；Ctrl+M/D 模型 / 数据输出；Ctrl+P 截图；Ctrl+Q 退出运行。\n0–5 切换 Geom 分组；Shift+0–5 切换 Site 分组；Alt+分组字母展开 / 折叠原版分组。\nTab 切换左面板；Shift+Tab 切换右面板。独立 Godot Extras 的 F11 内 Tab / Shift+Tab 移动控件焦点；F8 保留 Godot 停止。\n分组标题双击展开 / 折叠全部；按住界面右键显示快捷键提示。\n\nF2 只控制 MuJoCo Info；Godot FPS / 系统性能在 F11 单独设置。\n设计修改在 Godot 编辑器进行；运行交互不会回写设计。\n独立运行支持 F5 全屏；嵌入式 GameView 由编辑器管理尺寸。\nGodot 保留场景材质与灯光；原生渲染使用 MuJoCo 画面。禁用的选项会说明后端限制。"
	return text
