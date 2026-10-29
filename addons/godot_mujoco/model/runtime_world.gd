@tool
class_name MjRuntimeWorld
extends Node3D
const AuthorBridge = preload("author_live_bridge.gd")
const Layout = preload("world_layout.gd")
const Author = preload("author_resource.gd")
const Collision = preload("collision_settings.gd")
@export var world_design: MjAuthorResource
@export var start_paused := false
var space := RID()
var last_error := ""
var ready_for_models := false
signal command_finished(result: Dictionary)
var command_request := 0
var game_elapsed := 0.0
var last_command_result := {}
var author_compiler: Node
var queued_design_revision := -1
var author_started := false
var resume_after_capture := false
var manual_resume_required := false
signal world_ready
signal editor_connection_changed(connected: bool)
signal design_request_finished(result: Dictionary)
var author_live_id := ""
var editor_connected := false
var source_layout: Dictionary = {}
var pending_author_views := {}
var retiring_nodes: Array[Node] = []
var views_pending := false
var publish_at := 0

func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	last_error = ""
	author_started = false
	editor_connected = false
	manual_resume_required = false
	queued_design_revision = -1
	views_pending = false
	if ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false):
		last_error = "MjRuntimeWorld currently requires the default main-thread physics mode"
		push_error(last_error)
		return
	if not PhysicsServer3D.has_method("scene_enable_authoring"):
		last_error = "Select MuJoCo as the project's 3D physics engine and restart"
		push_error(last_error)
		return
	if not world_design:
		last_error = "Assign a world_design author resource to define global MuJoCo options"
		push_error(last_error)
		return
	var world := get_world_3d()
	if world.has_meta("mj_runtime_owner") and is_instance_valid(world.get_meta("mj_runtime_owner").get_ref()):
		last_error = "Only one MjRuntimeWorld may own a World3D; use a separate SubViewport for another world"
		push_error(last_error)
		return
	space = world.space
	if not PhysicsServer3D.call("scene_enable_authoring",space,world_design.worker_xml()):
		last_error = PhysicsServer3D.call("scene_info",space).last_error; push_error(last_error); return
	world.set_meta("mj_runtime_owner",weakref(self))
	ready_for_models = true

func _ready() -> void:
	if not Engine.is_editor_hint() and ready_for_models and world_design:
		author_compiler = preload("compile_service.gd").new()
		add_child(author_compiler, false, Node.INTERNAL_MODE_BACK)
		author_compiler.completed.connect(author_world_compiled)
		source_layout = Layout.capture(self)
		AuthorBridge.attach(self)
		return

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	if not author_live_id.is_empty(): AuthorBridge.detach(self)
	if author_compiler:
		author_compiler.cancel(); author_compiler.queue_free(); author_compiler = null
	if world_design and ready_for_models: PhysicsServer3D.call("scene_close_authoring", space)
	if command_request != 0: PhysicsServer3D.call("scene_cancel_world_command",command_request)
	command_request = 0
	# Even a failed first entry consumed _ready; recovery must run it again.
	request_ready()
	if not ready_for_models: return
	PhysicsServer3D.call("scene_pause", space, true)
	var world := get_world_3d()
	if world and world.has_meta("mj_runtime_owner"):
		world.remove_meta("mj_runtime_owner")
	ready_for_models = false

func set_paused(value: bool) -> bool:
	if world_design and not value and (views_pending or not author_started): return false
	return ready_for_models and PhysicsServer3D.call("scene_pause", space, value)

func info() -> Dictionary:
	return PhysicsServer3D.call("scene_info", space) if ready_for_models else {"last_error":last_error}

# These APIs enqueue work; model/data mutation occurs only at the native step boundary.
func request_command(command: String, count: int = 1) -> bool:
	if not ready_for_models or command_request != 0 or (command in ["resume","step","reset","capture"] and not author_started):
		last_error = "Wait for the pending simulation command"
		return false
	command_request = PhysicsServer3D.call("scene_request_world_command",space,command,count)
	if command_request == 0:
		last_error = "Simulation command queue is full"
		return false
	last_error = ""
	return true

