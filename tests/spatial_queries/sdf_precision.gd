extends "res://query_test_base.gd"
var rows: Array=[]
func probe(state: PhysicsDirectSpaceState3D,q: PhysicsShapeQueryParameters3D,label: String,expected: String,owners: Array):
	var start:=Time.get_ticks_usec()
	var result: PackedFloat32Array=state.cast_motion(q)
	var seconds:=(Time.get_ticks_usec()-start)/1000000.
	var status: Dictionary=state.call("get_query_status")
	var outcome: String="Unknown" if not status.ok else "Clear" if result.size()==2 and result[1]==1 else "Hit" if result.size()==2 else "Invalid"
	var row: Dictionary={"name":label,"seconds":seconds,"result":Array(result),"status":status,"outcome":outcome}
	check(outcome==expected or (expected=="HitOrUnknown" and outcome in ["Hit","Unknown"]),label+" outcome")
	if outcome=="Hit":
		var details: Dictionary=status.details
		var tol: float=state.call("get_sdf_query_precision_m")
		var total: float=details.get("sdf_total_uncertainty_m",INF)
		if tol>0:check(details.get("sdf_precision_met",false) and total<=tol and total<=.001,label+" complete spatial budget")
		check(details.safe_pose_verified and details.unsafe_pose_verified and result[0]<=result[1],label+" internal endpoint certificates")
		var static_query:=PhysicsShapeQueryParameters3D.new()
		static_query.shape=q.shape;static_query.transform=q.transform;static_query.margin=q.margin
		static_query.collision_mask=q.collision_mask;static_query.collide_with_areas=false
		static_query.transform.origin+=q.motion*result[0]
		var safe_hits: Array[Dictionary]=state.intersect_shape(static_query)
		var safe_status: Dictionary=state.call("get_query_status")
		static_query.transform=q.transform;static_query.transform.origin+=q.motion*result[1]
		var rest: Dictionary=state.get_rest_info(static_query)
		var rest_status: Dictionary=state.call("get_query_status")
		row.safe_recheck=safe_status.ok and safe_hits.is_empty()
		row.unsafe_recheck=rest_status.ok and not rest.is_empty() and rest.rid in owners and absf(rest.normal.length()-1)<.00001
		check(row.safe_recheck and row.unsafe_recheck,label+" independent actual-pose/owner/normal rechecks")
	elif outcome=="Unknown":
		check(result.is_empty() and not str(status.error).is_empty(),label+" unknown is observable, never miss")
	rows.append(row)
	return row
