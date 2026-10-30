@tool
extends "res://gallery.gd"
@export var collision_definitions: Resource
func help_title() -> String: return "无控 G1 示例"
func help_description() -> String:
	return "真实 Unitree G1，自由基座、重力开启、无 actuator / PD 驱动。初始倾斜用于避免完美对称平衡；倒地由物理计算产生。\n\n双击选择、Ctrl+拖动施力；暂停时按 MuJoCo 规则调整姿态。显示选项位于原版左面板的 Rendering 与 Group enable；Tab / Shift+Tab 开关左右面板，F11 仅提供 Godot 附加功能。\n\n增删 G1 和地形等设计修改在 Godot 编辑器执行，可撤销与保存；运行窗口不会回写设计。"
