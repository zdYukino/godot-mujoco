@tool
extends RefCounted
const Xml = preload("author_xml.gd")
const Commands = preload("author_commands.gd")
const Body = preload("body_node.gd")
const Geom = preload("geom_node.gd")
const Joint = preload("joint_node.gd")
const Visual = preload("model_visual.gd")
const Service = preload("compile_service.gd")
const Artifact = preload("editor_artifact.gd")
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
var compilation_context := ""
var _observed_design: WeakRef
var _queue_design: WeakRef
var _queue_source: Dictionary = {}
var _queue_ids := {}
var _queue_context := ""
var _queue_host := 0
var _queue_instance := ""
var _queue_generation := 0
var _queue_dependency_generation := 0
var _queue_active := false
var _presentation_error := ""
var _closed := false
var verification_state := "unverified"
var last_artifact_kind := ""
var cache_miss_reason := ""
var _scheduled_source: Dictionary = {}
var _request_source: Dictionary = {}
var _request_payload: Dictionary = {}
var _request_design: WeakRef
var _request_context := ""
var _dependency_generation := 0
var _request_dependency_generation := -1
var _file_observation: Dictionary = {}
var _source_paths: Array = []
var _files_due_ms := 0
var _filesystem: EditorFileSystem
var _fresh_preview_paths := {}
var _reuse_existing := true
var _verification_active := false
var _recheck_pending := false
var _staged_compiled: Dictionary = {}
var _request_uses_staged := false

func initialize(model: Node3D, reuse_existing := true) -> void:
	_disconnect_design()
	_disconnect_filesystem()
	if is_instance_valid(compiler): compiler.cancel()
	_retire_geometry(false)
	_closed = false
	host = model
	_reuse_existing = reuse_existing
	verification_state = "unverified"
	_verification_active = false; _recheck_pending = false; _staged_compiled = {}
	_scheduled_source = {}; _request_source = {}; _file_observation = {}
	_source_paths = []
	compile_token = Xml.uuid(); due_ms = 0
	artifact = {}; last_valid = {}; last_names.clear()
	if not host.design: return
	compilation_context = host.compilation_signature()
	# Unqualified serialized metadata is only a presentation hint. Drop malformed
	# records before any Inspector/native-fallback/visual consumer can read them;
	# the changed/missing payload still produces a worker miss and repair.
	if not host.design.cached_entities.all(Artifact.entity_record): host.design.cached_entities = []
	if not host.design.cached_geometry.all(Artifact.geometry_record): host.design.cached_geometry = []
	if not host.design.collision_geometry.all(Artifact.geometry_record): host.design.collision_geometry = []
	if not host.design.collision_stats.all(func(stat): return stat is Dictionary and stat.get("mesh") is String and stat.has("depth") and stat.has("cells")): host.design.collision_stats = []
	_watch_design()
	nodes.clear(); body_world.clear(); pending_transforms.clear()
	_collect_nodes(host)
	for entity in host.design.cached_entities:
		if entity.kind == "body": body_world[entity.name] = entity.properties.get("preview_transform", Transform3D.IDENTITY)
	refresh_nodes()
	var snapshot: Dictionary = host.design.entity_snapshot()
	var cached_by_name := {}
	for geometry in host.design.cached_geometry: cached_by_name[geometry.name] = geometry
	for entity in snapshot.entities:
		if entity.kind == "geom" and nodes.has(entity.id):
			var mesh: MeshInstance3D = nodes[entity.id].get_node_or_null("_Visual")
			if mesh and cached_by_name.has(entity.name): Visual.seed(mesh, cached_by_name[entity.name])
	_sync_visual_maps(snapshot)
	# Saved views are the last visible preview, never a current-session approval.
	# Runtime continues to use its authoritative shared-world composition path.
	if not Engine.is_editor_hint() and host.design.validated_revision == host.design.revision and host.design.validated_context == host.compilation_signature():
		_publish_geometry(host.design.cached_geometry, host.design.author_snapshot(), snapshot)
		last_valid = _queue_source.duplicate(true)
	if Engine.is_editor_hint():
		if host.is_inside_tree(): _watch_filesystem()
		ensure_compiler()
		queue_compile()

