@tool
class_name MjRuntimeWorld
extends Node3D
@export var world_model: MjModelResource
@export var start_paused := false
var space := RID()
var last_error := ""
var ready_for_models := false
signal command_finished(result: Dictionary)
var command_request := 0
var game_elapsed := 0.0
var last_command_result := {}

func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false):
		last_error = "MjRuntimeWorld currently requires the default main-thread physics mode"
		push_error(last_error)
		return
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
		capture_snapshot()

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
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
	return ready_for_models and PhysicsServer3D.call("scene_pause", space, value)

func info() -> Dictionary:
	return PhysicsServer3D.call("scene_info", space) if ready_for_models else {"last_error":last_error}

# These APIs enqueue work; model/data mutation occurs only at the native step boundary.
func request_command(command: String, count: int = 1) -> bool:
	if not ready_for_models or command_request != 0:
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
	if command_request == 0: return
	var result: Dictionary = PhysicsServer3D.call("scene_world_command_result",command_request)
	if result.is_empty(): return
	command_request = 0
	last_error = result.error
	last_command_result = result
	command_finished.emit(result)
