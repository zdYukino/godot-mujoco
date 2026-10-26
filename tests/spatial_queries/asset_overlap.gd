extends "res://query_test_base.gd"
func run() -> void:
	var scene=load("res://Main.tscn").instantiate(); root.add_child(scene)
	for i in 3: await physics_frame; await process_frame
	var space: RID=scene.get_world_3d().space
	PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
	var params:=PhysicsShapeQueryParameters3D.new()
	var sphere:=SphereShape3D.new(); sphere.radius=.12; params.shape=sphere; params.margin=0
	params.transform=Transform3D(Basis.IDENTITY,Vector3(0,-.25,0));params.collision_mask=1;params.collide_with_areas=false
	var excluded: Array[RID]=[]
	for name in ["StairsBall","PitBall","RoughBall"]: excluded.append(scene.get_node(name).get_rid())
	params.exclude=excluded
	var before: Dictionary=PhysicsServer3D.call("scene_info",space)
	var hits: Array[Dictionary]=state.intersect_shape(params)
	check(hits.size()==1 and hits[0].collider==scene and hits[0].rid in scene.native_rids,"sphere versus actual SDF target overlap identity")
	var points: PackedVector3Array=state.collide_shape(params)
	check(points.size()>=2 and absf(points[0].distance_to(params.transform.origin)-.12)<.0001 and absf(points[1].y+.35)<.001,"SDF collide_shape returns query and target surface witnesses")
	var rest: Dictionary=state.get_rest_info(params)
	check(not rest.is_empty() and rest.normal.y>.99 and absf(rest.point.y+.35)<.001,"SDF rest point and outward normal")
	params.transform.origin.y=-.20;params.margin=.04
	var close: Dictionary=state.get_rest_info(params)
	check(not close.is_empty() and absf(close.point.y+.35)<.001,"SDF positive margin counted once with original query witness")
	params.margin=0
	check(state.intersect_shape(params).is_empty() and state.call("get_query_status").ok,"separated sphere above actual SDF is clear with octree interval certificate")
	var plane:=WorldBoundaryShape3D.new();plane.plane=Plane(Vector3.UP,0);params.shape=plane;params.margin=.03
	var first_sequence: int=state.call("get_query_status").sequence
	for repeat in 2:
		check(state.intersect_shape(params).is_empty() and not state.call("get_query_status").ok and str(state.call("get_query_status").error).contains("unbounded plane"),"unsupported overlap is observable on every call, not a successful miss")
	check(state.call("get_query_status").sequence==first_sequence+2,"query status sequence identifies the current request")
	params.shape=sphere;params.collision_mask=0
	check(state.intersect_shape(params).is_empty() and state.call("get_query_status").ok,"valid filtered miss resets previous query error")
	check(PhysicsServer3D.call("scene_info",space).time==before.time,"asset overlap leaves simulation time unchanged")
	print("ASSET_OVERLAP_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"points":points,"rest":rest,"positive_margin":close}))
	scene.free()
	await process_frame
	quit(0 if failed==0 else 1)