func request_pause(paused: bool) -> bool:
	return request_command("pause" if paused else "resume")

func step_simulation(count: int = 1) -> bool:
	return request_command("step",count)

func capture_snapshot() -> bool:
	return request_command("capture")

func reset_simulation() -> bool:
	# Retain topology, resources and runtime additions. This does not save design data.
	return request_command("reset")

func _process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	game_elapsed += delta
	if Time.get_ticks_msec() > publish_at:
		publish_at = Time.get_ticks_msec() + 250
		AuthorBridge.publish_instances(self)
	if world_design: poll_author_world()
	if command_request == 0: return
	var result: Dictionary = PhysicsServer3D.call("scene_world_command_result",command_request)
	if result.is_empty(): return
	command_request = 0
	last_error = result.error
	last_command_result = result
	if resume_after_capture and result.get("success", false) and result.get("command") == "capture":
		resume_after_capture = false
		set_paused(false)
	command_finished.emit(result)

func poll_author_world() -> void:
	if not ready_for_models or not author_compiler: return
	var state := info()
	var revision := int(state.get("design_revision", -1))
	if views_pending and not state.get("design_pending", true): commit_author_views()
	if views_pending and state.get("compile_status") == "rendering" and all_author_visuals_ready():
		views_pending = false
		PhysicsServer3D.call("scene_author_views_ready", space)
	if state.get("design_pending", false) and revision != queued_design_revision:
		var snapshot: Dictionary = PhysicsServer3D.call("scene_async_snapshot", space)
		if not snapshot.is_empty():
			queued_design_revision = revision
			if snapshot.has("error"):
				PhysicsServer3D.call("scene_async_error", space, snapshot.error)
			else:
				snapshot.limits = Collision.limits()
				snapshot.generation = str(space.get_id())
				author_compiler.submit(snapshot)
	if state.get("compile_status") == "ready" and command_request==0 and (not author_started or not state.get("has_checkpoint",false)):
		author_started = true
		resume_after_capture = not start_paused and not manual_resume_required
		capture_snapshot()
		world_ready.emit()

func author_world_compiled(result: Dictionary) -> void:
	if not ready_for_models or str(result.get("generation")) != str(space.get_id()): return
	var revision := int(info().get("design_revision", -1))
	if int(result.get("revision", -2)) != revision: return
	if not result.get("success", false):
		last_error = result.get("error", "World compilation failed")
		PhysicsServer3D.call("scene_async_error", space, last_error)
		return
	if not PhysicsServer3D.call("scene_submit_async", space, revision, result): last_error = "Compiled world became obsolete"

func request_editor_design(command: Dictionary) -> int:
	return AuthorBridge.request(self, command)

func cancel_author_compile() -> void:
	if not world_design or not ready_for_models: return
	PhysicsServer3D.call("scene_pause_for_author",space)
	queued_design_revision = int(info().design_revision)
	if author_compiler: author_compiler.cancel()
	last_error = "世界编译已取消；继续编辑或恢复已提交设计。"
	PhysicsServer3D.call("scene_async_error",space,last_error)

