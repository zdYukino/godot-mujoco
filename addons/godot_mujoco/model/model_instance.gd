@tool
class_name MjModelInstance
extends Node3D
const Visual = preload("model_visual.gd")
const LiveBridge = preload("live_bridge.gd")
const AuthorScene = preload("author_scene.gd")
const AuthorCommands = preload("author_commands.gd")
const Author = preload("author_resource.gd")
@export var design: MjAuthorResource
@export_storage var design_instance_id := ""
var author_scene: RefCounted
var author_registration_deferred := false
signal author_modified
signal edit_finished(result: Dictionary)
var property_revision := 0
var edit_request := 0
var pending_preset:=false
var last_preset_result:Dictionary={}
var pending_model: MjModelResource
var committing_model := false
var live_id := ""

var model_rid := RID()
@export var model: MjModelResource:
	set(value):
		if model_rid.is_valid() and not committing_model:
			last_error = "Active model assignment rejected; unload explicitly before replacing the resource"
			return
		model = value
		if Engine.is_editor_hint() and is_inside_tree() and not preview_pending:
			preview_pending = true
			call_deferred("show_editor_preview")
var preview_pending := false
var space := RID()
var last_error := ""
var visuals := {}
var scales := {}
var spawn_transform := Transform3D.IDENTITY
var physical_root_synced := false

func _ready() -> void:
	if design:
		if design_instance_id.is_empty(): design_instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
		author_scene = AuthorScene.new()
		author_scene.initialize(self)
	if Engine.is_editor_hint():
		if not design: show_editor_preview()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if author_registration_deferred: return
	load_model()

func find_world() -> MjRuntimeWorld:
	var parent := get_parent()
	while parent:
		if parent is MjRuntimeWorld: return parent
		parent = parent.get_parent()
	return null

func trace_model_load(stage: String) -> void:
	if get_meta("mujoco_load_trace",false):
		print("MJ_MODEL_LOAD_STAGE ",JSON.stringify({"stage":stage,"node":str(name),"instance_id":get_instance_id(),"ticks_ms":Time.get_ticks_msec(),"frame":Engine.get_process_frames()}))

func load_model() -> bool:
	trace_model_load("enter")
	if model_rid.is_valid():
		last_error = "Already loaded; unload at a safe boundary before replacing the model"
		return false
	var world := find_world()
	if not world or not world.ready_for_models or (not model and not design):
		last_error = "Model instance needs a configured MjRuntimeWorld ancestor and model resource"
		return false
	if design and not world.world_design:
		last_error = "Upgrade the owning world and its model instances to author nodes before running"
		return false
	if design:
		space = world.space
		spawn_transform = global_transform
		var definition := author_definition()
		model_rid = PhysicsServer3D.call("scene_stage_author_model", space, RID(), definition)
		if not model_rid.is_valid():
			last_error = world.info().last_error
			return false
		live_id = str(get_path()) + "#" + str(get_instance_id()) + ":" + str(model_rid.get_id())
		return true
	trace_model_load("validate_package_begin")
	last_error = model.validate_package()
	trace_model_load("validate_package_end")
	if not last_error.is_empty(): return false
	space = world.space
	var was_paused: bool = world.info().paused
	trace_model_load("pause_begin")
	if not world.set_paused(true):
		last_error = "Loading must occur outside physics callbacks"
		return false
	trace_model_load("pause_end")
	spawn_transform = global_transform
	physical_root_synced = false
	var label := str(get_path()) + "#" + str(get_instance_id())
	trace_model_load("native_scene_load_begin")
	model_rid = PhysicsServer3D.call("scene_load_model",space,model.snapshot,model.resource_path.get_base_dir(),label,global_transform)
	if model_rid.is_valid(): PhysicsServer3D.call("scene_set_query_owner",space,model_rid,get_instance_id(),true)
	trace_model_load("native_scene_load_end")
	world.set_paused(was_paused)
	trace_model_load("restore_pause_end")
	if not model_rid.is_valid():
		last_error = world.info().last_error
		return false
	property_revision = 0
	last_error = ""
	live_id = str(get_path()) + "#" + str(get_instance_id()) + ":" + str(model_rid.get_id())
	LiveBridge.attach(self)
	trace_model_load("visual_geometry_begin")
	var geometry: Array=PhysicsServer3D.call("scene_geometry",space,model_rid)
	trace_model_load("visual_geometry_end")
	build_visuals(geometry,true)
	trace_model_load("visual_nodes_end")
	return true

