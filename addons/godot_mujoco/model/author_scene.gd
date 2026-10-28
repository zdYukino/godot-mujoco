@tool
extends RefCounted
const Xml = preload("author_xml.gd")
const Commands = preload("author_commands.gd")
const Body = preload("body_node.gd")
const Geom = preload("geom_node.gd")
const Joint = preload("joint_node.gd")
const Visual = preload("model_visual.gd")
const Service = preload("compile_service.gd")
var host: Node3D
var nodes := {}
var applying := false
var compiler: Node
var due_ms := 0
var pending_transforms := {}
var geometry_queue: Array = []
var geometry_by_name := {}
var body_world := {}
var last_valid: Dictionary = {}
var last_names := {}
var compiled_status := "未验证"
var artifact: Dictionary = {}
var scan_due := 0
var compile_token := ""

func initialize(model: Node3D) -> void:
	host = model
	if not host.design: return
	_collect_nodes(host)
	for entity in host.design.cached_entities:
		if entity.kind == "body": body_world[entity.name] = entity.properties.get("preview_transform", Transform3D.IDENTITY)
	refresh_nodes()
	for entity in host.design.entities():
		if entity.kind == "geom" and nodes.has(entity.id):
			var mesh: MeshInstance3D = nodes[entity.id].get_node_or_null("_Visual")
			if mesh: host.visuals[entity.name] = mesh; host.scales[entity.name] = mesh.scale
	if not host.design.cache_path.is_empty() and FileAccess.file_exists(host.design.cache_path):
		var input := FileAccess.open(host.design.cache_path, FileAccess.READ)
		var cached: Variant = input.get_var(false) if input else null
		if cached is Dictionary and cached.get("success", false) and cached.get("author", {}) == host.design.author_snapshot(): apply_compiled(cached)
	if artifact.is_empty() and host.design.validated_revision == host.design.revision:
		geometry_queue = host.design.cached_geometry.duplicate(true)
		for geometry in geometry_queue: geometry_by_name[geometry.name] = geometry
	if Engine.is_editor_hint():
		compiler = Service.new()
		compiler.name = "_MjCompiler"
		host.add_child(compiler, false, Node.INTERNAL_MODE_BACK)
		compiler.completed.connect(compilation_finished)
		compiler.status_changed.connect(func(text): compiled_status = text; changed())
		queue_compile()

func _collect_nodes(parent: Node) -> void:
	for child in parent.get_children():
		if child.has_method("author_kind") and not child.entity_id.is_empty():
			nodes[child.entity_id] = child
			child.source_model = weakref(host)
		_collect_nodes(child)

func scene_owner() -> Node:
	return host.owner if host.owner else host

func refresh_nodes() -> void:
	if not is_instance_valid(host) or not host.design: return
	applying = true
	var entities: Array = host.design.entities()
	var alive := {}
	for entity in entities:
		alive[entity.id] = true
		var node: Node3D = nodes.get(entity.id)
		if not is_instance_valid(node):
			node = {"body":Body, "geom":Geom, "joint":Joint}[entity.kind].new()
			node.entity_id = entity.id
			nodes[entity.id] = node
		var parent: Node = nodes.get(entity.parent_id, host)
		node.source_model = weakref(host)
		if node.get_parent() != parent:
			if node.get_parent(): node.reparent(parent, false)
			else: parent.add_child(node)
		node.owner = scene_owner()
		node.synchronizing = true
		node.name = str(entity.name).validate_node_name()
		last_names[entity.id] = str(node.name)
		var pose: Transform3D = entity.transform
		if entity.kind == "body" and body_world.has(entity.name):
			var parent_name: String = host.design.source_name(entity.parent_id)
			pose = body_world.get(parent_name, Transform3D.IDENTITY).affine_inverse() * body_world[entity.name]
		elif entity.kind == "joint":
			var axis := Xml.numbers(entity.attrs.get("axis", "0 0 1"))
			if axis.size() == 3 and Vector3(axis[0], axis[1], axis[2]).length() > 1e-10:
				pose.basis = Basis(Quaternion(Vector3.UP, Xml.mj_vector(Vector3(axis[0],axis[1],axis[2])).normalized()))
		node.motion_correction = entity.transform.affine_inverse() * pose if entity.kind == "body" else Transform3D.IDENTITY
		node.set_display_transform(pose)
		node.synchronizing = false
		node.refresh_inspector_schema()
	for identity in nodes.keys():
		if not alive.has(identity):
			var node: Node = nodes[identity]
			if is_instance_valid(node):
				if node.get_parent(): node.get_parent().remove_child(node)
				node.queue_free()
			nodes.erase(identity)
	applying = false

