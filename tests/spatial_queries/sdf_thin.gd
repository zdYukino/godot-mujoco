extends SceneTree
var passed:=0
var failed:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var space:=PhysicsServer3D.space_create();PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=PhysicsServer3D.space_get_direct_state(space)
	var empty:={"format":1,"xml":"<mujoco><worldbody/></mujoco>","state":{},"source":""}
	check(PhysicsServer3D.call("scene_configure_model",space,empty,""),"thin SDF isolated world")
	var vertex:="-1 -1 -.0001 1 -1 -.0001 1 1 -.0001 -1 1 -.0001 -1 -1 .0001 1 -1 .0001 1 1 .0001 -1 1 .0001"
	var face:="0 2 1 0 3 2 4 5 6 4 6 7 0 1 5 0 5 4 1 2 6 1 6 5 2 3 7 2 7 6 3 0 4 3 4 7"
	var snapshot:={"format":2,"xml":"<mujoco><asset><mesh name='thin' vertex='%s' face='%s'/></asset><worldbody><geom name='obstacle' type='sdf' mesh='thin' contype='8' conaffinity='0' rgba='1 1 1 0'/></worldbody></mujoco>" % [vertex,face],"state":{},"source":"","mesh_options":{"thin":{"octree_maxdepth":6}}}
	var document:=MjEditorDocument.new();check(document.restore(snapshot),"closed thin volume compiles as native SDF")
	var rid: RID=PhysicsServer3D.call("scene_load_model",space,snapshot,"","thin",Transform3D.IDENTITY)
	check(rid.is_valid(),"actual thin SDF loads")
	var geometry: Array=PhysicsServer3D.call("scene_geometry",space,rid)
	check(geometry.size()==1 and geometry[0].type==8,"thin obstacle actual mjGEOM_SDF type8")
	var sphere:=SphereShape3D.new();sphere.radius=.0001
	var q:=PhysicsShapeQueryParameters3D.new();q.shape=sphere;q.transform.origin=Vector3(0,2,0);q.motion=Vector3(0,-1000000,0);q.collision_mask=8;q.collide_with_areas=false
	check(state.intersect_shape(q).is_empty() and state.call("get_query_status").ok,"thin SDF start clear")
	q.transform.origin+=q.motion
	check(state.intersect_shape(q).is_empty() and state.call("get_query_status").ok,"thin SDF endpoint clear")
	q.transform.origin=Vector3(0,2,0)
	var result: PackedFloat32Array=state.cast_motion(q);var status: Dictionary=state.call("get_query_status")
	check(result.size()==2 and status.ok and absf(result[1]-.0000019998)<.00000000001,"continuous thin SDF crossing between clear endpoints")
	if result.size()==2:
		q.transform.origin=Vector3(0,2,0)+q.motion*result[1];q.margin=0
		var rest: Dictionary=state.get_rest_info(q)
		check(not rest.is_empty() and rest.rid==rid and absf(rest.point.y-.0001)<.000005 and rest.normal.y>.9,"thin SDF unsafe pose has actual original surface witness and normal")
	var boundaries: Array=[]
	for mode in ["touch_inward","touch_away","graze"]:
		q.transform.origin=Vector3(0,.0002,0);q.margin=0
		q.motion=Vector3(0,-.01,0) if mode=="touch_inward" else Vector3(0,.01,0) if mode=="touch_away" else Vector3(.5,0,0)
		var cast: PackedFloat32Array=state.cast_motion(q);var query_status: Dictionary=state.call("get_query_status")
		boundaries.append({"mode":mode,"result":Array(cast),"status":query_status})
		check(query_status.ok or (cast.is_empty() and not str(query_status.error).is_empty()),"SDF boundary returns certified result or explicit unresolved status: "+mode)
	PhysicsServer3D.call("scene_release_model",space,rid);PhysicsServer3D.free_rid(space)
	print("SDF_THIN_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cast":Array(result),"search_status":status,"boundaries":boundaries,"boundary_contract_checks":3,"boundary_unresolved":boundaries.filter(func(b):return not b.status.ok).map(func(b):return b.mode),"positive_checks":passed-3,"inspect":document.inspect()}))
	quit(0 if failed==0 else 1)
