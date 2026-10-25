@tool
extends "res://gallery.gd"
const Instance=preload("res://addons/godot_mujoco/model/model_instance.gd")
@export var robot_model: Resource
@export var collision_definitions: Resource
var robots: Array[Node3D]=[]
var robot_overlays: Dictionary={}
var add_button: Button
var add_status: Label
var busy:=false
var last_add: Dictionary={}
var load_error:=""
func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint(): return
	add_button=Button.new(); add_button.text="添加 G1"; add_button.tooltip_text="最多 2 台；同步编译会短暂停顿，保留已有机器人状态和世界时间"; add_button.pressed.connect(request_add); toolbar.add_child(add_button)
	add_status=Label.new(); add_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; chrome.add_child(add_status)
	for node in world.get_children():
		if not node is Instance or node==model: continue
		if valid_robot_state(node).is_empty():
			report_load_error(node.last_error if not node.last_error.is_empty() else "初始 G1 原生状态不可用")
		else:
			robots.append(node); build_robot_overlay(node)
	if robots.is_empty() and load_error.is_empty(): report_load_error("未找到有效的初始 G1")
	apply_display()
func valid_robot_state(robot: Node3D) -> Dictionary:
	if not is_instance_valid(robot) or not robot.model_rid.is_valid(): return {}
	var value: Dictionary=robot.state()
	return value if value.has("joints") and value.has("geoms") and value.has("rid") else {}
func report_load_error(error: String) -> void:
	load_error=error
	if is_instance_valid(add_button): add_button.disabled=true
	if is_instance_valid(add_status): add_status.text="G1 加载失败，世界保留："+error
func help_title() -> String:
	return "无控 G1 示例"
func help_description() -> String:
	return "真实 Unitree G1，自由基座、重力开启、无 actuator / PD 驱动。初始轻微倾斜用于避免完美对称平衡；倒地由物理计算产生。\n\n添加 G1：在空闲位置加入第二台，最多 2 台。原生模型同步编译会短暂停顿，保留第一台状态与仿真时间。机器人碰地板；当前 mask 排除机器人间互碰及自碰撞。\n\n重置恢复初始机器人及热添加机器人的载入姿态；来源、限制和验收步骤见 README。"
func request_add() -> void:
	if busy or not load_error.is_empty() or robots.is_empty() or robots.size()>=2: return
	busy=true; add_button.disabled=true; add_status.text="正在添加：同步编译可能短暂停顿…"
	await get_tree().process_frame
	await get_tree().process_frame
	last_add=add_robot(robot_model)
	busy=false; add_button.disabled=not load_error.is_empty() or robots.is_empty() or robots.size()>=2
	add_status.text=("已添加第 2 台 · 编译 %.2f s · 无重启" % (last_add.elapsed_ms/1000.0)) if last_add.success else "添加失败，原场景保留："+str(last_add.error)
func add_robot(resource: Resource) -> Dictionary:
	if not load_error.is_empty() or robots.is_empty(): return {"success":false,"error":load_error if not load_error.is_empty() else "初始 G1 不可用","elapsed_ms":0}
	if robots.size()>=2: return {"success":false,"error":"本例最多 2 台","elapsed_ms":0}
	var first=robots[0]
	var before: Dictionary=valid_robot_state(first).duplicate(true)
	if before.is_empty():
		report_load_error(first.last_error if is_instance_valid(first) and not first.last_error.is_empty() else "初始 G1 原生状态不可用")
		return {"success":false,"error":load_error,"elapsed_ms":0}
	var time_before: float=world.info().time
	var count_before: int=world.info().objects.size()
	var was_paused: bool=world.info().paused
	var started:=Time.get_ticks_msec()
	var robot=Instance.new(); robot.name="G1_2"; robot.model=resource; robot.position=Vector3(1.8,.82,0); robot.rotation_degrees.z=-5
	world.add_child(robot)
	var error: String=robot.last_error
	var success: bool=robot.model_rid.is_valid()
	if not success: robot.free()
	var result: Dictionary={"success":success,"error":error,"elapsed_ms":Time.get_ticks_msec()-started,"time_before":time_before,"time_after":world.info().time,"state_preserved":first.state().joints==before.joints,"first_rid_preserved":first.model_rid==before.rid,"pause_preserved":world.info().paused==was_paused,"objects_before":count_before,"objects_after":world.info().objects.size()}
	if success:
		robots.append(robot); build_robot_overlay(robot); apply_display()
	return result
func build_robot_overlay(robot: Node3D) -> void:
	var wires: Dictionary={}
	for geom in PhysicsServer3D.call("scene_geometry",world.space,robot.model_rid):
		if geom.contype==0 and geom.conaffinity==0: continue
		var matches: Array=collision_definitions.get_meta("geometries",[]).filter(func(item): return str(geom.name).ends_with(str(item.name)))
		if matches.size()!=1: push_error("Missing verified G1 collision preview: "+str(geom.name)); continue
		var overlay:=Node3D.new(); var wire:=MeshInstance3D.new(); wire.mesh=matches[0].mesh; wire.material_override=matches[0].material; wire.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; wire.transform=geom.transform; overlay.add_child(wire); add_child(overlay); wires[geom.name]=overlay
	robot_overlays[robot]=wires
func apply_display() -> void:
	super.apply_display()
	for robot in robots:
		if not is_instance_valid(robot) or not robot.model_rid.is_valid(): continue
		for mesh in robot.visuals.values(): mesh.visible=entities.button_pressed
		for overlay in robot_overlays.get(robot,{}).values(): overlay.visible=collisions.button_pressed
func _process(delta: float) -> void:
	super._process(delta)
	if Engine.is_editor_hint(): return
	for robot in robots.duplicate():
		var value:=valid_robot_state(robot)
		if value.is_empty():
			for overlay in robot_overlays.get(robot,{}).values(): overlay.free()
			robot_overlays.erase(robot); robots.erase(robot)
			report_load_error(robot.last_error if is_instance_valid(robot) and not robot.last_error.is_empty() else "G1 原生状态不可用")
			continue
		for geom in value.geoms:
			if robot_overlays[robot].has(geom.name):
				for wire in robot_overlays[robot][geom.name].get_children(): wire.global_transform=geom.transform