func node_transform_changed(node: Node3D) -> void:
	if applying: return
	if pending_transforms.is_empty(): compile_token = Xml.uuid()
	pending_transforms[node.entity_id] = node.transform
	# Pause is requested at the first change, not after the compilation debounce.
	request_pause()
	due_ms = Time.get_ticks_msec() + 300

func flush_transforms() -> void:
	if pending_transforms.is_empty(): return
	var pending := pending_transforms
	pending_transforms = {}
	for identity in pending:
		var node: Node3D = nodes.get(identity)
		if not is_instance_valid(node): continue
		var value: Transform3D = pending[identity]
		var scale := value.basis.get_scale()
		if not scale.is_equal_approx(Vector3.ONE):
			var error := apply_scale(node, scale)
			if not error.is_empty(): host.last_error = error
			node.set_display_transform(node.displayed_transform)
			continue
		var target: Transform3D = value * node.motion_correction.affine_inverse()
		if target.is_equal_approx(host.design.entity(identity).get("transform", Transform3D.IDENTITY)):
			node.displayed_transform = value
			continue
		var result := Commands.execute(host.design, {"op":"pose", "id":identity, "transform":target})
		if result.error.is_empty():
			host.design.restore_author(result.after)
			node.displayed_transform = value
			compile_token = Xml.uuid()
			due_ms = Time.get_ticks_msec() + 300
			changed()
		else:
			host.last_error = result.error
			node.set_display_transform(node.displayed_transform)

func apply_scale(node: Node3D, scale: Vector3) -> String:
	if node.author_kind() != "geom": return "Body and joint transforms cannot be scaled"
	if not scale.is_finite() or scale.x <= 0 or scale.y <= 0 or scale.z <= 0: return "Physical scale must be positive and finite"
	var entity: Dictionary = host.design.entity(node.entity_id)
	var shape: String = entity.attrs.get("type", "sphere")
	var size := Xml.numbers(entity.attrs.get("size", ".1 .1 .1"))
	if shape == "sphere":
		if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z): return "A sphere requires uniform scale"
		size[0] *= scale.x
	elif shape in ["cylinder", "capsule"]:
		if not is_equal_approx(scale.x, scale.z): return "Cylinder/capsule radial scales must match"
		size[0] *= scale.x
		size[1] *= scale.y
	elif shape in ["box", "ellipsoid", "plane"]:
		if size.size() < 3: size.resize(3)
		size[0] *= scale.x
		size[1] *= scale.z
		size[2] *= scale.y
	elif shape == "mesh":
		var previous: Vector3 = node.get("mjcf/mesh_scale")
		var result: Dictionary = host.apply_author_command({"op":"mesh_scale", "id":node.entity_id, "value":previous * scale}, false)
		return str(result.get("error", ""))
	else: return "Use the terrain editor for this geometry"
	var result: Dictionary = host.apply_author_command({"op":"set", "id":node.entity_id, "values":{"size":Array(size)}}, false)
	return str(result.get("error", ""))

func request_pause() -> void:
	if not Engine.is_editor_hint(): return
	var plugin: Node = EditorInterface.get_base_control().get_meta("mujoco_author_plugin", null)
	if plugin and plugin.has_method("author_changed"): plugin.author_changed(host, true)

func changed() -> void:
	if Engine.is_editor_hint():
		var plugin: Node = EditorInterface.get_base_control().get_meta("mujoco_author_plugin", null)
		if plugin and plugin.has_method("author_status_changed"): plugin.author_status_changed(host)

func queue_compile() -> void:
	compile_token = Xml.uuid()
	due_ms = Time.get_ticks_msec() + 300
	compiled_status = "等待后台验证"
	request_pause()
	changed()