func _watch_design() -> void:
	if _observed_design and _observed_design.get_ref() == host.design: return
	_disconnect_design()
	_observed_design = weakref(host.design)
	host.design.design_changed.connect(_source_changed)

func _disconnect_design() -> void:
	var design: Resource = _observed_design.get_ref() if _observed_design else null
	if design and design.design_changed.is_connected(_source_changed): design.design_changed.disconnect(_source_changed)
	_observed_design = null

func _source_changed() -> void:
	verification_state = "unverified"
	_verification_active = false; _recheck_pending = false; _staged_compiled = {}
	compile_token = Xml.uuid()
	_retire_geometry(true)

func _retire_geometry(waiting: bool) -> void:
	_queue_generation += 1
	_queue_active = false
	_queue_source = {}
	_queue_ids.clear(); geometry_by_name.clear(); geometry_queue = []
	_fresh_preview_paths.clear()
	_presentation_error = ""
	# The existing runtime ready gate observes queue emptiness. A retired or
	# failed current presentation must wait for accepted work, not certify ready.
	if waiting:
		geometry_queue.append({"_waiting":true})
		compiled_status = "等待当前设计的显示资源"

func _queue_matches_source() -> bool:
	if _closed or not is_instance_valid(host) or host.is_queued_for_deletion() or host.author_scene != self: return false
	if not host.design or not _queue_design or _queue_design.get_ref() != host.design or _queue_source.is_empty(): return false
	if host.get_instance_id() != _queue_host or host.design_instance_id != _queue_instance or host.compilation_signature() != _queue_context: return false
	if _queue_dependency_generation != _dependency_generation: return false
	# author_snapshot owns this input contract; compare its actual fields without
	# cloning the whole XML for every item. The tree-only query epoch is not enough.
	return host.design.matches_author_snapshot(_queue_source)

func _publish_geometry(geometry: Array, source: Dictionary, snapshot: Dictionary, fresh_paths: Array = []) -> void:
	var accepted := geometry.duplicate(true)
	_retire_geometry(false)
	_queue_source = source
	_queue_design = weakref(host.design)
	_queue_context = host.compilation_signature()
	_queue_host = host.get_instance_id()
	_queue_instance = host.design_instance_id
	_queue_dependency_generation = _dependency_generation
	for path in fresh_paths: _fresh_preview_paths[path] = true
	for item in accepted:
		geometry_by_name[item.name] = item
		var entity: Dictionary = snapshot.geom_by_name.get(item.name, {})
		if entity.is_empty(): continue
		_queue_ids[item.name] = entity.id
		geometry_queue.append(item)
	_queue_active = not geometry_queue.is_empty()
	compiled_status = "有效 · 显示资源准备中" if _queue_active else "有效"

func _sync_visual_maps(snapshot: Dictionary) -> void:
	var visuals := {}; var scales := {}
	for entity in snapshot.entities:
		if entity.kind != "geom": continue
		var node: Variant = nodes.get(entity.id)
		if not is_instance_valid(node): continue
		var visual := node.get_node_or_null("_Visual") as MeshInstance3D
		if visual and not visual.is_queued_for_deletion():
			visuals[entity.name] = visual; scales[entity.name] = visual.scale
	host.visuals.clear(); host.visuals.merge(visuals)
	host.scales.clear(); host.scales.merge(scales)

func ensure_compiler() -> void:
	if not Engine.is_editor_hint() or compiler or not EditorInterface.get_base_control().has_meta("mujoco_author_plugin"): return
	compiler = Service.new()
	compiler.name = "_MjCompiler"
	host.add_child(compiler, false, Node.INTERNAL_MODE_BACK)
	compiler.completed.connect(compilation_finished)
	compiler.status_changed.connect(func(text): compiled_status = text; changed())

