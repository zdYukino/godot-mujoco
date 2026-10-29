@tool
class_name MjModelInstance
extends Node3D
const AuthorScene = preload("author_scene.gd")
const AuthorCommands = preload("author_commands.gd")
const Author = preload("author_resource.gd")
const Collision = preload("collision_settings.gd")
@export var design: MjAuthorResource
@export_storage var design_instance_id := ""
var author_scene: RefCounted
var author_registration_deferred := false
signal author_modified
signal edit_finished(result: Dictionary)
var property_revision := 0
var edit_request := 0
var pending_preset := false
var last_preset_result: Dictionary = {}
var live_id := ""
var preset_compiler: Node
var native_control_request := 0
static var control_serial := 0
var preset_revision := 0
var preset_cancelled := false
var model_rid := RID()
var space := RID()
var last_error := ""
var visuals := {}
var scales := {}
var spawn_transform := Transform3D.IDENTITY

func _ready() -> void:
	if design:
		if design_instance_id.is_empty(): design_instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
		author_scene = AuthorScene.new()
		author_scene.initialize(self)
		property_revision = 0
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not author_registration_deferred: load_model()

func find_world() -> MjRuntimeWorld:
	var parent := get_parent()
	while parent:
		if parent is MjRuntimeWorld: return parent
		parent = parent.get_parent()
	return null

func compilation_context() -> Dictionary:
	return Collision.context(find_world(),design)

func compilation_signature() -> String:
	return Collision.signature(compilation_context())

func load_model() -> bool:
	if model_rid.is_valid(): last_error = "Model is already registered"; return false
	var world := find_world()
	if not design or not world or not world.world_design or not world.ready_for_models:
		last_error = "Model needs an author design and a configured MjRuntimeWorld ancestor"
		return false
	if not design.resource_path.is_empty():
		last_error = design.validate_dependencies()
		if not last_error.is_empty(): return false
	space = world.space
	spawn_transform = global_transform
	model_rid = PhysicsServer3D.call("scene_stage_author_model",space,RID(),author_definition())
	if not model_rid.is_valid(): last_error = world.info().get("last_error", "Model registration failed"); return false
	live_id = str(get_path()) + "#" + str(model_rid.get_id())
	return true

func unload_model() -> void:
	cancel_pending_edit()
	if model_rid.is_valid():
		PhysicsServer3D.call("scene_stage_author_remove",space,model_rid)
		model_rid = RID()

func _exit_tree() -> void:
	if author_scene: author_scene.shutdown()
	unload_model()
	for mesh in visuals.values():
		if is_instance_valid(mesh): mesh.queue_free()
	visuals.clear(); scales.clear()
	request_ready()

func state() -> Dictionary:
	return PhysicsServer3D.call("scene_state",space,model_rid) if model_rid.is_valid() else {}

func set_control(actuator: String, value: float) -> bool:
	return edit_request==0 and model_rid.is_valid() and PhysicsServer3D.call("scene_set_actuator",space,model_rid,actuator,value)

func show_editor_preview() -> void:
	if design and is_inside_tree() and not author_scene:
		author_scene = AuthorScene.new(); author_scene.initialize(self)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not model_rid.is_valid(): return
	if author_scene: author_scene.update_runtime(state())

func request_control_preset(preset: Dictionary, expected_revision: int) -> bool:
	if Engine.is_editor_hint() or not model_rid.is_valid() or edit_request != 0 or expected_revision < 0:
		last_error = "Preset requires a live instance, explicit revision and no pending edit"; return false
	var world := find_world()
	if not world or world.info().get("compile_status") != "ready":
		last_error = "Wait for the current design to compile"; return false
	control_serial += 1
	edit_request = control_serial
	preset_revision = expected_revision
	pending_preset = true; preset_cancelled = false; last_error = ""
	last_preset_result = {"status":"accepted", "request":edit_request}
	preset_compiler = preload("compile_service.gd").new()
	add_child(preset_compiler, false, Node.INTERNAL_MODE_BACK)
	preset_compiler.completed.connect(preset_prepared)
	preset_compiler.submit({"op":"preset", "author":design.author_snapshot(), "context":compilation_context(), "preset":preset.duplicate(true)})
	return true

