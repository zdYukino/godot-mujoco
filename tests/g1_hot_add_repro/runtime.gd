extends SceneTree
var space: RID
func mark(stage: String, detail: Dictionary={}) -> void:
	print("REPRO_STAGE ",JSON.stringify({"stage":stage,"ms":Time.get_ticks_msec(),"detail":detail}))
func require(ok: bool, message: String) -> bool:
	if not ok:
		mark("FAIL",{"message":message,"info":PhysicsServer3D.call("scene_info",space)})
		PhysicsServer3D.free_rid(space);quit(1)
	return ok
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var hot:=OS.get_cmdline_user_args().has("hot")
	var probes:=OS.get_cmdline_user_args().has("probes")
	mark("begin",{"hot":hot,"probes":probes,"godot":Engine.get_version_info().string,"cpu":OS.get_processor_count()})
	space=PhysicsServer3D.space_create();PhysicsServer3D.space_set_active(space,true)
	PhysicsServer3D.call("scene_pause",space,true)
	var floor_snapshot: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://floor/snapshot.json"))
	var robot: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://g1/snapshot.json"))
	if not require(PhysicsServer3D.call("scene_configure_model",space,floor_snapshot,"res://floor"),"configure"): return
	mark("floor_load_begin")
	var floor_id: RID=PhysicsServer3D.call("scene_load_model",space,floor_snapshot,"res://floor","floor",Transform3D.IDENTITY)
	if not require(floor_id.is_valid(),"floor"): return
	mark("first_load_begin")
	var pose:=Transform3D(Basis(Vector3.BACK,deg_to_rad(-5)),Vector3(-1.8,.82,0))
	var first: RID=PhysicsServer3D.call("scene_load_model",space,robot,"res://g1","first",pose)
	if not require(first.is_valid(),"first"): return
	mark("first_load_end",PhysicsServer3D.call("scene_info",space))
	if hot:
		PhysicsServer3D.call("scene_pause",space,false)
		for i in 360: await physics_frame; await process_frame
		PhysicsServer3D.call("scene_pause",space,true)
	var before: Dictionary=PhysicsServer3D.call("scene_state",space,first)
	var time_before: float=PhysicsServer3D.call("scene_info",space).time
	if not require(not hot or time_before>=5.9,"hot branch actually advances native time"): return
	if probes:
		mark("failure_probes.begin")
		var bad: Dictionary=floor_snapshot.duplicate(true)
		bad.xml=bad.xml.replace("<option ","<option gravity='0 0 -1' ")
		var rejected: RID=PhysicsServer3D.call("scene_load_model",space,bad,"res://floor","conflicting_floor",Transform3D.IDENTITY)
		if not require(not rejected.is_valid() and str(PhysicsServer3D.call("scene_info",space).last_error).contains("conflict"),"option conflict probe"): return
		var invalid_pose:=Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO)
		rejected=PhysicsServer3D.call("scene_load_model",space,floor_snapshot,"res://floor","invalid_pose",invalid_pose)
		if not require(not rejected.is_valid() and str(PhysicsServer3D.call("scene_info",space).last_error).contains("rigid pose"),"post-transfer probe"): return
		if not require(PhysicsServer3D.call("scene_state",space,first).joints==before.joints and PhysicsServer3D.call("scene_info",space).time==time_before,"failure probes preserve state/time"): return
		mark("failure_probes.end")
	mark("second_load_begin",{"time":time_before,"first_id":first.get_id()})
	pose=Transform3D(Basis(Vector3.BACK,deg_to_rad(-5)),Vector3(1.8,.82,0))
	var second: RID=PhysicsServer3D.call("scene_load_model",space,robot,"res://g1","second",pose)
	mark("second_load_end")
	if not require(second.is_valid(),"second"): return
	var after: Dictionary=PhysicsServer3D.call("scene_state",space,first)
	var info: Dictionary=PhysicsServer3D.call("scene_info",space)
	if not require(after.joints==before.joints and info.time==time_before and info.objects.size()==3 and info.ngeom==139 and info.nu==0,"state/time/count preservation"): return
	mark("PASS",{"time":info.time,"ngeom":info.ngeom,"first_id":first.get_id(),"second_id":second.get_id()})
	PhysicsServer3D.free_rid(space);quit(0)