func restore_spawn_transform() -> void:
	if physical_root_synced and is_inside_tree(): global_transform = spawn_transform
	physical_root_synced = false

func unload_model() -> void:
	restore_spawn_transform()
	cancel_pending_edit()
	LiveBridge.detach(self)
	if model_rid.is_valid():
		if design and find_world() and find_world().world_design:
			PhysicsServer3D.call("scene_stage_author_remove", space, model_rid)
			model_rid = RID()
			return
		# Native free defers a transaction if invoked during a physics callback.
		PhysicsServer3D.free_rid(model_rid)
		model_rid = RID()
	clear_visuals()

func _exit_tree() -> void:
	if author_scene: author_scene.shutdown()
	restore_spawn_transform()
	cancel_pending_edit()
	LiveBridge.detach(self)
	if model_rid.is_valid():
		if design and find_world() and find_world().world_design: PhysicsServer3D.call("scene_stage_author_remove", space, model_rid)
		else: PhysicsServer3D.free_rid(model_rid)
		model_rid = RID()
	for mesh in visuals.values():
		if is_instance_valid(mesh): mesh.queue_free()
	visuals.clear()
	scales.clear()
	request_ready()

func state() -> Dictionary:
	return PhysicsServer3D.call("scene_state",space,model_rid) if model_rid.is_valid() else {}

func set_control(actuator: String, value: float) -> bool:
	return edit_request==0 and model_rid.is_valid() and PhysicsServer3D.call("scene_set_actuator",space,model_rid,actuator,value)

func clear_visuals() -> void:
	if design:
		visuals.clear()
		scales.clear()
		return
	for mesh in visuals.values():
		if is_instance_valid(mesh):
			remove_child(mesh)
			mesh.queue_free()
	visuals.clear()
	scales.clear()

func build_visuals(geometry: Array, world_coordinates: bool) -> void:
	clear_visuals()
	for geom in geometry:
		var instance := Visual.create(geom)
		if not instance: continue
		var scale_value := instance.scale
		add_child(instance)
		if world_coordinates:
			instance.global_transform = geom.transform
			instance.scale *= scale_value
		visuals[geom.name] = instance
		scales[geom.name] = scale_value

func show_editor_preview() -> void:
	preview_pending = false
	if not is_inside_tree(): return
	if design:
		if not author_scene:
			author_scene = AuthorScene.new()
			author_scene.initialize(self)
		return
	clear_visuals()
	if not model: return
	var result: Dictionary = model.open_document()
	last_error = result.error
	if last_error.is_empty(): build_visuals(result.document.geometry(),false)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not model_rid.is_valid(): return
	var physical_state := state()
	if design and author_scene:
		author_scene.update_runtime(physical_state)
		return
	if physical_state.get("joints",{}).has("floating_base") and physical_state.get("bodies",{}).has("pelvis"):
		physical_root_synced = true
		global_transform = physical_state.bodies.pelvis.transform
	for geom in physical_state.get("geoms",[]):
		if visuals.has(geom.name):
			visuals[geom.name].global_transform = geom.transform
			visuals[geom.name].scale *= scales[geom.name]

func request_control_preset(preset:Dictionary,expected_revision:int)->bool:
	if Engine.is_editor_hint() or not model_rid.is_valid() or edit_request!=0 or expected_revision<0:
		last_error="Preset requires a live instance, explicit revision and no pending edit";return false
	edit_request=PhysicsServer3D.call("scene_request_preset",space,model_rid,preset,expected_revision)
	if edit_request==0:last_error="Preset queue rejected";return false
	pending_preset=true;last_error="";last_preset_result={"status":"accepted","request":edit_request}
	LiveBridge.publish(self);return true