func stage_editor_layout(layout: Dictionary) -> void:
	if not editor_connected: return
	manual_resume_required = true
	resume_after_capture = false
	PhysicsServer3D.call("scene_pause_for_author", space)
	if not str(layout.get("world_xml", "")).is_empty():
		if not PhysicsServer3D.call("scene_enable_authoring", space, layout.world_xml):
			last_error = info().get("last_error", "Invalid world options")
			return
	if layout.has("world_author"):
		var updated_world := Author.new()
		var world_error: String = updated_world.restore_author(layout.world_author)
		if not world_error.is_empty(): PhysicsServer3D.call("scene_async_error", space, world_error); return
		world_design = updated_world
	var existing := {}
	for node in Layout.nodes(self):
		if node.has_method("author_definition") and node.design: existing[node.design_instance_id] = node
	var keep := {}
	for value in layout.get("models", []):
		var instance_id: String = value.instance_id
		keep[instance_id] = true
		var design_resource := Author.new()
		var error: String = design_resource.restore_author(value.author)
		if not error.is_empty(): PhysicsServer3D.call("scene_async_error", space, error); return
		design_resource.cache_path = value.get("cache_path", "")
		design_resource.compiled_snapshot = value.get("compiled_snapshot", {}).duplicate(true)
		design_resource.cached_entities = value.get("cached_entities", []).duplicate(true)
		design_resource.cached_geometry = value.get("cached_geometry", []).duplicate(true)
		design_resource.collision_geometry = value.get("collision_geometry", []).duplicate(true)
		design_resource.collision_stats = value.get("collision_stats", []).duplicate(true)
		design_resource.validated_context = value.get("validated_context", "")
		design_resource.validated_revision = design_resource.revision
		var node: Node3D = existing.get(instance_id)
		if not node:
			node = load("res://addons/godot_mujoco/model/model_instance.gd").new()
			node.design = design_resource
			node.design_instance_id = instance_id
			node.name = value.name
			node.author_registration_deferred = true
			node.visible = false
			add_child(node)
			node.space = space
		var definition := {"xml":design_resource.runtime_xml(Collision.world_values(world_design.tree)), "mesh_options":design_resource.native_mesh_options(), "initial":design_resource.native_initial_pose(), "initial_controls":design_resource.native_initial_controls(), "entities":design_resource.entities(), "pose":value.pose, "label":str(node.get_path()), "owner":node.get_instance_id(), "instance_id":instance_id, "revision":design_resource.revision}
		node.model_rid = PhysicsServer3D.call("scene_stage_author_model", space, node.model_rid, definition)
		pending_author_views[instance_id] = {"node":node, "design":design_resource, "pose":value.pose}
	for key in existing:
		if not keep.has(key):
			PhysicsServer3D.call("scene_stage_author_remove", space, existing[key].model_rid)
			existing[key].model_rid = RID()
			retiring_nodes.append(existing[key])
	apply_physical_layout(layout.get("physical", []))
	source_layout = layout.duplicate(true)
	views_pending = true

func commit_author_views() -> void:
	PhysicsServer3D.call("scene_pause_for_author", space, false)
	for value in pending_author_views.values():
		var node: Node = value.node
		if not is_instance_valid(node): continue
		node.design = value.design
		node.global_transform = value.pose
		if node.author_scene: node.author_scene.shutdown()
		node.author_scene = load("res://addons/godot_mujoco/model/author_scene.gd").new()
		node.author_scene.initialize(node, false)
		node.visible = true
	pending_author_views.clear()
	for node in retiring_nodes:
		if is_instance_valid(node): node.queue_free()
	retiring_nodes.clear()

func all_author_visuals_ready() -> bool:
	for node in Layout.nodes(self):
		if node.has_method("author_definition") and node.author_scene and not node.author_scene.geometry_queue.is_empty(): return false
	return pending_author_views.is_empty()