func preset_prepared(result: Dictionary) -> void:
	if preset_compiler: preset_compiler.queue_free(); preset_compiler = null
	if edit_request == 0: return
	if not result.get("success", false):
		finish_preset({"success":false, "revision":int(state().get("property_revision", property_revision)), "error":result.get("error", "Preset compilation failed"), "cancelled":preset_cancelled})
		return
	native_control_request = PhysicsServer3D.call("scene_request_control_commit", space, model_rid, {"drives":result.drives, "kinds":result.kinds}, preset_revision)
	if native_control_request == 0: finish_preset({"success":false, "revision":property_revision, "error":"Preset commit queue rejected"})

func cancel_control_preset() -> bool:
	if not pending_preset or edit_request == 0 or preset_cancelled: return false
	if native_control_request != 0:
		preset_cancelled = PhysicsServer3D.call("scene_cancel_control_commit", native_control_request)
	else:
		preset_cancelled = true
		# Finish on the next frame, keeping queued/completed outcomes distinct.
		call_deferred("cancel_preset_worker")
	return preset_cancelled

func cancel_preset_worker() -> void:
	if preset_compiler and pending_preset and preset_cancelled: preset_compiler.cancel()

func cancel_pending_edit() -> void:
	if native_control_request != 0: PhysicsServer3D.call("scene_discard_control_commit", native_control_request)
	native_control_request = 0
	edit_request = 0; pending_preset = false; last_preset_result = {}
	if preset_compiler:
		var service := preset_compiler
		preset_compiler = null
		service.cancel(); service.queue_free()

func _process(_delta: float) -> void:
	if author_scene and Engine.is_editor_hint(): author_scene.poll()
	elif author_scene: author_scene.build_geometry_step()
	_poll_edit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and author_scene:
		author_scene.flush_transforms()

func apply_author_command(command: Dictionary, record_history := true) -> Dictionary:
	if not design: return {"error":"Assign a current author design first"}
	if not Engine.is_editor_hint():
		return {"error":"Design changes must be requested from the connected editor"}
	var result := AuthorCommands.execute(design, command)
	if not result.get("error", "").is_empty():
		last_error = result.error
		return result
	var plugin: Node = (EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
	if result.get("confirmation_required", false):
		if plugin and plugin.has_method("confirm_author_command"): plugin.confirm_author_command(self, command, result)
		return result
	if record_history and plugin and plugin.has_method("record_author_command"):
		plugin.record_author_command(self, command, result)
	else:
		restore_author_snapshot(result.after)
	return result

func restore_author_snapshot(snapshot: Dictionary) -> void:
	if not design: design = Author.new()
	last_error = design.restore_author(snapshot)
	if not last_error.is_empty(): return
	if author_scene:
		author_scene.refresh_nodes()
		author_scene.queue_compile()
	author_modified.emit()

func author_definition() -> Dictionary:
	var context := compilation_context()
	return {"xml":design.runtime_xml(context.collision_options), "mesh_options":design.native_mesh_options(), "initial":design.native_initial_pose(), "initial_controls":design.native_initial_controls(), "entities":design.entities(), "pose":global_transform, "label":str(get_path()), "owner":get_instance_id(), "instance_id":design_instance_id, "revision":design.revision}

func _poll_edit() -> void:
	if Engine.is_editor_hint() or native_control_request == 0: return
	var result: Dictionary = PhysicsServer3D.call("scene_control_result", native_control_request)
	if result.is_empty(): return
	native_control_request = 0
	finish_preset(result)

func finish_preset(result: Dictionary) -> void:
	result.request = edit_request
	edit_request = 0
	property_revision = int(result.revision)
	last_error = result.error
	last_preset_result = result.duplicate(true)
	last_preset_result.status = "completed" if result.success else ("cancelled" if result.get("cancelled", false) else "failed")
	pending_preset = false
	edit_finished.emit(result)
