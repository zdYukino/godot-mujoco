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
	var cases: Array=[];var fast_results: Array=[]
	for transformed in [false,true]:
		var target_pose:=Transform3D(Basis.from_euler(Vector3(.2,.3,.1)),Vector3(4,1,-3)) if transformed else Transform3D.IDENTITY
		var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
		var package_path:=FileAccess.get_file_as_string("res://map_package_path.txt")
		var map=load(package_path.path_join("map.tscn")).instantiate()
		map.transform=target_pose;viewport.add_child(map);await ticks(3)
		var space: RID=map.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
		var state: PhysicsDirectSpaceState3D=map.get_world_3d().direct_space_state
		var shapes: Array[Shape3D]=[]
		var sphere:=SphereShape3D.new();sphere.radius=.2;shapes.append(sphere)
		var box:=BoxShape3D.new();box.size=Vector3(.4,.4,.4);shapes.append(box)
		var cylinder:=CylinderShape3D.new();cylinder.radius=.2;cylinder.height=.4;shapes.append(cylinder)
		var capsule:=CapsuleShape3D.new();capsule.radius=.1;capsule.height=.8;shapes.append(capsule)
	
		var before: Dictionary=PhysicsServer3D.call("scene_info",space)
		var before_states: Array=[]
		for rid in map.native_rids:before_states.append(PhysicsServer3D.call("scene_state",space,rid))
		for index in shapes.size():
			for rotated in [false,true]:
				var basis:=Basis.from_euler(Vector3(.2,.3,.1)) if rotated else Basis.IDENTITY
				var extent:=.2
				if index==1:extent=.2*(absf(basis.x.y)+absf(basis.y.y)+absf(basis.z.y))
				elif index==2:extent=.2*sqrt(maxf(0,1-basis.y.y*basis.y.y))+.2*absf(basis.y.y)
				elif index==3:extent=.1+.3*absf(basis.y.y)
				for margin in [0.,.03]:
					var q:=PhysicsShapeQueryParameters3D.new();q.shape=shapes[index];q.transform=target_pose*Transform3D(basis,Vector3(0,2,0));q.motion=target_pose.basis*Vector3(0,-4,0);q.margin=margin;q.collision_mask=1;q.collide_with_areas=false
					var started_usec:=Time.get_ticks_usec()
					var result: PackedFloat32Array=state.cast_motion(q);var elapsed_seconds:=(Time.get_ticks_usec()-started_usec)/1000000.;var status: Dictionary=state.call("get_query_status")
					var expected: float=(2+.35-extent-margin)/4
					var good: bool=status.ok and result.size()==2 and result[0]<=expected+.000002 and result[1]>=expected-.000002 and result[1]-result[0]<.00001
					check(good,"SDF continuous shape%d rotated=%s margin%.2f expected%.9f got%s status%s" % [index,rotated,margin,expected,result,status])
					cases.append({"seconds":elapsed_seconds,"target_transformed":transformed,"shape":index,"rotated":rotated,"margin":margin,"expected":expected,"result":Array(result),"status":status})
		var q:=PhysicsShapeQueryParameters3D.new();q.shape=sphere;q.transform=target_pose*Transform3D(Basis.IDENTITY,Vector3(0,2,0));q.motion=target_pose.basis*Vector3(0,-1000000,0);q.collision_mask=1;q.collide_with_areas=false
		check(state.intersect_shape(q).is_empty() and state.call("get_query_status").ok,"SDF fast sweep starts clear")
		q.transform.origin+=q.motion
		check(state.intersect_shape(q).is_empty() and state.call("get_query_status").ok,"SDF fast sweep endpoint is clear")
		q.transform=target_pose*Transform3D(Basis.IDENTITY,Vector3(0,2,0))
		var fast: PackedFloat32Array=state.cast_motion(q);fast_results.append(Array(fast))
		check(fast.size()==2 and absf(fast[1]-.00000215)<.0000001,"SDF continuous high-speed crossing with both endpoints clear")
		q.motion=Vector3.ZERO
		check(state.cast_motion(q)==PackedFloat32Array([1,1]),"SDF zero motion starts clear")
		q.transform=target_pose*Transform3D(Basis.IDENTITY,Vector3(0,-.25,0));q.motion=target_pose.basis*Vector3(0,-4,0)
		check(state.cast_motion(q)==PackedFloat32Array([1,1]),"SDF initial overlap ignored by public cast")
		check(PhysicsServer3D.call("scene_info",space).time==before.time,"SDF casts preserve simulation time")
		var same:=true
		for i in map.native_rids.size():same=same and PhysicsServer3D.call("scene_state",space,map.native_rids[i])==before_states[i]
		check(same,"SDF casts preserve every original map state")
		q.transform=target_pose*Transform3D(Basis.IDENTITY,Vector3(0,2,0));q.motion=target_pose.basis*Vector3(0,-4,0);q.collision_mask=0
		check(state.cast_motion(q)==PackedFloat32Array([1,1]) and state.call("get_query_status").ok,"SDF sweep zero mask filters all targets")
		q.collision_mask=1
		var ray:=PhysicsRayQueryParameters3D.create(target_pose*Vector3(0,2,0),target_pose*Vector3(0,-1,0),1);ray.collide_with_areas=false
		var target_hit: Dictionary=state.intersect_ray(ray)
		if not target_hit.is_empty():q.exclude=[target_hit.rid]
		check(not target_hit.is_empty() and state.cast_motion(q)==PackedFloat32Array([1,1]),"SDF continuous sweep excludes actual imported RID")
		viewport.queue_free();await ticks(3)
	print("SDF_CAST_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":cases,"fast":fast_results}));quit(0 if failed==0 else 1)
