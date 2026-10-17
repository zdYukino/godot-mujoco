extends Node3D
## Every displayed object is backed by geometry in the same compiled mjModel.
const G1 = "res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf"
var space: RID
var objects: Array[Dictionary] = []
var visuals: Dictionary = {}
var selected := -1
var sequence := 0
var running := false
var status: Label
var feedback: Label
var selector: OptionButton
var toggle: Button
var joint: HSlider
var stats: Label
func button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 38
	b.pressed.connect(callback)
	parent.add_child(b)
	return b
func label(parent: Node, text: String, size: int = 16) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l
func _ready() -> void:
	if PhysicsServer3D.get_class() != "MjPhysicsServer3D":
		push_error("Select MuJoCo as the 3D physics engine")
		get_tree().quit(1)
		return
	space = get_world_3d().space
	PhysicsServer3D.call("scene_pause", space, true)
	var environment := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("182536")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b5c9e4")
	e.ambient_light_energy = 0.6
	environment.environment = e
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(5.5, 3.6, 6.5)
	add_child(camera)
	camera.look_at(Vector3(0.5, 1.1, 0))
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(320, 600)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	label(column, "G1 / DYNAMIC WORLD", 22)
	label(column, "MuJoCo 3.16.0 • native backend", 14)
	status = label(column, "Paused • ready to edit")
	toggle = button(column, "Run simulation  [Space]", toggle_pause)
	button(column, "Add G1 robot  [G]", add_robot)
	button(column, "Add falling obstacle  [O]", add_obstacle)
	selector = OptionButton.new()
	selector.item_selected.connect(func(index: int): selected = index)
	column.add_child(selector)
	button(column, "Delete selected  [Delete]", delete_selected)
	label(column, "Selected G1: left elbow target", 14)
	joint = HSlider.new()
	joint.min_value = 0
	joint.max_value = 1.2
	joint.step = 0.01
	joint.value_changed.connect(control_joint)
	column.add_child(joint)
	stats = label(column, "", 14)
	feedback = label(column, "Add G1, then an obstacle.\nPause to add or remove objects.", 14)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.x = 280
	label(column, "Fixed base • synthetic joint drives\nGravity compensation on G1\nReal obstacle contacts; no walking", 13)
	var floor_id: RID = PhysicsServer3D.call("scene_add_box", space, "Floor", Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)), Vector3(20, 0.2, 20), 0.0)
	add_visual(floor_id, Color("435267"), false)
	# Optional deterministic demonstration for headless scene smoke; no screenshot claim.
	if "--demo-sequence" in OS.get_cmdline_user_args():
		add_robot()
		add_obstacle()
		toggle_pause()
	if "--ui-smoke" in OS.get_cmdline_user_args():
		call_deferred("ui_smoke")

func ui_smoke() -> void:
	var stages := []
	stages.append({"stage": "before", "objects": PhysicsServer3D.call("scene_info", space).objects.size(), "visual_objects": visuals.size()})
	add_robot()
	control_joint(0.2)
	add_obstacle()
	stages.append({"stage": "after_add", "objects": PhysicsServer3D.call("scene_info", space).objects.size(), "visual_objects": visuals.size()})
	toggle_pause()
	for unused in 180:
		await get_tree().physics_frame
		await get_tree().process_frame
	toggle_pause()
	delete_selected()
	delete_selected()
	for cycle in 2:
		add_robot()
		delete_selected()
	await get_tree().process_frame
	stages.append({"stage": "after_delete", "objects": PhysicsServer3D.call("scene_info", space).objects.size(), "visual_objects": visuals.size()})
	var passed: bool = stages[0].objects == 1 and stages[1].objects == 3 and stages[2].objects == 1 and visuals.size() == 1 and objects.is_empty()
	print("DYNAMIC_UI_RESULT ", JSON.stringify({"passed": passed, "stages": stages}))
	get_tree().quit(0 if passed else 1)
func editable() -> bool:
	if running:
		feedback.text = "Pause first; model edits commit atomically."
		return false
	return true
