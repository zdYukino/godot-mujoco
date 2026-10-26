extends SceneTree
var rows: Array=[]
var failed:=0
var unknown:=0
var certified:=0
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	for i in 3:await physics_frame;await process_frame
	var space: RID=world.get_world_3d().space
	PhysicsServer3D.call("scene_pause",space,true)
	var empty:={"format":1,"xml":"<mujoco><option timestep='.002'/><worldbody/></mujoco>","state":{},"source":""}
	if not PhysicsServer3D.call("scene_configure_model",space,empty,""):quit(2);return
	var state: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var vertices:="-1 -1 -.4 1 -1 -.4 1 1 -.4 -1 1 -.4 -1 -1 .4 1 -1 .4 1 1 .4 -1 1 .4"
	var faces:="0 2 1 0 3 2 4 5 6 4 6 7 0 1 5 0 5 4 1 2 6 1 6 5 2 3 7 2 7 6 3 0 4 3 4 7"
	var shapes: Array[Shape3D]=[]
	var sphere:=SphereShape3D.new();sphere.radius=.2;shapes.append(sphere)
	var box:=BoxShape3D.new();box.size=Vector3(.4,.4,.4);shapes.append(box)
	var cylinder:=CylinderShape3D.new();cylinder.radius=.2;cylinder.height=.4;shapes.append(cylinder)
	var capsule:=CapsuleShape3D.new();capsule.radius=.15;capsule.height=.8;shapes.append(capsule)
	for transformed in [false,true]:
		var target_pose:=Transform3D(Basis.from_euler(Vector3(.2,.3,.1)),Vector3(4,1,-3)) if transformed else Transform3D.IDENTITY
		for target in ["ellipsoid","mesh","hfield","sdf"]:
			var asset:=""
			var geom:="type='ellipsoid' size='1 1 .4'"
			if target in ["mesh","sdf"]:
				asset="<asset><mesh name='target_mesh' vertex='%s' face='%s'/></asset>" % [vertices,faces]
				geom="type='%s' mesh='target_mesh'" % target
			elif target=="hfield":
				asset="<asset><hfield name='height' nrow='3' ncol='3' size='2 2 1 1' elevation='0 0 0 0 0 0 0 0 0'/></asset>"
				geom="type='hfield' hfield='height' pos='0 0 .4'"
			var snapshot:={"format":1,"xml":"<mujoco><option timestep='.002'/>"+asset+"<worldbody><geom name='target' "+geom+" contype='32' conaffinity='0'/></worldbody></mujoco>","state":{},"source":""}
			var rid: RID=PhysicsServer3D.call("scene_load_model",space,snapshot,"","pair_"+target,target_pose)
			if not rid.is_valid():failed+=1;continue
			PhysicsServer3D.call("scene_set_query_owner",space,rid,world.get_instance_id(),true)
			for index in shapes.size():
				var half:=.4 if index==3 else .2
				for mode in ["overlap","margin","clear","contained"]:
					var q:=PhysicsShapeQueryParameters3D.new();q.shape=shapes[index];q.collide_with_areas=false;q.collision_mask=32;q.margin=.04 if mode=="margin" else 0
					var height: float=(-.1 if target=="hfield" else 0.) if mode=="contained" else .4+half+(-.05 if mode=="overlap" else .02 if mode=="margin" else .1)
					q.transform=target_pose*Transform3D(Basis.IDENTITY,Vector3(0,height,0))
					var hits: Array[Dictionary]=state.intersect_shape(q);var hs: Dictionary=state.call("get_query_status")
					var points: PackedVector3Array=state.collide_shape(q);var ps: Dictionary=state.call("get_query_status")
					var rest: Dictionary=state.get_rest_info(q);var rs: Dictionary=state.call("get_query_status")
					var known: bool=hs.ok and ps.ok and rs.ok
					var good: bool=(hits.is_empty() and points.is_empty() and rest.is_empty()) if mode=="clear" else (hits.size()==1 and hits[0].rid==rid and points.size()>=2 and not rest.is_empty() and rest.rid==rid and (absf(rest.normal.length()-1)<.00001 if mode=="contained" else rest.normal.dot(target_pose.basis*Vector3.UP)>.5))
					if not known:unknown+=1
					elif good:certified+=1
					else:failed+=1
					var row:={"transformed":transformed,"target":target,"shape":index,"mode":mode,"known":known,"correct":good,"statuses":[hs,ps,rs],"points":points,"rest":rest}
					rows.append(row);print("ASSET_PAIR_CASE ",JSON.stringify(row))
			PhysicsServer3D.call("scene_release_model",space,rid)
	world.queue_free();viewport.queue_free()
	for i in 3:await physics_frame;await process_frame
	print("ASSET_PAIR_MATRIX_RESULT ",JSON.stringify({"failed":failed,"certified":certified,"unknown":unknown,"cases":rows.size()}))
	quit(0 if failed==0 and ("audit" in OS.get_cmdline_user_args() or unknown==0) else 1)
