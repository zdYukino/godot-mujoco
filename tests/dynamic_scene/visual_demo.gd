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
var joint_label: Label
var stats: Label
var camera: Camera3D
var panel: PanelContainer
var view_center := Vector3(0, 1.2, 0)
var view_distance := 4.0
var yaw := 0.7
var pitch := 0.18
var orbiting := false
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
	e.ambient_light_energy = 0.35
	environment.environment = e
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.02
	add_child(camera)
	camera.current = true
	update_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.size = Vector2(320, get_viewport().get_visible_rect().size.y - 36)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(margin)
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
	selector.item_selected.connect(select_index)
	column.add_child(selector)
	button(column, "Delete selected  [Delete]", delete_selected)
	joint_label = label(column, "No robot selected", 14)
	joint = HSlider.new()
	joint.min_value = 0
	joint.max_value = 1.2
	joint.step = 0.0
	joint.value_changed.connect(control_joint)
	column.add_child(joint)
	select_index(-1)
	var camera_buttons := HBoxContainer.new()
	column.add_child(camera_buttons)
	button(camera_buttons, "Focus [F]", focus_selected)
	button(camera_buttons, "Frame all [A]", frame_all)
	label(column, "Wheel: zoom • Right drag: orbit
Select G1 + F to inspect elbow motion", 13)
	stats = label(column, "", 14)
	feedback = label(column, "Add G1, then an obstacle.\nPause to add or remove objects.", 14)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.x = 280
	label(column, "Fixed base • synthetic joint drives\nGravity compensation on G1\nReal obstacle contacts; no walking", 13)
	var floor_id: RID = PhysicsServer3D.call("scene_add_box", space, "Floor", Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)), Vector3(20, 0.2, 20), 0.0)
	add_visual(floor_id, Color("435267"), false)
	get_viewport().size_changed.connect(func():
		panel.size.y = maxf(200, get_viewport().get_visible_rect().size.y - 36)
		frame_all())
	# Optional deterministic demonstration for headless scene smoke; no screenshot claim.
	if "--demo-sequence" in OS.get_cmdline_user_args():
		add_robot()
		add_obstacle()
		toggle_pause()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			call_deferred("capture_demo", argument.trim_prefix("--capture-dir="))
	if "--ui-smoke" in OS.get_cmdline_user_args():
		call_deferred("ui_smoke")

func ui_smoke() -> void:
	get_window().size = Vector2i(1180, 800)
	await get_tree().process_frame
	var stages := []
	var slider_ok := not joint.editable and joint.value == 0
	stages.append({"stage": "before", "objects": PhysicsServer3D.call("scene_info", space).objects.size(), "visual_objects": visuals.size()})
	add_robot()
	control_joint(1.08)
	var original: RID = objects[0].rid
	add_robot()
	slider_ok = slider_ok and joint.editable and joint.value == 0
	select_index(0)
	slider_ok = slider_ok and is_equal_approx(joint.value, 1.08)
	slider_ok = slider_ok and is_equal_approx(PhysicsServer3D.call("scene_state", space, original).controls.left_elbow_joint_position, 1.08)
	delete_selected()
	slider_ok = slider_ok and joint.editable and joint.value == 0
	control_joint(0.2)
	add_obstacle()
	slider_ok = slider_ok and not joint.editable and joint.value == 0
	var robot_id: RID = objects[0].rid
	var model_before: Dictionary = PhysicsServer3D.call("scene_state", space, robot_id)
	var all_rect := projected_bounds(robot_id)
	select_index(0)
	focus_selected()
	var focused_rect := projected_bounds(robot_id)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_unhandled_input(wheel)
	var zoomed_rect := projected_bounds(robot_id)
	var orbit_before := camera.transform
	var drag_start := InputEventMouseButton.new()
	drag_start.button_index = MOUSE_BUTTON_RIGHT
	drag_start.pressed = true
	_unhandled_input(drag_start)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
	drag.relative = Vector2(30, 10)
	_unhandled_input(drag)
	drag_start.pressed = false
	_unhandled_input(drag_start)
	var orbit_ok := not camera.transform.is_equal_approx(orbit_before) and not orbiting
	var view_ok := all_rect.size.y >= 200 and focused_rect.size.y >= 350 and zoomed_rect.size.y > focused_rect.size.y and camera.transform.is_finite() and orbit_ok
	var physical_unchanged: bool = model_before == PhysicsServer3D.call("scene_state", space, robot_id)
	var camera_report := {"frame_all_height_px": all_rect.size.y, "focused_height_px": focused_rect.size.y, "zoomed_height_px": zoomed_rect.size.y, "physics_unchanged": physical_unchanged, "passed": view_ok and physical_unchanged}
	frame_all()
	select_index(1)
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
		slider_ok = slider_ok and joint.editable and joint.value == 0
		delete_selected()
		slider_ok = slider_ok and not joint.editable and joint.value == 0
	await get_tree().process_frame
	stages.append({"stage": "after_delete", "objects": PhysicsServer3D.call("scene_info", space).objects.size(), "visual_objects": visuals.size()})
	var passed: bool = stages[0].objects == 1 and stages[1].objects == 3 and stages[2].objects == 1 and visuals.size() == 1 and objects.is_empty() and camera_report.passed and slider_ok
	print("DYNAMIC_UI_RESULT ", JSON.stringify({"passed": passed, "stages": stages, "camera": camera_report, "slider_sync": slider_ok}))
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
	add_visual(id, Color("8094a8"), true)
	select_object(id, "G1-%d" % sequence)
	feedback.text = "Committed G1: 29 joints / 69 geoms."
	frame_all()
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
	frame_all()