func add_robot() -> void:
	if not editable(): return
	sequence += 1
	var id: RID = PhysicsServer3D.call("scene_import_g1", space, G1, "G1-%d" % sequence, Transform3D(Basis.IDENTITY, Vector3((objects.size() % 3) * 1.6 - 0.8, 1.1, 0)))
	if not id.is_valid():
		feedback.text = PhysicsServer3D.call("scene_info", space).last_error
		return
	add_visual(id, Color("c4d1dc"), true)
	select_object(id, "G1-%d" % sequence)
	feedback.text = "Committed G1: 29 joints / 69 geoms."
func add_obstacle() -> void:
	if not editable(): return
	sequence += 1
	var x := -0.8
	if selected >= 0 and objects[selected].label.begins_with("G1"):
		var s: Dictionary = PhysicsServer3D.call("scene_state", space, objects[selected].rid)
		x = (s.geoms[0].transform as Transform3D).origin.x
	var id: RID = PhysicsServer3D.call("scene_add_box", space, "Obstacle-%d" % sequence, Transform3D(Basis.IDENTITY, Vector3(x, 3.2, 0)), Vector3(0.5, 0.4, 0.5), 0.5)
	if not id.is_valid():
		feedback.text = PhysicsServer3D.call("scene_info", space).last_error
		return
	add_visual(id, Color("f7a94b"), false)
	select_object(id, "Obstacle-%d" % sequence)
	feedback.text = "Obstacle added to the same MuJoCo world."
func select_object(id: RID, text: String) -> void:
	objects.append({"rid": id, "label": text})
	selector.add_item(text)
	selected = objects.size()-1
	selector.select(selected)
func delete_selected() -> void:
	if not editable() or selected < 0: return
	var object: Dictionary = objects[selected]
	if not PhysicsServer3D.call("scene_remove", space, object.rid):
		feedback.text = PhysicsServer3D.call("scene_info", space).last_error
		return
	for mesh in visuals[object.rid].values(): mesh.queue_free()
	visuals.erase(object.rid)
	objects.remove_at(selected)
	selector.remove_item(selected)
	selected = mini(selected, objects.size()-1)
	if selected >= 0: selector.select(selected)
	feedback.text = "Removed %s; other objects retain state." % object.label
func toggle_pause() -> void:
	if PhysicsServer3D.call("scene_pause", space, running):
		running = not running
		toggle.text = "Pause simulation  [Space]" if running else "Run simulation  [Space]"
		status.text = "Running • shared physical world" if running else "Paused • transaction ready"
func control_joint(value: float) -> void:
	if selected >= 0:
		var ok: bool = PhysicsServer3D.call("scene_set_control", space, objects[selected].rid, "left_elbow_joint", value)
		feedback.text = "Elbow target %.2f rad" % value if ok else "Select a G1 robot to control its joint."
func add_visual(id: RID, color: Color, robot_visual: bool) -> void:
	var geometry: Array = PhysicsServer3D.call("scene_geometry", space, id)
	var nodes := {}
	for g in geometry:
		if robot_visual and not g.visual: continue
		var mesh: Mesh
		if g.type == 7:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = g.vertices
			arrays[Mesh.ARRAY_NORMAL] = g.normals
			var array_mesh := ArrayMesh.new()
			array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh = array_mesh
		elif g.type == 6:
			var cube := BoxMesh.new()
			cube.size = g.size * 2
			mesh = cube
		else: continue
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.65
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.material_override = material
		add_child(node)
		node.global_transform = g.transform
		nodes[g.name] = node
	visuals[id] = nodes
func _process(_delta: float) -> void:
	if not space.is_valid() or not is_instance_valid(stats): return
	for id in visuals:
		var s: Dictionary = PhysicsServer3D.call("scene_state", space, id)
		for g in s.get("geoms", []):
			if visuals[id].has(g.name): visuals[id][g.name].global_transform = g.transform
	var s: Dictionary = PhysicsServer3D.call("scene_info", space)
	stats.text = "Objects %d   Bodies %d\nGeoms %d   Joints %d   Drives %d\nContacts %d   Time %.2f s\nRevision %d" % [s.objects.size(), s.nbody, s.ngeom, s.njnt, s.nu, s.ncon, s.time, s.revision]
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_G: add_robot()
		KEY_O: add_obstacle()
		KEY_DELETE: delete_selected()
