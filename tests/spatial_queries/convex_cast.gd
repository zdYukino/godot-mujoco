extends "res://query_test_base.gd"
func run() -> void:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var wall:=StaticBody3D.new();wall.collision_layer=2;wall.collision_mask=0
	var collider:=CollisionShape3D.new();var thin:=BoxShape3D.new();thin.size=Vector3(.02,6,6);collider.shape=thin;wall.add_child(collider);world.add_child(wall)
	await ticks(3)
	var space: RID=world.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var shapes: Array[Shape3D]=[]
	var sphere:=SphereShape3D.new();sphere.radius=.2;shapes.append(sphere)
	var box:=BoxShape3D.new();box.size=Vector3(.4,.6,.8);shapes.append(box)
	var cylinder:=CylinderShape3D.new();cylinder.radius=.2;cylinder.height=.6;shapes.append(cylinder)
	var capsule:=CapsuleShape3D.new();capsule.radius=.15;capsule.height=3;shapes.append(capsule)
	var cases: Array=[]
	for shape_index in shapes.size():
		for angle in [0.,.4,.75]:
			for margin in [0.,.03]:
				var basis:=Basis.from_euler(Vector3(.2,angle,angle))
				var extent:=.2
				if shape_index==1: extent=absf(basis.x.x)*.2+absf(basis.y.x)*.3+absf(basis.z.x)*.4
				elif shape_index==2: extent=.2*sqrt(maxf(0,1-basis.y.x*basis.y.x))+.3*absf(basis.y.x)
				elif shape_index==3: extent=.15+1.35*absf(basis.y.x)
				var q:=PhysicsShapeQueryParameters3D.new();q.shape=shapes[shape_index];q.transform=Transform3D(basis,Vector3(-5,.3,.4));q.motion=Vector3(10,0,0);q.margin=margin;q.collision_mask=2;q.collide_with_areas=false
				var result: PackedFloat32Array=state.cast_motion(q)
				var expected: float=(5-.01-extent-margin)/10
				var good: bool=result.size()==2 and result[0]<=expected+.000001 and result[1]>=expected-.000001 and result[1]-result[0]<.00001
				check(good,"continuous shape %d angle %.2f margin %.2f oracle %.9f got %s" % [shape_index,angle,margin,expected,result])
				cases.append({"shape":shape_index,"angle":angle,"margin":margin,"expected":expected,"result":Array(result)})
	var fast:=PhysicsShapeQueryParameters3D.new();fast.shape=box;fast.transform.origin=Vector3(-100,0,0);fast.motion=Vector3(1000000,0,0);fast.collision_mask=2;fast.collide_with_areas=false
	check(state.intersect_shape(fast).is_empty(),"thin obstacle start clear")
	var endpoint:=fast.transform;endpoint.origin+=fast.motion;fast.transform=endpoint
	check(state.intersect_shape(fast).is_empty(),"thin obstacle endpoint clear")
	fast.transform.origin=Vector3(-100,0,0)
	var fast_result: PackedFloat32Array=state.cast_motion(fast)
	check(fast_result.size()==2 and fast_result[0]<1 and fast_result[1]>=fast_result[0],"continuous fast box crosses thin obstacle between clear endpoints")
	fast.motion=Vector3.ZERO
	check(state.cast_motion(fast)==PackedFloat32Array([1,1]),"zero motion clear")
	fast.transform.origin=Vector3.ZERO;fast.motion=Vector3(10,0,0)
	check(state.cast_motion(fast)==PackedFloat32Array([1,1]),"initial overlap ignored for public shape cast")
	var area:=Area3D.new();area.position=Vector3(3,0,0);area.collision_layer=4;area.collision_mask=0;area.monitoring=false;area.monitorable=false
	var area_shape:=CollisionShape3D.new();area_shape.shape=thin;area.add_child(area_shape);world.add_child(area);await ticks(2)
	var area_query:=PhysicsShapeQueryParameters3D.new();area_query.shape=box;area_query.transform.origin=Vector3.ZERO;area_query.motion=Vector3(6,0,0);area_query.collision_mask=4;area_query.collide_with_bodies=false;area_query.collide_with_areas=true
	var area_result: PackedFloat32Array=state.cast_motion(area_query)
	check(area_result.size()==2 and absf(area_result[1]-(3-.01-.2)/6)<.00001,"Area continuous sweep with bodies disabled")
	area_query.exclude=[area.get_rid()]
	check(state.cast_motion(area_query)==PackedFloat32Array([1,1]),"Area sweep exclude")
	area.queue_free();await ticks(2)
	area_query.exclude=[]
	check(state.cast_motion(area_query)==PackedFloat32Array([1,1]),"Area sweep lifecycle release")
	var empty:={"format":1,"xml":"<mujoco><option timestep='.002'/><worldbody/></mujoco>","state":{},"source":""}
	check(PhysicsServer3D.call("scene_configure_model",space,empty,""),"configure independent authored query world")
	var snapshot:={"format":1,"xml":"<mujoco><option timestep='.002'/><worldbody><body name='target' pos='3 0 0'><joint name='hinge' type='hinge' axis='0 0 1'/><geom name='ell' type='ellipsoid' size='.4 .7 .5' contype='8' conaffinity='0' mass='1'/></body></worldbody><actuator><motor name='motor' joint='hinge'/></actuator></mujoco>","state":{},"source":""}
	var model_rid: RID=PhysicsServer3D.call("scene_load_model",space,snapshot,"","query_target",Transform3D.IDENTITY)
	check(model_rid.is_valid(),"MJCF ellipsoid query target loads")
	if model_rid.is_valid():
		PhysicsServer3D.call("scene_set_query_owner",space,model_rid,world.get_instance_id(),true)
		PhysicsServer3D.call("scene_set_actuator",space,model_rid,"motor",.3)
		var before: Dictionary=PhysicsServer3D.call("scene_state",space,model_rid)
		var time_before: float=PhysicsServer3D.call("scene_info",space).time
		var q:=PhysicsShapeQueryParameters3D.new();q.shape=box;q.transform.origin=Vector3(-1,0,0);q.motion=Vector3(8,0,0);q.collision_mask=8;q.collide_with_areas=false
		var ellipsoid_result: PackedFloat32Array=state.cast_motion(q)
		check(ellipsoid_result.size()==2 and absf(ellipsoid_result[1]-.425)<.00001,"box versus imported ellipsoid continuous TOI")
		check(PhysicsServer3D.call("scene_state",space,model_rid)==before and PhysicsServer3D.call("scene_info",space).time==time_before,"continuous query preserves MJCF qpos/qvel/control/time")
		PhysicsServer3D.call("scene_release_model",space,model_rid)
	world.queue_free();viewport.queue_free();await ticks(2)
	print("CONVEX_CAST_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":cases,"fast":Array(fast_result),"area":Array(area_result)}))
	quit(0 if failed==0 else 1)