func _watch_filesystem() -> void:
	_filesystem = EditorInterface.get_resource_filesystem()
	_filesystem.filesystem_changed.connect(_filesystem_changed)
	_filesystem.resources_reimported.connect(_resources_reimported)
	if _filesystem.has_signal("resources_reload"): _filesystem.connect("resources_reload", _resources_reimported)

func _disconnect_filesystem() -> void:
	if is_instance_valid(_filesystem):
		if _filesystem.filesystem_changed.is_connected(_filesystem_changed): _filesystem.filesystem_changed.disconnect(_filesystem_changed)
		if _filesystem.resources_reimported.is_connected(_resources_reimported): _filesystem.resources_reimported.disconnect(_resources_reimported)
		if _filesystem.has_signal("resources_reload") and _filesystem.is_connected("resources_reload", _resources_reimported): _filesystem.disconnect("resources_reload", _resources_reimported)
	_filesystem = null

func _filesystem_changed() -> void:
	var generation := _dependency_generation
	_check_files(true)
	if _closed or generation != _dependency_generation or _file_observation.is_empty(): return
	# This signal has no paths. Same-size writes can retain the public API's
	# second-resolution timestamp, including raw non-imported dependencies.
	# An ambiguous notification therefore requires a bounded file recheck.
	# A production reply can seed that follow-up without compiling twice.
	_file_notification()

func _file_notification() -> void:
	_dependency_generation += 1
	_retire_geometry(true)
	if _verification_active:
		_recheck_pending = true
		verification_state = "pending"
		compiled_status = "等待文件变化后的后台验证"
		request_pause(); changed()
	else: queue_compile()

func _resources_reimported(paths: PackedStringArray) -> void:
	if _closed or not is_instance_valid(host) or not host.design: return
	for path in paths:
		if not _file_observation.has(path): continue
		# Named unrelated events are ignored. Relevant own writes may need one
		# follow-up hit, which publishes no files and therefore cannot self-loop.
		_file_notification(); return

func _check_files(force := false) -> void:
	if _closed or not is_instance_valid(host) or not host.design: return
	var now := Time.get_ticks_msec()
	if not force and now < _files_due_ms: return
	_files_due_ms = now + 500
	# While producing, the worker owns changes to generated preview files. It
	# verifies their bytes and returns the observation after atomic publication.
	var paths := _source_paths if verification_state == "pending" else _file_observation.keys()
	var current := Artifact.observe_files(paths)
	for path in current:
		if current[path] != _file_observation.get(path):
			_file_observation.merge(current, true)
			_file_notification(); return

func editor_ready(check_files := false) -> bool:
	if _closed or not is_instance_valid(host) or host.author_scene != self or not host.design: return false
	if check_files: _check_files(true)
	if verification_state != "ready" or not host.design.matches_author_snapshot(_scheduled_source): return false
	if host.compilation_signature() != compilation_context or host.design.validated_revision != host.design.revision or host.design.validated_context != compilation_context: return false
	return host.design.validation_error.is_empty() and pending_transforms.is_empty() and geometry_queue.is_empty() and due_ms == 0 and (not is_instance_valid(compiler) or not compiler.busy())

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
	var snapshot: Dictionary = host.design.entity_snapshot()
	var entities: Array = snapshot.entities
	var alive := {}
	for entity in entities:
		alive[entity.id] = true
		# Native deletion can leave a freed (or queued) Object in this map until
		# cancel/Undo refreshes the authored hierarchy. Validate the Variant before
		# assigning a typed Node; Godot rejects a freed assignment immediately.
		var previous: Variant = nodes.get(entity.id)
		var node: Node3D
		if is_instance_valid(previous) and not previous.is_queued_for_deletion(): node = previous
		else:
			if is_instance_valid(previous) and previous.get_parent(): previous.get_parent().remove_child(previous)
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
			var parent_name: String = snapshot.names.get(entity.parent_id, "")
			pose = body_world.get(parent_name, Transform3D.IDENTITY).affine_inverse() * body_world[entity.name]
		elif entity.kind == "joint":
			var axis := Xml.numbers(entity.attrs.get("axis", "0 0 1"))
			if axis.size() == 3 and Vector3(axis[0], axis[1], axis[2]).length() > 1e-10:
				pose.basis = Basis(Quaternion(Vector3.UP, Xml.mj_vector(Vector3(axis[0],axis[1],axis[2])).normalized()))
		node.motion_correction = entity.transform.affine_inverse() * pose if entity.kind == "body" else Transform3D.IDENTITY
		node.set_display_transform(pose)
		node.synchronizing = false
		node.refresh_inspector_schema(snapshot)
	for identity in nodes.keys():
		if not alive.has(identity):
			var previous: Variant = nodes[identity]
			if is_instance_valid(previous):
				var node: Node = previous
				if node.get_parent(): node.get_parent().remove_child(node)
				node.queue_free()
			nodes.erase(identity)
	_sync_visual_maps(snapshot)
	applying = false

