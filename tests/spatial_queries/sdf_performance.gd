extends SceneTree
var passed:=0
var failed:=0
func _initialize():call_deferred("run")
func run():
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var map=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();viewport.add_child(map)
	for i in 3:await physics_frame;await process_frame
	PhysicsServer3D.call("scene_pause",map.get_world_3d().space,true)
	var state: PhysicsDirectSpaceState3D=map.get_world_3d().direct_space_state
	var q:=PhysicsShapeQueryParameters3D.new();var box:=BoxShape3D.new();box.size=Vector3(.4,.4,.4);q.shape=box;q.transform.origin=Vector3(0,2,0);q.motion=Vector3(0,-4,0);q.margin=.03;q.collide_with_areas=false;q.collision_mask=1
	var runs: Array=[]
	for repeat in 3:
		var started:=Time.get_ticks_usec();var result: PackedFloat32Array=state.cast_motion(q);var seconds:=(Time.get_ticks_usec()-started)/1000000.;var status: Dictionary=state.call("get_query_status")
		if result.size()==2 and status.ok:passed+=1
		else:failed+=1
		runs.append({"phase":"cold" if repeat==0 else "warm","seconds":seconds,"result":Array(result),"status":status})
	viewport.queue_free()
	for i in 3:await physics_frame;await process_frame
	print("SDF_PERFORMANCE_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"runs":runs,"realtime_accepted":false,"note":"Timing evidence only; two-second proof budget excludes cold cache preprocessing."}))
	quit(0 if failed==0 else 1)