func cancel_control_preset()->bool:
	if not pending_preset or edit_request==0:return false
	return PhysicsServer3D.call("scene_cancel_preset",edit_request)

func request_model_edit(candidate: MjModelResource, expected_revision: int = -1) -> bool:
	if Engine.is_editor_hint() or not model_rid.is_valid() or edit_request != 0:
		last_error = "Load an instance and wait for the pending edit before retrying"
		return false
	if not candidate:
		last_error = "Choose a saved model resource"
		return false
	last_error = candidate.validate_package()
	if not last_error.is_empty(): return false
	if expected_revision < 0: expected_revision = property_revision
	last_preset_result={}
	# Copy authored data: future UI/resource changes cannot alter this queued request.
	pending_model = ResourceLoader.load(candidate.resource_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not pending_model:
		last_error = "Save the design resource before requesting runtime application"
		return false
	last_error = pending_model.validate_package()
	if not last_error.is_empty():
		pending_model = null
		return false
	edit_request = PhysicsServer3D.call("scene_request_model_edit",space,model_rid,pending_model.snapshot,pending_model.resource_path.get_base_dir(),expected_revision)
	if edit_request == 0:
		pending_model = null
		last_error = "Edit queue full or this instance already has a pending request"
		return false
	LiveBridge.publish(self)
	return true

func cancel_pending_edit() -> void:
	if edit_request != 0:
		PhysicsServer3D.call("scene_cancel_model_edit",edit_request)
	edit_request = 0
	pending_model = null
	pending_preset=false
	last_preset_result={}

func _process(_delta: float) -> void:
	if author_scene and Engine.is_editor_hint(): author_scene.poll()
	elif author_scene: author_scene.build_geometry_step()
	_poll_edit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and author_scene:
		author_scene.flush_transforms()

func apply_author_command(command: Dictionary, record_history := true) -> Dictionary:
	if not design: return {"error":"Upgrade this model to a node author document first"}
	if not Engine.is_editor_hint():
		return {"error":"Design changes must be requested from the connected editor"}
	var result := AuthorCommands.execute(design, command)
	if not result.get("error", "").is_empty():
		last_error = result.error
		return result
	var plugin: Node = EditorInterface.get_base_control().get_meta("mujoco_author_plugin", null)
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

func upgrade_author_model() -> String:
	if design: return ""
	var result := Author.from_legacy(model)
	if not result.error.is_empty(): return result.error
	clear_visuals()
	design = result.design
	design_instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var world := find_world()
	if Engine.is_editor_hint() and world and not world.world_design:
		var error := world.upgrade_author_world()
		if not error.is_empty(): return error
	if is_inside_tree():
		author_scene = AuthorScene.new()
		author_scene.initialize(self)
	return ""

func author_definition() -> Dictionary:
	return {"xml":design.runtime_xml(), "initial":design.native_initial_pose(), "entities":design.entities(), "pose":global_transform, "label":str(get_path()), "owner":get_instance_id(), "instance_id":design_instance_id, "revision":design.revision}

func _poll_edit() -> void:
	if Engine.is_editor_hint() or edit_request == 0: return
	var result: Dictionary = PhysicsServer3D.call("scene_edit_result",edit_request)
	if result.is_empty(): return
	edit_request = 0
	property_revision = PhysicsServer3D.call("scene_state",space,model_rid).get("property_revision",result.revision)
	last_error = result.error
	if pending_preset:
		last_preset_result=result.duplicate(true)
		last_preset_result.status="completed" if result.success else ("cancelled" if result.get("cancelled",false) else "failed")
	elif result.success:
		committing_model = true
		model = pending_model
		committing_model = false
		build_visuals(PhysicsServer3D.call("scene_geometry",space,model_rid),true)
	pending_model = null
	pending_preset=false
	LiveBridge.publish(self)
	edit_finished.emit(result)

func _validate_property(property: Dictionary) -> void:
	if property.name=="model" and design: property.usage=PROPERTY_USAGE_STORAGE
