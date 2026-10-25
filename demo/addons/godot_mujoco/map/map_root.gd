@tool
extends Node3D
## Standalone maps establish the same explicit authored world needed by terrain Apply.
## When inserted under an existing MjRuntimeWorld, its options remain authoritative.
var owns_world := false
var last_error := ""
func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	if not PhysicsServer3D.has_method("scene_configure_model"):
		last_error = "地图需要 MuJoCo 物理后端"; push_error(last_error); return
	var world := get_world_3d()
	if world.has_meta("mj_runtime_owner") and is_instance_valid(world.get_meta("mj_runtime_owner").get_ref()): return
	var space := world.space
	var info: Dictionary = PhysicsServer3D.call("scene_info",space)
	var paused: bool = info.get("paused",false)
	if not PhysicsServer3D.call("scene_pause",space,true): last_error = "地图初始化必须在物理回调外"; push_error(last_error); return
	var snapshot := {"format":1,"xml":"<mujoco><compiler angle='radian'/><option timestep='0.002'/><worldbody/></mujoco>","state":{},"source":""}
	if not PhysicsServer3D.call("scene_configure_model",space,snapshot,""):
		last_error = PhysicsServer3D.call("scene_info",space).last_error
	else:
		world.set_meta("mj_runtime_owner",weakref(self)); owns_world = true
	PhysicsServer3D.call("scene_pause",space,paused)
	if not last_error.is_empty(): push_error(last_error)
func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	if owns_world:
		var world := get_world_3d()
		if world and world.has_meta("mj_runtime_owner") and world.get_meta("mj_runtime_owner").get_ref() == self: world.remove_meta("mj_runtime_owner")
	owns_world = false
