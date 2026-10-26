extends "res://query_test_base.gd"
func run() -> void:
	var viewport:=SubViewport.new(); viewport.own_world_3d=true; root.add_child(viewport)
	var world:=Node3D.new(); viewport.add_child(world)
	var area:=Area3D.new(); area.collision_layer=2; area.collision_mask=0; area.monitoring=false; area.monitorable=false
	world.add_child(area)
	var shapes: Array[Shape3D]=[]
	var sphere:=SphereShape3D.new(); sphere.radius=1;shapes.append(sphere)
	var box:=BoxShape3D.new(); box.size=Vector3(2,2,2);shapes.append(box)
	var cylinder:=CylinderShape3D.new();cylinder.radius=1;cylinder.height=2;shapes.append(cylinder)
	var capsule:=CapsuleShape3D.new();capsule.radius=.5;capsule.height=2;shapes.append(capsule)
	var collisions: Array[CollisionShape3D]=[]
	for i in shapes.size():
		var node:=CollisionShape3D.new();node.shape=shapes[i];node.position=Vector3(i*3,0,0);node.rotation_degrees=Vector3(7,15,4);area.add_child(node);collisions.append(node)
	await ticks(3)
	var state: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var space: RID=world.get_world_3d().space
	PhysicsServer3D.call("scene_pause",space,true)
	var time_before: float=PhysicsServer3D.call("scene_info",space).time
	for i in shapes.size():
		var center: Vector3=collisions[i].global_position
		var ray:=PhysicsRayQueryParameters3D.create(center+Vector3.UP*4,center-Vector3.UP*4,2);ray.collide_with_bodies=false;ray.collide_with_areas=true
		var hit: Dictionary=state.intersect_ray(ray)
		check(not hit.is_empty() and hit.rid==area.get_rid() and hit.collider==area and hit.shape==i,"Area ray identity "+str(i))
		var point:=PhysicsPointQueryParameters3D.new();point.position=center;point.collision_mask=2;point.collide_with_bodies=false;point.collide_with_areas=true
		var points: Array[Dictionary]=state.intersect_point(point)
		check(points.size()==1 and points[0].rid==area.get_rid() and points[0].shape==i,"Area solid point "+str(i))
		var query:=PhysicsShapeQueryParameters3D.new();var probe:=SphereShape3D.new();probe.radius=.2;query.shape=probe;query.transform.origin=center+Vector3(0,.8,0);query.collision_mask=2;query.collide_with_bodies=false;query.collide_with_areas=true
		var overlaps: Array[Dictionary]=state.intersect_shape(query)
		check(overlaps.size()==1 and overlaps[0].collider==area and overlaps[0].shape==i,"Area shape overlap "+str(i))
		var contacts: PackedVector3Array=state.collide_shape(query)
		check(contacts.size()>=2 and absf(contacts[0].distance_to(query.transform.origin)-.2)<.0001,"Area query surface witness "+str(i))
		var rest: Dictionary=state.get_rest_info(query)
		check(not rest.is_empty() and rest.collider_id==area.get_instance_id() and rest.linear_velocity==Vector3.ZERO,"Area rest identity/static velocity "+str(i))
		ray.exclude=[area.get_rid()]
		check(state.intersect_ray(ray).is_empty(),"Area RID exclude "+str(i))
		query.exclude=[area.get_rid()]
		check(state.intersect_shape(query).is_empty(),"Area overlap exclude "+str(i))
		ray.exclude=[];ray.collide_with_areas=false
		check(state.intersect_ray(ray).is_empty(),"bodies=false and areas=false clear "+str(i))
		collisions[i].disabled=true;await ticks(1)
		ray.collide_with_areas=true
		check(state.intersect_ray(ray).is_empty(),"disabled Area shape filtered "+str(i))
		collisions[i].disabled=false;await ticks(1)
	check(PhysicsServer3D.call("scene_info",space).time==time_before,"Area queries and property changes do not integrate world")
	area.collision_layer=8;await ticks(1)
	var mismatch:=PhysicsPointQueryParameters3D.new();mismatch.position=Vector3.ZERO;mismatch.collision_mask=2;mismatch.collide_with_bodies=false;mismatch.collide_with_areas=true
	check(state.intersect_point(mismatch).is_empty(),"query mask matches Area layer, not Area mask")
	area.queue_free();await ticks(2)
	mismatch.collision_mask=8
	check(state.intersect_point(mismatch).is_empty(),"freed Area leaves no query owner")
	world.queue_free();viewport.queue_free();await ticks(2)
	print("AREA_QUERY_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(0 if failed==0 else 1)
