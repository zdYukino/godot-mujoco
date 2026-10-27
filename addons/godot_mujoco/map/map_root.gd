@tool
extends Node3D
## Standalone maps establish the same explicit authored world needed by terrain Apply.
## When inserted under an existing MjRuntimeWorld, its options remain authoritative.
@export var native_collisions: Array[Dictionary] = []
@export var world_settings: Dictionary = {}
var native_rids: Array[RID] = []
var owns_world := false
var last_error := ""
func _enter_tree() -> void:
	if Engine.is_editor_hint(): return
	if not PhysicsServer3D.has_method("scene_configure_model"):
		last_error = "地图需要 MuJoCo 物理后端"; push_error(last_error); return
	var world := get_world_3d()
	if world.has_meta("mj_runtime_owner") and is_instance_valid(world.get_meta("mj_runtime_owner").get_ref()):
		load_collisions(); return
	var space := world.space
	var info: Dictionary = PhysicsServer3D.call("scene_info",space)
	var paused: bool = info.get("paused",false)
	if not PhysicsServer3D.call("scene_pause",space,true): last_error = "地图初始化必须在物理回调外"; push_error(last_error); return
	var options := preload("native_collision.gd").options(world_settings)
	if not options.error.is_empty():
		last_error = options.error; PhysicsServer3D.call("scene_pause",space,paused); push_error(last_error); return
	var snapshot := {"format":1,"xml":"<mujoco><compiler angle='radian'/>"+options.xml+"<worldbody/></mujoco>","state":{},"source":""}
	if not PhysicsServer3D.call("scene_configure_model",space,snapshot,""):
		last_error = PhysicsServer3D.call("scene_info",space).last_error
	else:
		world.set_meta("mj_runtime_owner",weakref(self)); owns_world = true
		load_collisions()
	PhysicsServer3D.call("scene_pause",space,paused)
	if not last_error.is_empty(): push_error(last_error)
func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	for id in native_rids: PhysicsServer3D.free_rid(id)
	native_rids.clear()
	if owns_world:
		var world := get_world_3d()
		if world and world.has_meta("mj_runtime_owner") and world.get_meta("mj_runtime_owner").get_ref() == self: world.remove_meta("mj_runtime_owner")
	owns_world = false

func load_collisions() -> void:
	var space := get_world_3d().space
	var paused: bool = PhysicsServer3D.call("scene_info",space).get("paused",false)
	if not PhysicsServer3D.call("scene_pause",space,true): last_error = "无法暂停以装载地图"; return
	for entry in native_collisions:
		var id: RID = PhysicsServer3D.call("scene_load_model",space,entry.snapshot,"",str(get_instance_id())+"_map_"+str(native_rids.size()),global_transform*entry.pose)
		if not id.is_valid():
			last_error = PhysicsServer3D.call("scene_info",space).last_error
			for old in native_rids: PhysicsServer3D.free_rid(old)
			native_rids.clear(); break
		native_rids.append(id)
		PhysicsServer3D.call("scene_set_query_owner",space,id,get_instance_id(),true)
	PhysicsServer3D.call("scene_pause",space,paused)
	if not last_error.is_empty(): push_error(last_error)
