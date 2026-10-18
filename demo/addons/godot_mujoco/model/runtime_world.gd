@tool
class_name MjRuntimeWorld
extends Node3D
@export var world_model: MjModelResource
@export var start_paused := false
var space := RID()
var last_error := ""
var ready_for_models := false

func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	if not PhysicsServer3D.has_method("scene_configure_model"):
		last_error = "Select MuJoCo as the project's 3D physics engine and restart"
		push_error(last_error)
		return
	if not world_model:
		last_error = "Assign a world_model resource to define all global MuJoCo options"
		push_error(last_error)
		return
	var world := get_world_3d()
	if world.has_meta("mj_runtime_owner") and is_instance_valid(world.get_meta("mj_runtime_owner").get_ref()):
		last_error = "Only one MjRuntimeWorld may own a World3D; use a separate SubViewport for another world"
		push_error(last_error)
		return
	last_error = world_model.validate_package()
	if not last_error.is_empty(): push_error(last_error); return
	space = world.space
	if not PhysicsServer3D.call("scene_pause", space, true):
		last_error = "Cannot pause world outside physics callbacks"
		return
	if not PhysicsServer3D.call("scene_configure_model", space, world_model.snapshot, world_model.resource_path.get_base_dir()):
		last_error = PhysicsServer3D.call("scene_info", space).last_error
		push_error(last_error)
		return
	world.set_meta("mj_runtime_owner", weakref(self))
	ready_for_models = true

func _ready() -> void:
	if not Engine.is_editor_hint() and ready_for_models:
		set_paused(start_paused)

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	# Even a failed first entry consumed _ready; recovery must run it again.
	request_ready()
	if not ready_for_models: return
	PhysicsServer3D.call("scene_pause", space, true)
	var world := get_world_3d()
	if world and world.has_meta("mj_runtime_owner"):
		world.remove_meta("mj_runtime_owner")
	ready_for_models = false

func set_paused(value: bool) -> bool:
	return ready_for_models and PhysicsServer3D.call("scene_pause", space, value)

func info() -> Dictionary:
	return PhysicsServer3D.call("scene_info", space) if ready_for_models else {"last_error":last_error}