func select_object(id: RID, text: String) -> void:
	objects.append({"rid": id, "label": text})
	selector.add_item(text)
	selected = objects.size()-1
	selector.select(selected)
	select_index(selected)
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
	if selected >= 0:
		selector.select(selected)
	select_index(selected)
	frame_all()
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
		select_index(selected)
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
		material.roughness = 0.85
		material.metallic_specular = 0.2
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
		KEY_F: focus_selected()
		KEY_A: frame_all()

# Camera operations only read rendered physics geometry. They never move bodies.
func object_bounds(id: RID) -> AABB:
	var bounds := AABB()
	var first := true
	for mesh in visuals.get(id, {}).values():
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func select_index(index: int) -> void:
	selected = index if index >= 0 and index < objects.size() else -1
	joint.editable = false
	joint.set_value_no_signal(0)
	joint_label.text = "No robot selected"
	if selected < 0:
		return
	var s: Dictionary = PhysicsServer3D.call("scene_state", space, objects[selected].rid)
	var controls: Dictionary = s.get("controls", {})
	joint.editable = controls.has("left_elbow_joint_position")
	if joint.editable:
		var value: float = controls.left_elbow_joint_position
		# Reflect the actual target even if set outside the demonstration range
		# by another caller. Selection itself never writes a target back.
		joint.min_value = minf(0, value)
		joint.max_value = maxf(1.2, value)
		joint.set_value_no_signal(value)
		joint_label.text = "Left elbow target: %.2f rad" % value
	else:
		joint_label.text = "Selected object has no joint controls"

func fit_bounds(bounds: AABB) -> void:
	view_center = bounds.get_center()
	var viewport_size := get_viewport().get_visible_rect().size
	var available_aspect := maxf(0.35, (viewport_size.x - 370.0) / viewport_size.y)
	var half_angle := atan(tan(deg_to_rad(camera.fov * 0.5)) * minf(1.0, available_aspect))
	# A bounding sphere fits at every orbit angle, with a small visual margin.
	view_distance = clampf(maxf(0.2, bounds.size.length() * 0.5) / sin(half_angle) * 1.1, 0.4, 60)
	update_camera()

func focus_selected() -> void:
	if selected >= 0:
		fit_bounds(object_bounds(objects[selected].rid))

func frame_all() -> void:
	if objects.is_empty():
		view_center = Vector3(0, 1.2, 0)
		view_distance = 4.0
		update_camera()
		return
	var bounds := object_bounds(objects[0].rid)
	for i in range(1, objects.size()):
		bounds = bounds.merge(object_bounds(objects[i].rid))
	fit_bounds(bounds)

func update_camera() -> void:
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	camera.position = view_center + direction * view_distance
	camera.look_at(view_center)
	# Reserve the left control panel: center the subject in the remaining view.
	var size := get_viewport().get_visible_rect().size
	var shift := minf(350.0, size.x * 0.45) / size.y * view_distance * tan(deg_to_rad(camera.fov * 0.5))
	camera.position -= camera.basis.x * shift

func zoom(factor: float) -> void:
	view_distance = clampf(view_distance * factor, 0.4, 60)
	update_camera()

func orbit(delta: Vector2) -> void:
	yaw -= delta.x * 0.008
	pitch = clampf(pitch + delta.y * 0.008, -0.45, 1.35)
	update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(0.85)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.0 / 0.85)
	elif event is InputEventMouseMotion and orbiting:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			orbit(event.relative)
		else:
			orbiting = false

func projected_bounds(id: RID) -> Rect2:
	var bounds := object_bounds(id)
	var rect := Rect2(camera.unproject_position(bounds.get_endpoint(0)), Vector2.ZERO)
	for corner in range(1, 8):
		rect = rect.expand(camera.unproject_position(bounds.get_endpoint(corner)))
	return rect

# Optional real-render diagnostics, distinct from the headless acceptance suite.
func capture_demo(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	get_window().size = Vector2i(1180, 800)
	await save_frame(directory.path_join("01-before.png"))
	add_robot()
	add_obstacle()
	await save_frame(directory.path_join("02-g1-obstacle.png"))
	select_index(0)
	selector.select(0)
	focus_selected()
	await save_frame(directory.path_join("03-focus-g1.png"))
	control_joint(1.08)
	toggle_pause()
	for unused in 120:
		await get_tree().physics_frame
		await get_tree().process_frame
	toggle_pause()
	await save_frame(directory.path_join("04-elbow-driven.png"))
	print("CAMERA_CAPTURE_COMPLETE ", directory)
	get_tree().quit()

func save_frame(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Screenshot save failed: " + path)
		get_tree().quit(1)