func poll() -> void:
	if not host or not host.design: return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): flush_transforms()
	if pending_transforms.is_empty() and due_ms > 0 and Time.get_ticks_msec() >= due_ms and compiler:
		due_ms = 0
		compiler.submit({"author":host.design.author_snapshot(), "revision":host.design.revision, "generation":compile_token})
	build_geometry_step()

func compilation_finished(result: Dictionary) -> void:
	if result.generation != compile_token or int(result.revision) != host.design.revision: return
	if not result.get("success", false):
		host.design.validation_error = result.get("error", "Compilation failed")
		host.last_error = host.design.validation_error
		changed()
		return
	host.design.cache_path = str(result.directory).path_join("result.bin")
	apply_compiled(result)
	if Engine.is_editor_hint():
		var plugin: Node = EditorInterface.get_base_control().get_meta("mujoco_author_plugin", null)
		if plugin and plugin.has_method("author_compiled"): plugin.author_compiled(host, result)

func apply_compiled(result: Dictionary) -> void:
	artifact = result
	host.last_error = ""
	host.design.validated_revision = host.design.revision
	host.design.validation_error = ""
	host.design.cached_entities = result.get("entities", []).duplicate(true)
	host.design.cached_geometry = result.get("geometry", []).duplicate(true)
	host.design.collision_geometry = result.get("collision_geometry", []).duplicate(true)
	host.design.compiled_snapshot = result.get("snapshot", {}).duplicate(true)
	body_world.clear()
	for entity in host.design.cached_entities:
		if entity.kind == "body": body_world[entity.name] = entity.properties.get("preview_transform", Transform3D.IDENTITY)
	geometry_by_name.clear()
	geometry_queue = result.get("geometry", []).duplicate()
	for geometry in geometry_queue: geometry_by_name[geometry.name] = geometry
	last_valid = host.design.author_snapshot()
	refresh_nodes()
	compiled_status = "有效 · 显示资源准备中"
	changed()

func build_geometry_step() -> void:
	if geometry_queue.is_empty(): return
	var started := Time.get_ticks_usec()
	while not geometry_queue.is_empty() and Time.get_ticks_usec() - started < 3000:
		var geometry: Dictionary = geometry_queue.pop_front()
		var entity := {}
		for item in host.design.entities():
			if item.kind == "geom" and item.name == geometry.name:
				entity = item
				break
		if entity.is_empty(): continue
		var node: Node3D = nodes.get(entity.id)
		if not is_instance_valid(node): continue
		var previous := node.get_node_or_null("_Visual") as MeshInstance3D
		var old_visible := previous.visible if previous else true
		if previous:
			node.remove_child(previous)
			previous.queue_free()
		var instance: MeshInstance3D = Visual.create(geometry)
		if not instance: continue
		instance.name = "_Visual"
		var scale := instance.scale
		var parent_world: Transform3D = body_world.get(host.design.source_name(entity.parent_id), Transform3D.IDENTITY)
		instance.transform = node.transform.affine_inverse() * parent_world.affine_inverse() * geometry.transform
		instance.scale *= scale
		instance.visible = old_visible
		node.add_child(instance)
		instance.owner = scene_owner()
		host.visuals[geometry.name] = instance
		host.scales[geometry.name] = instance.scale
	if geometry_queue.is_empty():
		compiled_status = "有效"
		changed()

func update_runtime(state: Dictionary) -> void:
	applying = true
	for entity in host.design.entities():
		if entity.kind != "body" or not state.get("bodies", {}).has(entity.name): continue
		var node: Node3D = nodes.get(entity.id)
		if is_instance_valid(node):
			node.synchronizing = true
			node.global_transform = state.bodies[entity.name].transform
			node.synchronizing = false
	applying = false

func cancel_compile() -> void:
	due_ms = 0
	if compiler: compiler.cancel()
	compile_token = Xml.uuid()
	compiled_status = "编译已取消"
	host.design.validation_error = "编译已取消；继续编辑或恢复上次有效设计。"
	host.last_error = host.design.validation_error
	changed()

func shutdown() -> void:
	if is_instance_valid(compiler):
		compiler.cancel()
		compiler.queue_free()
	compiler = null