func run():
	if "--compare" in OS.get_cmdline_user_args():
		await compare();return
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var map=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();viewport.add_child(map);await ticks(3)
	var space: RID=map.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=map.get_world_3d().direct_space_state
	check(state.call("get_sdf_query_precision_m")==.0005 and state.call("get_sdf_upper_refinement"),"default combined 0.5mm mode")
	for bad in [-1.,.0011,INF,NAN]:
		check(not state.call("set_sdf_query_precision_m",bad) and state.call("get_sdf_query_precision_m")==.0005,"invalid precision preserves setting")
	var before: Dictionary=PhysicsServer3D.call("scene_info",space)
	var states: Array=[]
	for rid in map.native_rids:states.append(PhysicsServer3D.call("scene_state",space,rid))
	var sphere:=SphereShape3D.new();sphere.radius=.04
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=sphere;q.collision_mask=1;q.collide_with_areas=false
	for c in [{"name":"rough_oblique","start":Vector3(2.3,1,-.6),"motion":Vector3(1.2,-2,1.2)},{"name":"stair_edge","start":Vector3(-4,2,0),"motion":Vector3(0,-4,0)},{"name":"stair_oblique","start":Vector3(-5.5,.25,0),"motion":Vector3(4.2,-.35,0)},{"name":"rough_side","start":Vector3(1.5,-.2,.2),"motion":Vector3(3,0,0)},{"name":"pit_multiple_entries","start":Vector3(-1.3,.1,0),"motion":Vector3(2.6,0,0)}]:
		q.transform=Transform3D(Basis.IDENTITY,c.start);q.motion=c.motion
		probe(state,q,c.name,"Hit",map.native_rids)
	var box:=BoxShape3D.new();box.size=Vector3(.4,.4,.4)
	var cylinder:=CylinderShape3D.new();cylinder.radius=.2;cylinder.height=.4
	var capsule:=CapsuleShape3D.new();capsule.radius=.1;capsule.height=.8
	sphere.radius=.2
	for shape in [sphere,box,cylinder,capsule]:
		for margin in [0.,.03]:
			q.shape=shape;q.margin=margin;q.transform=Transform3D(Basis.from_euler(Vector3(.2,.3,.1)),Vector3(0,2,0));q.motion=Vector3(0,-4,0)
			probe(state,q,shape.get_class()+" rotated margin="+str(margin),"Hit",map.native_rids)
	q.shape=sphere;q.margin=0;q.transform=Transform3D(Basis.IDENTITY,Vector3(0,2,0));q.motion=Vector3.ZERO
	probe(state,q,"zero motion clear","Clear",map.native_rids)
	q.transform.origin=Vector3(0,-.25,0);q.motion=Vector3(0,-4,0)
	probe(state,q,"initial overlap public cast exclusion","Clear",map.native_rids)
	q.transform.origin=Vector3(0,2,0);q.collision_mask=0
	probe(state,q,"zero mask","Clear",map.native_rids);q.collision_mask=1
	sphere.radius=.04;q.transform.origin=Vector3(0,1000000,0);q.motion=Vector3(0,-1000000.5,0)
	var large: Dictionary=probe(state,q,"large-coordinate 1.49m legacy bracket is rejected","Unknown",map.native_rids)
	check(str(large.status.error).contains("uncertainty") or str(large.status.error).contains("float"),"large-coordinate error explains failed precision")
	q.transform.origin=Vector3(2.3,1,-.6);q.motion=Vector3(1.2,-2,1.2)
	for tolerance in [.0001,.0005,.001]:
		check(state.call("set_sdf_query_precision_m",tolerance),"precision setting "+str(tolerance))
		probe(state,q,"rough threshold "+str(tolerance),"HitOrUnknown" if tolerance==.0001 else "Hit",map.native_rids)
	state.call("set_sdf_query_precision_m",.0005)
	var unchanged: bool=PhysicsServer3D.call("scene_info",space).time==before.time
	for i in map.native_rids.size():unchanged=unchanged and PhysicsServer3D.call("scene_state",space,map.native_rids[i])==states[i]
	check(unchanged,"all finite-precision queries preserve time and map states")
	viewport.queue_free();await ticks(3)
	print("SDF_PRECISION_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":rows,"scope":"compiled native SDF; source mesh approximation error excluded"}))
	quit(0 if failed==0 else 1)

# Optional reproducible A/B/C benchmark uses this same endpoint checker;
# Unknown baseline rows are reported separately and never treated as misses.
func compare():
	for mode in [{"name":"A_legacy","precision":0.,"refine":false},{"name":"B_1mm","precision":.001,"refine":false},{"name":"C_0.1mm","precision":.0001,"refine":true},{"name":"C_0.5mm","precision":.0005,"refine":true},{"name":"C_1mm","precision":.001,"refine":true}]:
		var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
		var map=load(FileAccess.get_file_as_string("res://map_package_path.txt").path_join("map.tscn")).instantiate();viewport.add_child(map);await ticks(3)
		var space: RID=map.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
		var state: PhysicsDirectSpaceState3D=map.get_world_3d().direct_space_state
		state.call("set_sdf_query_precision_m",mode.precision);state.call("set_sdf_upper_refinement",mode.refine)
		var shape:=SphereShape3D.new();shape.radius=.04
		var q:=PhysicsShapeQueryParameters3D.new();q.shape=shape;q.transform.origin=Vector3(2.3,1,-.6);q.motion=Vector3(1.2,-2,1.2);q.collision_mask=1;q.collide_with_areas=false
		for repeat in 2:
			probe(state,q,mode.name+(" cold" if repeat==0 else " warm"),"Hit" if mode.name in ["C_0.5mm","C_1mm"] else "HitOrUnknown",map.native_rids)
		q.transform.origin+=q.motion*.5;q.motion=Vector3.ZERO
		check(not state.intersect_shape(q).is_empty() and state.call("get_query_status").ok,mode.name+" actual midpath intersection proves Clear would be false")
		viewport.queue_free();await ticks(3)
	print("SDF_PRECISION_COMPARISON_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":rows,"unknown_is_not_miss":true}))
	quit(0 if failed==0 else 1)
