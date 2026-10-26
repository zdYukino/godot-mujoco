extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int) -> void:
	for i in n:await physics_frame;await process_frame
func run() -> void:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var map=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();viewport.add_child(map);await ticks(3)
	var space: RID=map.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=map.get_world_3d().direct_space_state
	var sphere:=SphereShape3D.new();sphere.radius=.04
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=sphere;q.collision_mask=1;q.collide_with_areas=false
	var cases: Array=[]
	for row in [{"name":"stair_edge","start":Vector3(-4,2,0),"motion":Vector3(0,-4,0)},{"name":"stair_oblique","start":Vector3(-5.5,.25,0),"motion":Vector3(4.2,-.35,0)},{"name":"rough_side","start":Vector3(1.5,-.2,.2),"motion":Vector3(3,0,0)},{"name":"rough_oblique","start":Vector3(2.3,1,-.6),"motion":Vector3(1.2,-2,1.2)},{"name":"pit_multiple_entries","start":Vector3(-1.3,.1,0),"motion":Vector3(2.6,0,0)}]:
		q.transform=Transform3D(Basis.IDENTITY,row.start);q.motion=row.motion
		var result: PackedFloat32Array=state.cast_motion(q);var status: Dictionary=state.call("get_query_status")
		check(status.ok and result.size()==2 and result[1]<1 and result[0]<=result[1],row.name+" continuous sweep")
		if result.size()==2:
			var end:=q.transform;end.origin+=q.motion*result[1]
			var pose:=PhysicsShapeQueryParameters3D.new();pose.shape=sphere;pose.transform=end;pose.collision_mask=1;pose.collide_with_areas=false
			var rest: Dictionary=state.get_rest_info(pose)
			check(not rest.is_empty() and rest.rid in map.native_rids and absf(rest.normal.length()-1)<.00001,row.name+" actual SDF original-surface witness/normal")
		cases.append({"name":row.name,"result":Array(result),"status":status})
		if row.name=="pit_multiple_entries":
			check(result.size()==2 and result[1]<.4,"nonconvex sweep returns first entry")
			for fraction in [.15,.5,.85]:
				var point:=PhysicsShapeQueryParameters3D.new();point.shape=sphere;point.transform.origin=row.start+row.motion*fraction;point.collision_mask=1;point.collide_with_areas=false
				var hits: Array[Dictionary]=state.intersect_shape(point)
				check(state.call("get_query_status").ok and (hits.is_empty() if fraction==.5 else not hits.is_empty()),"actual SDF multiple-entry occupancy %.2f" % fraction)
	for radius in [.02,.08]:
		sphere.radius=radius;q.transform=Transform3D(Basis.IDENTITY,Vector3(0,2,0));q.motion=Vector3(0,-4,0)
		var result: PackedFloat32Array=state.cast_motion(q);var expected: float=(2+.35-radius)/4
		check(result.size()==2 and result[0]<=expected+.000002 and result[1]>=expected-.000002,"shape dimension scale %.3fm" % radius)
	sphere.radius=.04
	q.transform=Transform3D(Basis.IDENTITY,Vector3(0,1000000,0));q.motion=Vector3(0,-1000000.5,0)
	var cancel_result: PackedFloat32Array=state.cast_motion(q);var cancel_status: Dictionary=state.call("get_query_status")
	check(cancel_result.size()==2 and cancel_status.ok,"large start/full-motion cancellation retains geometric error envelope")
	cases.append({"name":"large_motion_cancellation","result":Array(cancel_result),"status":cancel_status})
	q.motion=Vector3(0,-4,0)
	q.transform=Transform3D(Basis.from_scale(Vector3(1.25,1,1)),Vector3(0,2,0))
	check(state.cast_motion(q).is_empty() and not state.call("get_query_status").ok,"nonrigid transform rejects explicitly")
	q.transform=Transform3D(Basis.IDENTITY,Vector3(2097152,2,0));q.motion=Vector3(0,-4,0)
	check(state.cast_motion(q).is_empty() and not state.call("get_query_status").ok and str(state.call("get_query_status").error).contains("domain"),"query coordinate beyond certified domain rejects explicitly")
	q.transform.origin=Vector3(0,2,0);sphere.radius=.000001
	check(state.cast_motion(q).is_empty() and not state.call("get_query_status").ok and str(state.call("get_query_status").error).contains("domain"),"sub-domain query size rejects explicitly")
	sphere.radius=.04
	check(state.cast_motion(q).size()==2 and state.call("get_query_status").ok,"successful query resets certification-domain errors")
	viewport.queue_free();await ticks(3)
	var moved:=SubViewport.new();moved.own_world_3d=true;root.add_child(moved)
	var far=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();far.position.x=2048;moved.add_child(far);await ticks(3)
	PhysicsServer3D.call("scene_pause",far.get_world_3d().space,true)
	q.transform.origin=Vector3(2048,2,0)
	var far_state: PhysicsDirectSpaceState3D=far.get_world_3d().direct_space_state
	check(far_state.cast_motion(q).is_empty() and not far_state.call("get_query_status").ok and str(far_state.call("get_query_status").error).contains("domain"),"target world reference beyond 1024m rejects explicitly")
	moved.queue_free();await ticks(3)
	var offset_world:=SubViewport.new();offset_world.own_world_3d=true;root.add_child(offset_world)
	var offset_map=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();offset_map.position=Vector3(512,256,-128);offset_world.add_child(offset_map);await ticks(3)
	PhysicsServer3D.call("scene_pause",offset_map.get_world_3d().space,true)
	var offset_state: PhysicsDirectSpaceState3D=offset_map.get_world_3d().direct_space_state
	q.transform=Transform3D(Basis.IDENTITY,offset_map.position+Vector3(0,2,0));q.motion=Vector3(0,-4,0)
	var offset_result: PackedFloat32Array=offset_state.cast_motion(q);var offset_status: Dictionary=offset_state.call("get_query_status")
	check(offset_result.size()==2 and offset_status.ok,"certified world offset 512/256/-128 sweep")
	cases.append({"name":"world_offset","result":Array(offset_result),"status":offset_status})
	offset_world.queue_free();await ticks(3)
	print("SDF_TERRAIN_EDGES_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":cases}));quit(0 if failed==0 else 1)
