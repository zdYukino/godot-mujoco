@tool
class_name MjModelInstance
extends Node3D
const Visual = preload("model_visual.gd")
var model_rid := RID()
@export var model: MjModelResource:
	set(value):
		if model_rid.is_valid():
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

func _ready() -> void:
	if Engine.is_editor_hint():
		show_editor_preview()
		return
	load_model()

func find_world() -> MjRuntimeWorld:
	var parent := get_parent()
	while parent:
		if parent is MjRuntimeWorld: return parent
		parent = parent.get_parent()
	return null

func load_model() -> bool:
	if model_rid.is_valid():
		last_error = "Already loaded; unload at a safe boundary before replacing the model"
		return false
	var world := find_world()
	if not world or not world.ready_for_models or not model:
		last_error = "Model instance needs a configured MjRuntimeWorld ancestor and model resource"
		return false
	last_error = model.validate_package()
	if not last_error.is_empty(): return false
	space = world.space
	var was_paused: bool = world.info().paused
	if not world.set_paused(true):
		last_error = "Loading must occur outside physics callbacks"
		return false
	var label := str(get_path()) + "#" + str(get_instance_id())
	model_rid = PhysicsServer3D.call("scene_load_model",space,model.snapshot,model.resource_path.get_base_dir(),label,global_transform)
	world.set_paused(was_paused)
	if not model_rid.is_valid():
		last_error = world.info().last_error
		return false
	build_visuals(PhysicsServer3D.call("scene_geometry",space,model_rid),true)
	return true

func unload_model() -> void:
	if model_rid.is_valid():
		# Native free defers a transaction if invoked during a physics callback.
		PhysicsServer3D.free_rid(model_rid)
		model_rid = RID()
	clear_visuals()

func _exit_tree() -> void:
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
	return model_rid.is_valid() and PhysicsServer3D.call("scene_set_actuator",space,model_rid,actuator,value)

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
	for geom in state().get("geoms",[]):
		if visuals.has(geom.name):
			visuals[geom.name].global_transform = geom.transform
			visuals[geom.name].scale *= scales[geom.name]