func apply_physical_layout(values: Array) -> void:
	var previous := {}
	for value in source_layout.get("physical", []): previous[value.path] = value
	var keep := {}
	for value in values:
		keep[value.path] = true
		if previous.get(value.path, {}) == value: continue
		var node := get_node_or_null(value.path)
		if not node:
			var parent := get_node_or_null(str(value.path).get_base_dir())
			if not parent: parent = self
			if value.kind == "shape": node = CollisionShape3D.new()
			elif value.kind == "terrain": node = load("res://addons/godot_mujoco/model/static_heightfield.gd").new()
			elif value.kind == "map": node = load("res://addons/godot_mujoco/map/map_root.gd").new()
			elif ClassDB.is_parent_class(value.kind, "CollisionObject3D"): node = ClassDB.instantiate(value.kind)
			if not node: continue
			node.name = str(value.path).get_file()
			parent.add_child(node)
		if value.kind == "shape":
			node.shape = Layout.make_shape(value.shape)
			node.transform = value.pose
			node.disabled = value.disabled
		elif value.kind == "terrain":
			var data: Resource = load("res://addons/godot_mujoco/model/heightfield_data.gd").new()
			data.width = value.design.width; data.depth = value.design.depth; data.heights = value.design.heights.duplicate()
			node.design = data
			node.global_transform = value.pose
			node.collision_layer = value.design.get("layer", 1); node.collision_mask = value.design.get("mask", 1)
			node.set_meta("mujoco_editor_staging",true)
			node.request_apply()
			node.remove_meta("mujoco_editor_staging")
		elif value.kind == "map":
			node.native_collisions = value.collisions
			node.global_transform = value.pose
			node.set_meta("mujoco_editor_staging",true)
			node.load_collisions()
			node.remove_meta("mujoco_editor_staging")
		else:
			if not previous.has(value.path) or previous[value.path].pose != value.pose:
				node.global_transform = value.pose
				if node is RigidBody3D: PhysicsServer3D.call("scene_reset_author_body",space,node.get_rid())
			for key in value.properties:
				if key == "material":
					var material := PhysicsMaterial.new()
					for field in value.properties.material: material.set(field, value.properties.material[field])
					node.physics_material_override = material
				else: node.set(key, value.properties[key])
	for path in previous:
		if keep.has(path): continue
		var node := get_node_or_null(path)
		if node and not retiring_nodes.has(node):
			if node is PhysicsBody3D: PhysicsServer3D.body_set_space(node.get_rid(), RID())
			elif node is Area3D: PhysicsServer3D.area_set_space(node.get_rid(), RID())
			retiring_nodes.append(node)

func _get_property_list() -> Array[Dictionary]:
	var fields: Array[Dictionary] = [{"name":"MJCF 碰撞", "type":TYPE_NIL, "usage":PROPERTY_USAGE_GROUP, "hint_string":"mjcf/collision_"}]
	if not world_design: return []
	for key in Collision.WORLD_DEFAULTS:
		var field := {"name":"mjcf/collision_" + key,"type":TYPE_BOOL if key in ["nativeccd","multiccd"] else TYPE_FLOAT if key == "ccd_tolerance" else TYPE_INT,"usage":PROPERTY_USAGE_EDITOR}
		if key not in ["nativeccd","multiccd"]:
			field.hint = PROPERTY_HINT_RANGE
			field.hint_string = "0,100,0.000001" if key == "ccd_tolerance" else "0,1000,1"
		fields.append(field)
	return fields

func _get(property_name: StringName) -> Variant:
	var key := String(property_name).trim_prefix("mjcf/collision_")
	if world_design and Collision.WORLD_DEFAULTS.has(key): return Collision.world_values(world_design.tree)[key]
	return null

func _set(property_name: StringName, value: Variant) -> bool:
	var key := String(property_name).trim_prefix("mjcf/collision_")
	if not world_design or not Collision.WORLD_DEFAULTS.has(key): return false
	var snapshot: Dictionary = world_design.author_snapshot()
	last_error = Collision.write_world(snapshot.tree,{key:value})
	if not last_error.is_empty(): return false
	snapshot.revision += 1
	restore_world_snapshot(snapshot)
	return true

func restore_world_snapshot(snapshot: Dictionary) -> void:
	last_error = world_design.restore_author(snapshot)
	if not last_error.is_empty(): return
	if Engine.is_editor_hint():
		var plugin: Node = (EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
		if plugin and plugin.author_debugger: plugin.author_debugger.pause_world(self)
		for node in Layout.nodes(self):
			if node.has_method("author_definition") and node.author_scene: node.author_scene.queue_compile()
