@tool
extends "res://gallery.gd"
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
@export var collision_definitions: Resource
var robots: Array[Node3D] = []
var robot_overlays := {}
var add_button: Button
var add_status: Label
var busy := false
var last_add := {}
var load_error := ""
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	add_button = Button.new(); add_button.text = "添加 G1（诊断）"
	add_button.tooltip_text = "复制编辑器中的 G1 设计，支持撤销与保存；后台重建完成后手动继续。双 G1 仅为限时诊断。"
	add_button.pressed.connect(request_add); toolbar.add_child(add_button)
	add_status = Label.new(); add_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; chrome.add_child(add_status)
	world.design_request_finished.connect(func(result):
		busy = false; last_add = result
		add_status.text = "设计已写入编辑器，等待后台重建；完成后手动继续。" if result.get("success", false) else str(result.get("error", "请求失败")))
func help_title() -> String: return "无控 G1 示例"
func help_description() -> String:
	return "真实 Unitree G1，自由基座、重力开启、无 actuator / PD 驱动。初始倾斜用于避免完美对称平衡；倒地由物理计算产生。\n\n场景树的 body / geom / joint 可直接编辑。运行中设计修改会暂停实际物理，后台重建后手动继续。\n\n添加 G1 按钮向编辑器请求复制，可 Ctrl+Z、Ctrl+S。独立运行时禁用设计按钮。双 G1 是有超时和取消能力的诊断项，不作为单 G1 验收门槛。\n\n滚轮缩放，F 重新取景；碰撞 mask 保留原有设置。"
func valid_robot_state(robot: Node3D) -> Dictionary:
	if not is_instance_valid(robot) or not robot.model_rid.is_valid(): return {}
	var value: Dictionary = robot.state()
	return value if value.has("joints") and value.has("geoms") else {}
func request_add() -> void:
	if busy or not world.editor_connected or robots.is_empty() or robots.size() >= 2: return
	var pose: Transform3D = robots[0].spawn_transform
	pose.origin.x += 3.6
	var request: int = world.request_editor_design({"op":"duplicate_model", "instance_id":robots[0].design_instance_id, "name":"G1_2", "pose":pose})
	busy = request != 0
	if busy: add_status.text = "已请求编辑器复制，世界已暂停…"
func build_robot_overlay(robot: Node3D) -> void:
	var wires := {}
	for geom in robot.state().geoms:
		var matches: Array = collision_definitions.get_meta("geometries", []).filter(func(item): return str(geom.name).ends_with(str(item.name)))
		if matches.size() != 1: continue
		var overlay := Node3D.new(); var wire := MeshInstance3D.new()
		wire.mesh = matches[0].mesh; wire.material_override = matches[0].material
		wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; wire.transform = geom.transform
		overlay.add_child(wire); add_child(overlay); wires[geom.name] = overlay
	robot_overlays[robot] = wires
func apply_display() -> void:
	super.apply_display()
	for robot in robots:
		if not is_instance_valid(robot): continue
		for mesh in robot.visuals.values(): mesh.visible = entities.button_pressed
		for overlay in robot_overlays.get(robot, {}).values(): overlay.visible = collisions.button_pressed
func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint() or not is_instance_valid(add_button): return
	add_button.disabled = busy or not world.editor_connected or robots.size() >= 2 or not world.author_started or world.info().get("design_pending", true)
	if not world.editor_connected: add_status.text = "独立运行：连接编辑器后可修改设计。"
	for node in world.get_children():
		if not node is Instance or node == model or robots.has(node) or valid_robot_state(node).is_empty(): continue
		robots.append(node); build_robot_overlay(node); apply_display()
		if robots.size() > 1: world.get_node("Camera").frame_for_count(robots.size())
	for robot in robots.duplicate():
		var value := valid_robot_state(robot)
		if value.is_empty():
			for overlay in robot_overlays.get(robot, {}).values(): overlay.queue_free()
			robot_overlays.erase(robot); robots.erase(robot); continue
		for geom in value.geoms:
			if robot_overlays.get(robot, {}).has(geom.name):
				for wire in robot_overlays[robot][geom.name].get_children(): wire.global_transform = geom.transform
