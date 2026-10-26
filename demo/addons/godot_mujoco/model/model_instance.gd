@tool
class_name MjModelInstance
extends Node3D
const Visual = preload("model_visual.gd")
const LiveBridge = preload("live_bridge.gd")
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
	if Engine.is_editor_hint():
		show_editor_preview()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	if not world or not world.ready_for_models or not model:
		last_error = "Model instance needs a configured MjRuntimeWorld ancestor and model resource"
		return false
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
		# Native free defers a transaction if invoked during a physics callback.
		PhysicsServer3D.free_rid(model_rid)
		model_rid = RID()
	clear_visuals()

func _exit_tree() -> void:
	restore_spawn_transform()
	cancel_pending_edit()
	LiveBridge.detach(self)
	if model_rid.is_valid():
		PhysicsServer3D.free_rid(model_rid)
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
	clear_visuals()
	if not model: return
	var result: Dictionary = model.open_document()
	last_error = result.error
	if last_error.is_empty(): build_visuals(result.document.geometry(),false)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not model_rid.is_valid(): return
	var physical_state := state()
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
	_poll_edit()

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