func node_transform_changed(node: Node3D) -> void:
	if applying: return
	if pending_transforms.is_empty():
		_retire_geometry(true)
		verification_state = "unverified"
		compile_token = Xml.uuid()
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
		# Native reparent changes local coordinates before source reconciliation.
		# Keep that final local value until it belongs to the source's new parent:
		# reparent alone then compares equal, while a following drag is preserved.
		if node.author_model() != host: continue
		var entity: Dictionary = host.design.entity(identity)
		if entity.is_empty(): continue
		var parent_id: String = node.get_parent().entity_id if node.get_parent().has_method("author_kind") else ""
		if parent_id != entity.parent_id:
			pending_transforms[identity] = value
			continue
		var scale := value.basis.get_scale()
		if not scale.is_equal_approx(Vector3.ONE):
			var error := apply_scale(node, scale)
			if not error.is_empty(): host.last_error = error
			node.set_display_transform(node.displayed_transform)
			continue
		var target: Transform3D = value * node.motion_correction.affine_inverse()
		if target.is_equal_approx(entity.transform):
			node.set_display_transform(value)
			continue
		var result := Commands.execute(host.design, {"op":"pose", "id":identity, "transform":target})
		if result.error.is_empty():
			host.design.restore_author(result.after)
			node.set_display_transform(value)
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
	elif shape in ["mesh","sdf"]:
		var previous: Vector3 = node.get("mjcf/mesh_scale")
		var result: Dictionary = host.apply_author_command({"op":"mesh_scale", "id":node.entity_id, "value":previous * scale}, false)
		return str(result.get("error", ""))
	else: return "Use the terrain editor for this geometry"
	var result: Dictionary = host.apply_author_command({"op":"set", "id":node.entity_id, "values":{"size":Array(size)}}, false)
	return str(result.get("error", ""))

