@tool
extends VBoxContainer
const PackageBuilder = preload("res://addons/godot_mujoco/model/package_builder.gd")
const SceneBuilder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
var source_watch = preload("res://addons/godot_mujoco/map/source_watch.gd").new()
var source_status: Label
var source_poll := 0.0
var runtime_targets: OptionButton
var runtime_status: Label
var runtime_apply: Button
var runtime_target_key := ""
var project_model_path := ""
var project_model_snapshot: Dictionary = {}
var model_provenance: Dictionary = {}
var plugin: EditorPlugin
var state: RefCounted
var tree: Tree
var fields: VBoxContainer
var status: Label
var live: Label
var viewport: SubViewport
var camera: Camera3D
var meshes := {}
var selected := {}
var inputs := {}
var pending := false
var refreshing := false
var serial := 0
var distance := 5.0
var yaw := 0.65
var pitch := 0.3
var center := Vector3(0, 0.8, 0)
var orbiting := false
var edit_axis := 0
var move_step := 0.1
var rotate_step := 5.0
var recovery_path := "user://mujoco_editor_recovery.json"

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

func _ready() -> void:
	var toolbar := HFlowContainer.new()
	add_child(toolbar)
	button(toolbar, "Import MJCF", func(): file_dialog(false, true))
	button(toolbar, "检查来源", check_sources)
	button(toolbar, "重导入来源（明确丢弃本地）", confirm_reimport)
	button(toolbar, "保留本地 / 另存副本", func(): file_dialog(true, false))
	button(toolbar, "Import fixed G1", import_g1_dialog)
	button(toolbar, "Import free G1 (relaxed)", func(): import_g1_dialog(true))
	button(toolbar, "Open document", func(): file_dialog(false, false))
	button(toolbar, "Save document", func(): file_dialog(true, false))
	button(toolbar,"保存控制预设",func():preset_dialog(true))
	button(toolbar,"加载控制预设",func():preset_dialog(false))
	button(toolbar, "Save project model", save_project_model)
	button(toolbar, "Open project model", open_project_model_dialog)
	button(toolbar, "Create runtime scene", create_runtime_scene_dialog)
	button(toolbar, "Create simulation playground", func(): create_runtime_scene_dialog(true))
	button(toolbar, "Recover", func(): open_document(recovery_path))
	button(toolbar, "Run / Pause", toggle_run)
	button(toolbar, "Frame all", frame_all)
	for shape in ["box", "sphere", "cylinder"]:
		button(toolbar, "+ " + shape, add_primitive.bind(shape))
	source_status = Label.new(); source_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(source_status)
	var runtime_bar := HFlowContainer.new()
	add_child(runtime_bar)
	runtime_targets = OptionButton.new()
	runtime_targets.custom_minimum_size.x = 280
	runtime_bar.add_child(runtime_targets)
	runtime_targets.item_selected.connect(func(index):
		runtime_target_key = str(runtime_targets.get_item_metadata(index))
		refresh_runtime_targets())
	button(runtime_bar, "Assign saved model to scene selection", assign_saved_model)
	runtime_apply = button(runtime_bar, "Apply saved model to runtime", apply_runtime_model)
	button(runtime_bar, "Send selected control to runtime", send_runtime_control)
	button(runtime_bar,"应用整份运行预设",runtime_preset_dialog)
	button(runtime_bar,"取消待提交运行预设",func():plugin.live_debugger.send(runtime_target_key,"cancel_preset",{}))
	runtime_status = Label.new()
	runtime_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(runtime_status)
	plugin.live_debugger.changed.connect(refresh_runtime_targets)
	refresh_runtime_targets()
	var operations := HFlowContainer.new()
	add_child(operations)
	var axis := OptionButton.new()
	for label in ["Local MJCF X", "Local MJCF Y", "Local MJCF Z"]: axis.add_item(label)
	axis.item_selected.connect(func(index): edit_axis = index)
	operations.add_child(axis)
	button(operations, "Move −0.1 m", transform_selection.bind("move", -1.0))
	button(operations, "Move +0.1 m", transform_selection.bind("move", 1.0))
	button(operations, "Rotate −5°", transform_selection.bind("rotate", -1.0))
	button(operations, "Rotate +5°", transform_selection.bind("rotate", 1.0))
	button(operations, "Size ÷1.1", transform_selection.bind("size", -1.0))
	button(operations, "Size ×1.1", transform_selection.bind("size", 1.0))
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "MuJoCo 3.16 • metres / kg / seconds / radians • local properties use MJCF Z-up axes; preview uses Godot Y-up • Left click selects visible geometry; operations use local MJCF axes"
	add_child(note)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 270
	split.add_child(left)
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 150
	tree.item_selected.connect(on_select)
	left.add_child(tree)
	button(left, "Delete selected body / geom", delete_selected)
	var view_box := SubViewportContainer.new()
	view_box.stretch = true
	view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_box.custom_minimum_size = Vector2(320, 300)
	view_box.gui_input.connect(camera_input)
	split.add_child(view_box)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view_box.add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 45
	camera.near = 0.01
	viewport.add_child(camera)
	viewport.size_changed.connect(frame_all)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.8
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("25313e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.4
	viewport.add_child(env)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 300
	split.add_child(scroll)
	fields = VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(fields)
	live = Label.new()
	add_child(live)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	state.changed.connect(refresh)
	refresh()
	frame_all()
	if not state.draft.is_empty():
		select_entity(state.draft.selected.kind, state.draft.selected.name)
		for key in state.draft.fields:
			if inputs.has(key):
				inputs[key].text = state.draft.fields[key]
		pending = true
		status.text = "Unapplied fields restored after plugin enable — Apply or Discard"
	set_process(true)

func shutdown() -> void:
	save_recovery()
	state.draft = {}
	if pending:
		var draft_fields := {}
		for key in inputs:
			draft_fields[key] = inputs[key].text
		state.draft = {"selected":selected.duplicate(true), "fields":draft_fields}
	set_process(false)
	if state.changed.is_connected(refresh):
		state.changed.disconnect(refresh)
	meshes.clear()

func save_recovery() -> void:
	if state.document and (state.dirty or pending):
		write_document(recovery_path)

func show_error(message: String) -> void:
	status.text = "FAILED — " + message + ". Existing model and pending fields retained."

func can_leave_fields() -> bool:
	if pending:
		show_error("Apply or Discard pending property edits first")
		return false
	return true

func execute(command: Dictionary) -> bool:
	var before: Dictionary = state.document.snapshot()
	if not state.document.edit(command):
		show_error(state.document.get_error())
		return false
	record_change(before, "MuJoCo " + str(command.get("op", "edit")))
	return true

func record_change(before: Dictionary, title: String) -> void:
	var after: Dictionary = state.document.snapshot()
	var history := plugin.get_undo_redo()
	history.create_action(title, UndoRedo.MERGE_DISABLE, state)
	history.add_do_method(state, "restore_snapshot", after)
	history.add_undo_method(state, "restore_snapshot", before)
	history.commit_action(false)
	state.content = after
	state.dirty = true
	pending = false
	refresh()
	save_recovery()
	refresh_runtime_targets()

func import_mjcf(path: String) -> bool:
	if not can_leave_fields():
		return false
	var before: Dictionary = state.document.snapshot()
	if not state.document.import_file(path):
		show_error(state.document.get_error())
		return false
	source_watch.capture(path, state.document.asset_manifest().assets)
	project_model_path = ""
	model_provenance = {}
	record_change(before, "MuJoCo import")
	state.dirty = false
	check_sources()
	frame_all()
	return true

func file_dialog(save: bool, importing: bool) -> void:
	if not can_leave_fields():
		return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.xml ; MJCF model"]) if importing else PackedStringArray(["*.gmj.json ; MuJoCo editor document"])
	dialog.file_selected.connect(func(path: String):
		if importing:
			import_mjcf(path)
		elif save:
			save_document(path)
		else:
			open_document(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.7)

func write_document(path: String) -> bool:
	# Only editor JSON documents are written. XML and imported assets are never overwritten.
	if path.get_extension().to_lower() != "json":
		show_error("Document filename must end in .gmj.json")
		return false
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not f:
		show_error("Cannot write document " + path)
		return false
	var payload: Dictionary = state.document.snapshot()
	payload["source_tracking"] = {"source":source_watch.source,"hashes":source_watch.hashes,"exported_hash":source_watch.exported_hash}
	if pending:
		var draft := {}
		for key in inputs:
			draft[key] = inputs[key].text
		payload["draft"] = {"selected":selected, "fields":draft}
	f.store_string(JSON.stringify(payload, "\t", true, true))
	f.close()
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		show_error("Cannot atomically replace document: " + error_string(result))
		return false
	return true

func save_document(path: String) -> bool:
	if not can_leave_fields() or not write_document(path):
		return false
	state.file_path = path
	state.dirty = false
	status.text = "Saved " + path + " • source assets remain external and unchanged"
	return true

func open_document(path: String) -> bool:
	if not can_leave_fields():
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		show_error("Invalid document JSON")
		return false
	var before: Dictionary = state.document.snapshot()
	if not state.document.restore(json.data):
		show_error(state.document.get_error())
		return false
	source_watch = preload("res://addons/godot_mujoco/map/source_watch.gd").new()
	var tracking: Dictionary = json.data.get("source_tracking",{})
	source_watch.source = tracking.get("source",""); source_watch.hashes = tracking.get("hashes",{}); source_watch.exported_hash = tracking.get("exported_hash","")
	project_model_path = ""
	model_provenance = {}
	record_change(before, "MuJoCo open document")
	state.file_path = path
	if json.data.has("draft"):
		select_entity(json.data.draft.selected.kind, json.data.draft.selected.name)
		for key in json.data.draft.fields:
			if inputs.has(key):
				inputs[key].text = json.data.draft.fields[key]
		pending = true
		status.text = "Recovered pending fields — Apply or Discard"
	frame_all()
	return true

func import_g1_dialog(free_base: bool = false) -> void:
	if not can_leave_fields(): return
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.urdf ; Original fixed-base Unitree G1 URDF"])
	dialog.file_selected.connect(func(path: String):
		var before: Dictionary = state.document.snapshot()
		if state.document.import_g1(path, free_base, free_base):
			project_model_path = ""
			model_provenance = {}
			record_change(before,"MuJoCo import free-base relaxed G1" if free_base else "MuJoCo import fixed-base G1")
			frame_all()
		else: show_error(state.document.get_error())
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(.7)

func create_runtime_scene_dialog(playground: bool = false) -> void:
	if not can_leave_fields(): return
	if project_model_path.is_empty() or state.dirty or state.document.snapshot() != project_model_snapshot:
		show_error("Save project model first so the scene references an explicit immutable revision")
		return
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.tscn ; MuJoCo runtime scene"])
	dialog.current_file = "mujoco_scene.tscn"
	dialog.file_selected.connect(func(path: String):
		var resource = ResourceLoader.load(project_model_path)
		var error := SceneBuilder.save_playground(resource,path) if playground else SceneBuilder.save(resource,path)
		if error == OK:
			refresh_project_files()
			status.text = "Saved runtime scene: " + path + ". Select MuJoCo physics, restart, and instantiate this scene."
		else: show_error("Cannot save runtime scene: " + error_string(error))
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(.7)

func save_project_model() -> void:
	if not can_leave_fields():
		return
	model_provenance["imported_source_hashes"] = source_watch.hashes.duplicate()
	var result: Dictionary = PackageBuilder.pack(state.document, "res://mujoco_models", "model", model_provenance, project_model_path.get_base_dir() if not project_model_path.is_empty() else "")
	if not result.error.is_empty():
		show_error(result.error)
		return
	state.dirty = false
	project_model_path = result.path
	source_watch.exported_hash = FileAccess.get_sha256(result.path.get_base_dir().path_join("model.xml"))
	project_model_snapshot = state.document.snapshot().duplicate(true)
	model_provenance = ResourceLoader.load(project_model_path).provenance.duplicate(true)
	refresh_project_files()
	status.text = "Saved portable project model: " + result.path
	refresh_runtime_targets()

func open_project_model_dialog() -> void:
	if not can_leave_fields():
		return
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.tres ; MuJoCo project model"])
	dialog.file_selected.connect(func(path: String): open_project_model(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(.7)

func open_project_model(path: String) -> bool:
	if not can_leave_fields():
		return false
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource or not resource is PackageBuilder.ModelResource:
		show_error("Not a MuJoCo model resource")
		return false
	var result: Dictionary = resource.open_document()
	if not result.error.is_empty():
		show_error(result.error)
		return false
	var before: Dictionary = state.document.snapshot()
	if not state.document.restore(result.document.snapshot()):
		show_error(state.document.get_error())
		return false
	project_model_path = path
	model_provenance = resource.provenance.duplicate(true)
	source_watch = preload("res://addons/godot_mujoco/map/source_watch.gd").new()
	source_watch.source = model_provenance.get("source","")
	source_watch.hashes = model_provenance.get("sources",{}).duplicate()
	source_watch.hashes.merge(model_provenance.get("assets",{}),true)
	record_change(before, "MuJoCo open project model")
	frame_all()
	return true

func add_primitive(shape: String) -> void:
	if not can_leave_fields():
		return
	state.document.set_paused(true)
	serial += 1
	var entity_name := shape + "_" + str(Time.get_ticks_usec()) + "_" + str(serial)
	if execute({"op":"add", "shape":shape, "name":entity_name}):
		select_entity("body", entity_name)
		frame_all()

func delete_selected() -> void:
	if not selected.is_empty() and can_leave_fields():
		state.document.set_paused(true)
		execute({"op":"delete", "kind":selected.kind, "name":selected.name})

func toggle_run() -> void:
	if not can_leave_fields():
		return
	state.document.set_paused(not state.document.is_paused())
	status.text = "Paused — structural changes compile only on Apply" if state.document.is_paused() else "Running real MuJoCo simulation; structural editing will pause preview"

func refresh() -> void:
	if not is_instance_valid(tree):
		return
	if pending:
		rebuild_meshes()
		status.text = "Model changed by undo/redo; pending field text retained — Apply or Discard"
		return
	refreshing = true
	var info: Dictionary = state.document.inspect()
	tree.clear()
	var root := tree.create_item()
	root.set_text(0, "Model (MJCF)")
	var bodies := {}
	var old := selected.duplicate()
	selected = {}
	for entity in info.entities:
		var parent: TreeItem = bodies.get(entity.parent, root)
		var item := tree.create_item(parent)
		item.set_text(0, entity.kind + ": " + entity.name)
		item.set_metadata(0, entity)
		if entity.kind == "body":
			bodies[entity.name] = item
		if entity.kind == old.get("kind") and entity.name == old.get("name"):
			item.select(0)
			selected = entity
	refreshing = false
	build_fields()
	rebuild_meshes()
	status.text = "Paused" if info.paused else "Running"
	status.text += " • Apply commits pending fields transactionally; Ctrl+Z / Ctrl+Shift+Z use editor history • " + ("Unsaved" if state.dirty else "Saved")
	refresh_runtime_targets()

func select_entity(kind: String, entity_name: String) -> void:
	selected = {"kind":kind, "name":entity_name}
	refresh()

func on_select() -> void:
	if refreshing:
		return
	if not can_leave_fields():
		restore_tree_selection(tree.get_root())
		# Native Tree mouse handling can still clear later rows after this signal.
		# Resolve again after input dispatch, using current state rather than a stale item.
		call_deferred("restore_pending_tree_selection")
		return
	var item := tree.get_selected()
	selected = item.get_metadata(0) if item and item.get_metadata(0) is Dictionary else {}
	build_fields()
	highlight_selection()

func restore_pending_tree_selection() -> void:
	if pending and is_instance_valid(tree) and not selected.is_empty():
		restore_tree_selection(tree.get_root())

func restore_tree_selection(item: TreeItem) -> void:
	if not item: return
	var data: Variant = item.get_metadata(0)
	if data is Dictionary and data.get("kind") == selected.get("kind") and data.get("name") == selected.get("name"):
		# Tree changes its visual selection before item_selected is emitted.
		# Restore it without rebuilding the form or re-entering this callback.
		refreshing = true
		tree.deselect_all()
		item.select(0)
		tree.set_selected(item, 0)
		refreshing = false
		return
	for child in item.get_children(): restore_tree_selection(child)

func field(key: String, value: Variant, editable: bool, hint: String) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = key + " — " + hint + ("" if editable else " [read-only]")
	fields.add_child(label)
	if editable:
		var input := LineEdit.new()
		input.text = JSON.stringify(value)
		input.text_changed.connect(func(_text): pending = true; status.text = "Pending changes — Apply or Discard; not yet written to physics"; refresh_runtime_targets())
		fields.add_child(input)
		inputs[key] = input
	else:
		var label_value := Label.new()
		label_value.text = str(value)
		label_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fields.add_child(label_value)

func build_fields() -> void:
	# Apply/Discard can rebuild their own form from inside pressed. A signal
	# emitter is locked until its callback returns: detach now, destroy only
	# at the end of the frame. Disconnect retired buttons so a queued/repeated
	# activation cannot apply the replacement form through a stale control.
	for child in fields.get_children():
		if child is BaseButton:
			child.disabled = true
			for connection in child.get_signal_connection_list("pressed"):
				child.disconnect("pressed", connection.callable)
		fields.remove_child(child)
		child.queue_free()
	inputs.clear()
	if selected.is_empty():
		field("Selection", "Select a body, geom, joint or actuator", false, "")
		return
	var p: Dictionary = selected.properties
	var kind: String = selected.kind
	field("name", selected.name, false, kind)
	for key in p:
		var editable := false
		var hint := "actual compiled value"
		if kind == "body":
			editable = selected.name != "world" and key in ["mass", "pos", "quat", "inertia", "ipos", "iquat", "inertia_mode"]
			hint = {"mass":"kg; explicit mass scales existing inertia", "inertia":"positive principal kg m²; triangle inequalities; manual mode", "inertia_mode":"JSON string: automatic (geom mass/density) or manual; manual inertial fields override inference", "ipos":"body-local center of mass, m", "iquat":"body-local principal-axis quaternion wxyz", "pos":"local MJCF xyz, m", "quat":"local wxyz, unit quaternion"}.get(key, "source inertia mode")
			if key in ["mass", "inertia", "ipos", "iquat"] and p.get("compiler_inertia_policy") == "forced geometry": editable = false
			if key == "inertia_mode" and p.get("compiler_inertia_policy") != "automatic": editable = false
		elif kind == "geom":
			editable = key in ["pos", "quat", "friction", "contype", "conaffinity", "margin", "density"] or (key == "size" and p.type in [2, 5, 6])
			hint = {"size":"MJCF half sizes [x,y,z]; sphere [r,0,0]; cylinder [r,half-height,0], m", "density":"kg/m³; only bodies with inferred inertia", "friction":"[sliding, torsional, rolling]", "pos":"local MJCF xyz, m", "quat":"local wxyz", "margin":"m"}.get(key, "contact bitmask / source value")
		elif kind == "actuator":
			editable = key == "control" or (key == "kp" and p.type == "position-compatible") or (key == "kv" and p.type != "general/non-PD")
			hint = "actuator transmission units; gear shown below; PD gains apply only to compatible affine drives"
		elif kind == "joint":
			editable = p.type in ["hinge", "slide"] and key in ["limited", "range", "damping", "frictionloss"]
			if key == "damping" and not p.get("damping_editable", true): editable = false
			hint = str(p.unit) + "; mass belongs to body"
		if key in ["pos", "quat"] and not p.get("pose_editable", true):
			editable = false
			hint = "frame/fromto source transform; compiled value read-only"
		if key == "size" and not p.get("size_editable", true):
			editable = false
			hint = "fromto-derived size; read-only"
		field(key, p[key], editable, hint)
	if kind == "joint" and p.type in ["hinge", "slide"]:
		field("set_qpos", p.qpos[0], true, "paused scalar position, " + p.unit)
	button(fields, "Apply to physics", apply_fields)
	button(fields, "Discard pending fields", func(): pending = false; refresh())

func apply_fields() -> bool:
	if selected.is_empty():
		return false
	var values := {}
	for key in inputs:
		var parser := JSON.new()
		if parser.parse(inputs[key].text) != OK:
			show_error("Invalid numeric JSON in " + key)
			return false
		var previous: Variant = selected.properties.qpos[0] if key == "set_qpos" else selected.properties[key]
		if parser.data != previous:
			values[key] = parser.data
	if values.is_empty():
		pending = false
		return true
	# A single action cannot mix a direct state write with a structural transaction.
	if (values.has("control") or values.has("set_qpos")) and values.size() != 1:
		show_error("Apply control/position separately from structural parameters")
		return false
	if values.has("control"):
		return execute({"op":"control", "name":selected.name, "value":values.control})
	state.document.set_paused(true)
	if values.has("set_qpos"):
		return execute({"op":"qpos", "name":selected.name, "value":values.set_qpos})
	return execute({"op":"set", "kind":selected.kind, "name":selected.name, "values":values})

func rebuild_meshes() -> void:
	for mesh in meshes.values():
		mesh.free()
	meshes.clear()
	for geom in state.document.geometry():
		var instance := MeshInstance3D.new()
		var size: Vector3 = geom.size
		match geom.type:
			0:
				var m := PlaneMesh.new()
				m.size = Vector2(maxf(size.x * 2, 10), maxf(size.y * 2, 10))
				instance.mesh = m
			2:
				var m := SphereMesh.new()
				m.radius = size.x
				m.height = size.x * 2
				instance.mesh = m
			3:
				var m := CapsuleMesh.new()
				m.radius = size.x
				m.height = (size.x + size.y) * 2
				instance.mesh = m
			4:
				var m := SphereMesh.new()
				m.radius = 1
				m.height = 2
				instance.mesh = m
			5:
				var m := CylinderMesh.new()
				m.top_radius = size.x
				m.bottom_radius = size.x
				m.height = size.y * 2
				instance.mesh = m
			6:
				var m := BoxMesh.new()
				m.size = Vector3(size.x, size.z, size.y) * 2
				instance.mesh = m
			7:
				var m := ArrayMesh.new()
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = geom.vertices
				arrays[Mesh.ARRAY_NORMAL] = geom.normals
				m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				instance.mesh = m
		if not instance.mesh:
			instance.free()
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = geom.color
		material.roughness = 0.85
		instance.material_override = material
		viewport.add_child(instance)
		instance.transform = geom.transform
		if geom.type == 4:
			instance.scale = Vector3(size.x, size.z, size.y)
		instance.set_meta("pick_mesh", instance.mesh.generate_triangle_mesh())
		meshes[geom.name] = instance
	highlight_selection()

func _process(delta: float) -> void:
	source_poll += delta
	if source_poll >= 2.0:
		source_poll = 0.0; check_sources()
	if not state.document or not visible:
		return
	if visible:
		state.document.advance(delta)
	for geom in state.document.geometry():
		if meshes.has(geom.name):
			meshes[geom.name].transform = geom.transform
			if geom.type == 4:
				meshes[geom.name].scale = Vector3(geom.size.x, geom.size.z, geom.size.y)
	var info: Dictionary = state.document.inspect()
	var detail := ""
	for entity in info.entities:
		if entity.kind == selected.get("kind") and entity.name == selected.get("name"):
			if entity.kind == "joint":
				detail = " | live qpos: " + str(entity.properties.qpos) + " " + entity.properties.unit
			elif entity.kind == "actuator":
				detail = " | live control: " + str(entity.properties.control)
	live.text = "t=%.3f s | contacts=%d | %s%s" % [info.time, info.contacts, "PAUSED" if info.paused else "RUNNING", detail]

func frame_all() -> void:
	var bounds := AABB()
	var first := true
	for geom in state.document.geometry():
		if geom.type == 0 or not meshes.has(geom.name):
			continue
		var mesh: MeshInstance3D = meshes[geom.name]
		var box := mesh.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if not first:
		center = bounds.get_center()
		var aspect := float(viewport.size.x) / maxf(viewport.size.y, 1)
		var angle := atan(tan(deg_to_rad(camera.fov) * .5) * minf(aspect, 1.0))
		distance = maxf(bounds.size.length() * .575 / sin(angle), 1.2)
	update_camera()

func update_camera() -> void:
	camera.position = center + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(center)

func camera_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			pick_geometry(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.85 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.18), .1, 1000)
	elif event is InputEventMouseMotion and orbiting:
		yaw -= event.relative.x * .01
		pitch = clampf(pitch + event.relative.y * .01, -1.4, 1.4)
	update_camera()

func refresh_project_files() -> void:
	# File publication can happen during editor deferred work or an ongoing scan.
	# Wait for a normal frame and serialize scans to avoid progress-dialog reentry.
	await get_tree().process_frame
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning():
		await get_tree().process_frame
	filesystem.scan()

func highlight_selection() -> void:
	for name in meshes:
		var material: StandardMaterial3D = meshes[name].material_override
		material.emission_enabled = selected.get("kind") == "geom" and selected.get("name") == name
		material.emission = Color(.25, .18, .02)

func pick_geometry(point: Vector2) -> String:
	if not can_leave_fields(): return ""
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var nearest := INF
	var picked := ""
	for name in meshes:
		var mesh: MeshInstance3D = meshes[name]
		var inverse := mesh.global_transform.affine_inverse()
		var triangle: TriangleMesh = mesh.get_meta("pick_mesh")
		var hit := triangle.intersect_ray(inverse * origin, inverse.basis * direction)
		if not hit.is_empty():
			var distance_to_hit := origin.distance_to(mesh.global_transform * Vector3(hit.position))
			if distance_to_hit < nearest:
				nearest = distance_to_hit
				picked = name
	if not picked.is_empty(): select_entity("geom", picked)
	return picked

func transform_selection(operation: String, direction: float) -> bool:
	if not can_leave_fields() or selected.is_empty(): return false
	if selected.kind not in ["body", "geom"]:
		show_error("Select a body or visible geometry")
		return false
	var p: Dictionary = selected.properties
	var values := {}
	if operation == "size":
		if selected.kind != "geom" or p.type not in [2,5,6] or not p.get("size_editable", true):
			show_error("Only explicit box/sphere/cylinder dimensions are editable")
			return false
		var size: Array = p.size.duplicate()
		var count := 1 if p.type == 2 else 2 if p.type == 5 else 3
		for index in count: size[index] *= 1.1 if direction > 0 else 1.0/1.1
		for index in range(count,3): size[index] = 0.0
		values.size = size
	else:
		if not p.get("pose_editable", true):
			show_error("Frame/fromto-derived pose is read-only")
			return false
		if operation == "move":
			var position: Array = p.pos.duplicate()
			position[edit_axis] += direction * move_step
			values.pos = position
		elif operation == "rotate":
			var a: Array = p.quat
			var rotation := Quaternion(float(a[1]),float(a[2]),float(a[3]),float(a[0]))
			var axis := Vector3.ZERO
			axis[edit_axis] = 1.0
			rotation = (rotation * Quaternion(axis, deg_to_rad(direction * rotate_step))).normalized()
			values.quat = [rotation.w,rotation.x,rotation.y,rotation.z]
		else: return false
	state.document.set_paused(true)
	return execute({"op":"set", "kind":selected.kind,"name":selected.name,"values":values})

func refresh_runtime_targets() -> void:
	if not is_instance_valid(runtime_targets) or not plugin.live_debugger: return
	runtime_targets.clear()
	var targets: Dictionary = plugin.live_debugger.instances
	for key in targets:
		var info: Dictionary = targets[key]
		runtime_targets.add_item("Session %s • %s" % [info.session,info.path])
		var index := runtime_targets.item_count - 1
		runtime_targets.set_item_metadata(index,key)
		if key == runtime_target_key: runtime_targets.select(index)
	if not targets.has(runtime_target_key):
		runtime_target_key = str(runtime_targets.get_item_metadata(0)) if runtime_targets.item_count else ""
	runtime_apply.disabled = runtime_target_key.is_empty()
	if runtime_target_key.is_empty():
		runtime_status.text = "No runtime instance connected. Run with F5; save a project model before applying."
		return
	var info: Dictionary = targets[runtime_target_key]
	runtime_apply.disabled = info.pending
	var changed: bool = project_model_path != info.resource or state.dirty or pending
	runtime_status.text = "Runtime revision %s • %s • %s" % [info.revision,"Request pending" if info.pending else "Ready", "Design changes not applied" if changed else "Saved resource matches"]
	var outcome:Dictionary=info.get("preset",{})
	if not outcome.is_empty(): runtime_status.text+=" • Preset "+str(outcome.get("status",""))+" #"+str(outcome.get("request",0))
	if not str(info.error).is_empty(): runtime_status.text += " • Failed: " + str(info.error) + " • Fix and retry"

func apply_runtime_model() -> bool:
	if not can_leave_fields(): return false
	if project_model_path.is_empty() or state.dirty or state.document.snapshot() != project_model_snapshot:
		show_error("Save project model before applying its design revision to runtime")
		return false
	if not plugin.live_debugger.send(runtime_target_key,"apply",{"resource":project_model_path}):
		show_error("Runtime target unavailable or request pending")
		return false
	return true

func send_runtime_control() -> bool:
	if not can_leave_fields() or selected.get("kind") != "actuator": return false
	return plugin.live_debugger.send(runtime_target_key,"control",{"actuator":selected.name,"value":selected.properties.control})

func assign_saved_model() -> bool:
	if not can_leave_fields(): return false
	if project_model_path.is_empty() or state.dirty or state.document.snapshot() != project_model_snapshot:
		show_error("Save the project model before assigning its design revision")
		return false
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	if nodes.size() != 1 or not nodes[0] is MjModelInstance:
		show_error("Select one MjModelInstance in the local Godot scene tree")
		return false
	var node: Node = nodes[0]
	var resource = ResourceLoader.load(project_model_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var history := plugin.get_undo_redo()
	history.create_action("Assign MuJoCo design revision",UndoRedo.MERGE_DISABLE,node)
	history.add_do_property(node,"model",resource)
	history.add_undo_property(node,"model",node.model)
	history.commit_action()
	status.text = "Assigned design revision to local scene. Save the scene to persist it; live runtime application is separate."
	return true

func preset_dialog(save:bool) -> void:
	if not can_leave_fields():return
	var dialog=EditorFileDialog.new();dialog.access=EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode=EditorFileDialog.FILE_MODE_SAVE_FILE if save else EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters=PackedStringArray(["*.json ; Control preset"]);add_child(dialog)
	dialog.file_selected.connect(func(path):
		if save:save_control_preset(path)
		else:load_control_preset(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.65)
func save_control_preset(path:String)->bool:
	if not can_leave_fields():return false
	var error=preload("control_presets.gd").save_file(state.document,path)
	if not error.is_empty():show_error(error);return false
	status.text="预设已保存：编辑文档的目标/PD；未保存仿真姿态或运行实例状态";return true
func load_control_preset(path:String)->bool:
	if not can_leave_fields():return false
	var presets=preload("control_presets.gd")
	var input=presets.read_file(path)
	if not input.error.is_empty():show_error(input.error);return false
	var result=presets.candidate(state.document,input.value)
	if not result.error.is_empty():show_error(result.error);return false
	var before:Dictionary=state.document.snapshot()
	if not state.document.restore(result.snapshot):show_error(state.document.get_error());return false
	record_change(before,"Load control preset")
	status.text="预设已加载到编辑文档，可 Undo；运行实例尚未改变。PD需保存模型后显式应用，目标值需选择对应控制并发送。";return true

func runtime_preset_dialog()->void:
	if runtime_target_key.is_empty():show_error("Select one runtime instance");return
	var key=runtime_target_key
	var target=plugin.live_debugger.instances.get(key,{})
	if target.is_empty() or target.pending:show_error("Wait for pending runtime operation");return
	var revision=target.revision
	var dialog=EditorFileDialog.new();dialog.access=EditorFileDialog.ACCESS_FILESYSTEM;dialog.file_mode=EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.title="Apply preset to "+str(target.path)
	dialog.filters=PackedStringArray(["*.json ; Runtime control preset"]);add_child(dialog)
	dialog.file_selected.connect(func(path):
		var input=preload("control_presets.gd").read_file(path)
		if not input.error.is_empty():show_error(input.error)
		elif runtime_target_key!=key or not plugin.live_debugger.instances.has(key) or plugin.live_debugger.instances[key].revision!=revision:show_error("Runtime target/revision changed; reopen preset chooser")
		elif not input.value is Dictionary:show_error("Invalid preset schema")
		elif not plugin.live_debugger.send(key,"preset",{"preset":input.value}):show_error("Runtime target unavailable or pending")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.65)

func check_sources() -> void:
	if source_watch.source.is_empty(): source_status.text = "来源未跟踪（打开旧文档请先导入来源）"; return
	var result: Dictionary = source_watch.inspect(state.dirty or pending)
	source_status.text = "来源：" + result.state + "  " + ", ".join(result.changes) + "  " + result.error

func confirm_reimport() -> void:
	if source_watch.source.is_empty(): show_error("没有已跟踪的来源"); return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "显式从原来源重新导入。未保存编辑与字段草稿会被替换；可先保留本地并另存副本。解析失败保持旧文档。运行实例不自动 Apply。"
	add_child(dialog)
	dialog.confirmed.connect(func(): reimport_source(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func reimport_source() -> bool:
	var candidate: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not candidate.import_file(source_watch.source):
		source_watch.error = candidate.get_error(); show_error(source_watch.error); check_sources(); return false
	var next_watch = preload("res://addons/godot_mujoco/map/source_watch.gd").new()
	if not next_watch.capture(source_watch.source, candidate.asset_manifest().assets):
		show_error(next_watch.error); return false
	var before: Dictionary = state.document.snapshot()
	if not state.document.restore(candidate.snapshot()): show_error(state.document.get_error()); return false
	pending = false; source_watch = next_watch; project_model_path = ""; model_provenance = {}
	record_change(before, "显式重新导入来源")
	state.dirty = false; refresh(); check_sources(); return true