func request_pause() -> void:
	if not Engine.is_editor_hint(): return
	var plugin: Node = (EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
	if plugin and plugin.has_method("author_changed"): plugin.author_changed(host, true)

func changed() -> void:
	if _closed: return
	if Engine.is_editor_hint():
		var plugin: Node = (EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
		if plugin and plugin.has_method("author_status_changed"): plugin.author_status_changed(host)

func queue_compile() -> void:
	if _closed or not is_instance_valid(host) or not host.design: return
	if _queue_active and not _queue_matches_source(): _retire_geometry(true)
	compilation_context = host.compilation_signature()
	compile_token = Xml.uuid()
	verification_state = "pending"
	_verification_active = false; _recheck_pending = false; _staged_compiled = {}
	_scheduled_source = host.design.author_snapshot()
	_source_paths = host.design.dependencies.keys()
	var paths: Array = _source_paths.duplicate()
	for path in Artifact.preview_paths(Artifact.payload(host.design)):
		if not paths.has(path): paths.append(path)
	_file_observation = Artifact.observe_files(paths)
	_files_due_ms = Time.get_ticks_msec() + 500
	due_ms = Time.get_ticks_msec() + 300
	compiled_status = "等待后台验证"
	request_pause()
	changed()

func poll() -> void:
	if _closed or not is_instance_valid(host) or not host.design: return
	if Engine.is_editor_hint() and host.is_inside_tree() and not is_instance_valid(_filesystem): _watch_filesystem()
	ensure_compiler()
	if not _observed_design or _observed_design.get_ref() != host.design:
		_watch_design(); _retire_geometry(true); queue_compile()
	if verification_state == "unverified" or compilation_context != host.compilation_signature() or not host.design.matches_author_snapshot(_scheduled_source): queue_compile()
	_check_files()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): flush_transforms()
	if pending_transforms.is_empty() and due_ms > 0 and Time.get_ticks_msec() >= due_ms and compiler:
		due_ms = 0
		compiler.submit(_validation_request())
	build_geometry_step()

func _validation_request() -> Dictionary:
	_request_source = host.design.author_snapshot()
	_request_uses_staged = not _staged_compiled.is_empty()
	_request_payload = (Artifact.result_payload(_staged_compiled) if _request_uses_staged else Artifact.payload(host.design)).duplicate(true)
	var stamp: Dictionary = _staged_compiled.editor_artifact_stamp if _request_uses_staged else host.design.editor_artifact_stamp
	_request_design = weakref(host.design)
	_request_context = host.compilation_signature()
	_request_dependency_generation = _dependency_generation
	_verification_active = true; _recheck_pending = false
	return {"op":"verify_or_compile", "author":_request_source, "revision":host.design.revision, "generation":compile_token, "context":host.compilation_context(), "editor_artifact_stamp":stamp, "payload":_request_payload}

func compilation_finished(result: Dictionary) -> void:
	if _closed or not is_instance_valid(host) or host.author_scene != self: return
	if result.generation != compile_token or int(result.revision) != host.design.revision: return
	if not _request_design or _request_design.get_ref() != host.design or not host.design.matches_author_snapshot(_request_source): return
	if host.compilation_signature() != _request_context or _request_context != compilation_context: return
	if result.has("author") and not host.design.matches_author_snapshot(result.author): return
	_verification_active = false
	if not result.get("success", false):
		if not result.get("cancelled", false) and (_recheck_pending or _request_dependency_generation != _dependency_generation):
			var staged := _staged_compiled
			queue_compile(); _staged_compiled = staged
			return
		_recheck_pending = false; _staged_compiled = {}
		verification_state = "cancelled" if result.get("cancelled", false) else "error"
		host.design.validation_error = result.get("error", "Compilation failed")
		host.last_error = host.design.validation_error
		changed()
		return
	var stamp: Dictionary = result.get("editor_artifact_stamp", {})
	if result.get("author_digest") != Artifact.digest(_request_source) or result.get("context_digest") != Artifact.digest(host.compilation_context()) or stamp.get("author_digest") != result.author_digest: return
	var observation: Dictionary = result.get("file_observation", {})
	if _recheck_pending or _request_dependency_generation != _dependency_generation or Artifact.observe_files(observation.keys()) != observation:
		# Own generated-file notifications and an ambiguous source event may be
		# coalesced together. Never bless that ambiguity or discard a valid newly
		# produced candidate: verify its bytes in a follow-up with no new native
		# compilation. It remains private/unapproved until that request succeeds.
		var staged := result if result.get("artifact_kind") == "compiled" else _staged_compiled
		queue_compile()
		_staged_compiled = staged
		return
	_file_observation = observation
	_files_due_ms = Time.get_ticks_msec() + 500
	host.design.cache_path = ""
	last_artifact_kind = result.get("artifact_kind", "")
	cache_miss_reason = result.get("cache_miss_reason", "")
	if last_artifact_kind == "hit" and _request_uses_staged:
		var accepted := _staged_compiled.duplicate()
		accepted.generation = compile_token; accepted.revision = host.design.revision
		cache_miss_reason = accepted.get("cache_miss_reason", "")
		apply_compiled(accepted)
	elif last_artifact_kind == "hit":
		if Artifact.payload(host.design) != _request_payload:
			queue_compile(); return
		# Keep the loaded payload, then audit actual live geometry/material data
		# through B's bounded preparer. Paths/descriptors alone do not certify a
		# cached Mesh/Texture. Equivalent resources incur no presentation writes.
		host.design.editor_artifact_stamp = stamp.duplicate(true)
		host.design.validated_revision = host.design.revision
		host.design.validated_context = compilation_context
		host.design.validation_error = ""; host.last_error = ""
		_publish_geometry(host.design.cached_geometry, _request_source, host.design.entity_snapshot(), Artifact.preview_paths(_request_payload))
		last_valid = _request_source.duplicate(true)
		compiled_status = "保存的预览已验证 · 检查显示资源"
	else:
		apply_compiled(result)
	if not host.design.matches_author_snapshot(_request_source) or not host.design.validation_error.is_empty(): return
	verification_state = "ready"
	_staged_compiled = {}; _recheck_pending = false
	changed()
	if Engine.is_editor_hint():
		var plugin: Node = (EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
		if plugin and plugin.has_method("author_compiled"): plugin.author_compiled(host, result)

func apply_compiled(result: Dictionary, initial := false) -> void:
	if _closed or not is_instance_valid(host) or host.author_scene != self or not host.design: return
	if not pending_transforms.is_empty(): return
	var source: Dictionary = host.design.author_snapshot()
	if result.has("author") and result.author != source: return
	if result.has("revision") and int(result.revision) != host.design.revision: return
	if result.has("generation") and not compile_token.is_empty() and result.generation != compile_token: return
	if not str(result.get("context", "")).is_empty() and result.context != host.compilation_signature(): return
	if not result.get("success", true): return
	# An arbitrary direct/legacy payload publication is not a worker approval.
	# compilation_finished alone re-grants current editor readiness afterward.
	if Engine.is_editor_hint(): verification_state = "unverified"
	_watch_design()
	artifact = result
	host.last_error = ""
	host.design.validated_revision = host.design.revision
	host.design.validation_error = ""
	host.design.cached_entities = result.get("entities", []).duplicate(true)
	host.design.cached_geometry = result.get("geometry", []).duplicate(true)
	host.design.collision_geometry = result.get("collision_geometry", []).duplicate(true)
	host.design.collision_stats = result.get("collision_stats", []).duplicate(true)
	host.design.validated_context = result.get("context", "")
	host.design.compiled_snapshot = result.get("snapshot", {}).duplicate(true)
	# Existing builder/runtime replays may omit additive qualification metadata.
	# Preserve it; changed payload/source still fails its complete worker digest.
	if result.has("editor_artifact_stamp"): host.design.editor_artifact_stamp = result.editor_artifact_stamp.duplicate(true)
	host.design.cache_path = ""
	body_world.clear()
	for entity in host.design.cached_entities:
		if entity.kind == "body": body_world[entity.name] = entity.properties.get("preview_transform", Transform3D.IDENTITY)
	_publish_geometry(host.design.cached_geometry, source, host.design.entity_snapshot(), result.get("repaired_preview_paths", []))
	last_valid = source.duplicate(true)
	var generation := _queue_generation
	refresh_nodes()
	if generation != _queue_generation: return
	changed()

func build_geometry_step() -> void:
	if geometry_queue.is_empty(): return
	if _closed or not _presentation_error.is_empty() or geometry_queue[0].get("_waiting", false): return
	var started := Time.get_ticks_usec()
	if not _queue_active:
		# Retain the existing direct cached-queue replay used by standalone callers.
		if geometry_queue != host.design.cached_geometry or host.design.author_snapshot() != last_valid:
			_retire_geometry(true); return
		_publish_geometry(geometry_queue, host.design.author_snapshot(), host.design.entity_snapshot())
	if not _queue_matches_source():
		_retire_geometry(true); return
	var generation := _queue_generation
	var snapshot: Dictionary = host.design.entity_snapshot()
	var recheck := false
	var processed := 0
	while not geometry_queue.is_empty() and (processed == 0 or Time.get_ticks_usec() - started < 3000):
		if generation != _queue_generation: return
		if recheck and not _queue_matches_source():
			_retire_geometry(true); return
		var geometry: Dictionary = geometry_queue[0]
		var identity: String = _queue_ids.get(geometry.name, "")
		var node: Variant = nodes.get(identity)
		if not is_instance_valid(node) or node.author_model() != host:
			_retire_geometry(true); return
		var entity: Dictionary = snapshot.by_id.get(identity, {})
		var parent_id: String = node.get_parent().entity_id if node.get_parent().has_method("author_kind") else ""
		if entity.is_empty() or parent_id != entity.parent_id:
			_retire_geometry(true); return
		var previous := node.get_node_or_null("_Visual") as MeshInstance3D
		var prepared: Dictionary = Visual.prepare_update(previous, geometry, _fresh_preview_paths)
		if not prepared.error.is_empty():
			_presentation_error = prepared.error
			host.last_error = _presentation_error
			host.design.validation_error = _presentation_error
			compiled_status = "显示资源失败 · " + _presentation_error
			changed(); return
		# An unchanged descriptor performs no external resource/node operations;
		# share this immutable stage. Resource preparation and prior writes can
		# reenter user code, so those boundaries revalidate actual source content.
		if generation != _queue_generation or (prepared.requires_validation and not _queue_matches_source()):
			if generation == _queue_generation: _retire_geometry(true)
			return
		var instance: MeshInstance3D = previous if previous else MeshInstance3D.new()
		var parent_world: Transform3D = body_world.get(snapshot.names.get(entity.get("parent_id", ""), ""), Transform3D.IDENTITY)
		var pose: Transform3D = node.transform.affine_inverse() * parent_world.affine_inverse() * geometry.transform
		pose.basis *= Basis.from_scale(Visual.shape_scale(geometry))
		recheck = Visual.apply_update(instance, prepared, pose)
		if not previous:
			instance.name = "_Visual"; node.add_child(instance)
		if instance.owner != scene_owner(): instance.owner = scene_owner()
		if generation != _queue_generation: return
		host.visuals[entity.name] = instance
		host.scales[entity.name] = instance.scale
		geometry_queue.pop_front()
		processed += 1
	if geometry_queue.is_empty():
		if not _queue_matches_source():
			_retire_geometry(true); return
		_queue_active = false
		_fresh_preview_paths.clear()
		compiled_status = "有效 · 已验证保存的预览" if last_artifact_kind == "hit" else "有效 · 已重新编译" if last_artifact_kind == "compiled" else "有效"
		changed()

func drain_geometry() -> String:
	# Synchronous builders must surface failed/waiting work instead of spinning
	# forever on the deliberately nonempty runtime-readiness barrier.
	for attempt in geometry_queue.size() + 1:
		if _closed: return "Visual application has stopped"
		if not _presentation_error.is_empty(): return _presentation_error
		if geometry_queue.is_empty(): return ""
		if geometry_queue[0].get("_waiting", false): return "Visuals are waiting for current accepted source data"
		var remaining := geometry_queue.size()
		build_geometry_step()
		if not _presentation_error.is_empty(): return _presentation_error
		if _closed: return "Visual application has stopped"
		if geometry_queue.is_empty(): return ""
		if geometry_queue[0].get("_waiting", false): return "Visuals are waiting for current accepted source data"
		if geometry_queue.size() >= remaining: return "Visual application made no progress"
	return "Visual application did not settle"

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
	_retire_geometry(true)
	due_ms = 0
	verification_state = "cancelled"
	_verification_active = false; _recheck_pending = false; _staged_compiled = {}
	compile_token = Xml.uuid()
	if is_instance_valid(compiler): compiler.cancel()
	compiled_status = "编译已取消"
	host.design.validation_error = "编译已取消；继续编辑或恢复上次有效设计。"
	host.last_error = host.design.validation_error
	changed()

func shutdown() -> void:
	_closed = true
	verification_state = "closed"
	_disconnect_design()
	_disconnect_filesystem()
	_retire_geometry(false)
	if is_instance_valid(compiler):
		compiler.cancel()
		compiler.queue_free()
	compiler = null
