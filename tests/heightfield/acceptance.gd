extends SceneTree
const Terrain=preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Grid=preload("res://addons/godot_mujoco/model/heightfield_data.gd")
var passed:=0
var failed:=0
func check(ok: bool,label: String):
	if ok: passed+=1;print("PASS ",label)
	else: failed+=1;printerr("FAIL ",label)
func _initialize(): call_deferred("run")
func settle(node: Node,property: String):
	for i in 240:
		await process_frame
		if node.get(property)==0: return
	check(false,"bounded completion "+property)
func step(world: Node,count: int):
	check(world.step_simulation(count),"step queued")
	await settle(world,"command_request")
	check(world.last_command_result.success,"step completed")
func ray(world: Node,x: float,z: float,mask: int=1) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,5,z),Vector3(x,-5,z),mask))
func run():
	var host:=SubViewport.new();host.own_world_3d=true;root.add_child(host)
	var scene=load("res://Environment.tscn")
	var world=scene.instantiate();world.get_node("Floor").free();host.add_child(world)
	await settle(world,"command_request")
	var terrain=Terrain.new();terrain.name="Terrain";terrain.auto_apply=false
	var grid=Grid.new();grid.width=11;grid.depth=11;grid.heights.resize(121);grid.heights.fill(0.3)
	terrain.design=grid;world.add_child(terrain)
	check(terrain.request_apply(),"add queued")
	check(not terrain.request_apply(),"duplicate add rejected")
	check(not terrain.body_rid.is_valid(),"queued is not applied")
	await settle(terrain,"pending_request")
	check(terrain.last_error.is_empty() and terrain.body_rid.is_valid() and terrain.revision==1,"add boundary success")
	var hit=ray(world,0,2)
	check(not hit.is_empty() and hit.collider==terrain and hit.rid==terrain.body_rid and hit.shape==0,"ray terrain identity")
	check(not hit.is_empty() and absf(hit.position.y-.3)<1e-5 and hit.normal.y>.99,"flat height and normal")
	check(ray(world,0,2,2).is_empty(),"ray layer mask")
	var filtered=PhysicsRayQueryParameters3D.create(Vector3(0,5,2),Vector3(0,-5,2))
	filtered.exclude=[terrain.body_rid]
	check(world.get_world_3d().direct_space_state.intersect_ray(filtered).is_empty(),"ray excludes terrain RID")
	filtered.exclude=[];filtered.hit_back_faces=false
	var front=world.get_world_3d().direct_space_state.intersect_ray(filtered)
	check(not front.is_empty() and front.rid==terrain.body_rid,"ray front face accepted with back faces disabled")
	filtered.hit_back_faces=true
	var both=world.get_world_3d().direct_space_state.intersect_ray(filtered)
	check(not both.is_empty() and both.position==front.position,"back face toggle preserves front hit")
	# Start exactly on the flat surface and point outwards: t=0 is a back face,
	# not an inside-origin query (strict interior test excludes the surface).
	var outbound=PhysicsRayQueryParameters3D.create(front.position,front.position+Vector3.UP)
	outbound.hit_back_faces=false
	check(world.get_world_3d().direct_space_state.intersect_ray(outbound).is_empty(),"outward surface back face rejected")
	outbound.hit_back_faces=true
	var back=world.get_world_3d().direct_space_state.intersect_ray(outbound)
	check(not back.is_empty() and back.position.distance_to(front.position)<1e-6,"outward surface back face enabled")
	await step(world,700)
	await process_frame;await process_frame
	check(absf(world.get_node("Box").position.y-.5)<.035,"ordinary box contacts heightfield")
	check(world.get_node("First").state().bodies.arm.transform.origin.y>.36 and world.get_node("First").state().bodies.arm.transform.origin.y<.44,"light slide model contacts heightfield")
	var state=world.get_node("First").state()
	var second_state=world.get_node("Second").state()
	var box_pose=PhysicsServer3D.body_get_state(world.get_node("Box").get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	var time=world.info().time
	var old=terrain.body_rid
	grid.heights[0]=1.2;grid.heights[1]=.4;grid.heights[11]=.6;grid.heights[12]=1.6
	check(terrain.dirty(),"design dirty before explicit apply")
	check(terrain.request_apply(),"replace queued")
	await settle(terrain,"pending_request")
	check(terrain.last_error.is_empty() and terrain.revision==2 and terrain.body_rid==old and not terrain.dirty(),"replace committed same identity")
	check(world.info().time==time and world.info().paused and world.get_node("First").state().joints==state.joints,"paused compatible joint state retained")
	check(world.get_node("Second").state().joints==second_state.joints and PhysicsServer3D.body_get_state(world.get_node("Box").get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)==box_pose,"second instance and ordinary body preserved")
	var inside_query=PhysicsRayQueryParameters3D.create(Vector3(0,0,2),Vector3(0,4,2))
	check(world.get_world_3d().direct_space_state.intersect_ray(inside_query).is_empty(),"ray inside terrain skipped by default")
	inside_query.hit_from_inside=true
	var inside_hit=world.get_world_3d().direct_space_state.intersect_ray(inside_query)
	check(not inside_hit.is_empty() and inside_hit.position==inside_query.from and inside_hit.normal==Vector3.ZERO,"ray inside terrain reports origin when enabled")
	# Compare rays with actual visual triangles, including a non-coplanar cell.
	var mesh=terrain.get_node("HeightfieldVisual").mesh
	var vertices:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in [Vector2(-4.8,-4.8),Vector2(-4.2,-4.8),Vector2(-4.8,-4.2),Vector2(-4.2,-4.2)]:
		var top:Variant=null
		for i in range(0,vertices.size(),3):
			var p=Geometry3D.ray_intersects_triangle(Vector3(point.x,5,point.y),Vector3.DOWN,vertices[i],vertices[i+1],vertices[i+2])
			if p!=null and (top==null or p.y>top.y): top=p
		hit=ray(world,point.x,point.y)
		check(top!=null and not hit.is_empty() and absf(top.y-hit.position.y)<1e-5,"visual collision triangle agreement")
	check(terrain.request_apply(1),"stale request queued")
	await settle(terrain,"pending_request")
	check(not terrain.last_error.is_empty() and terrain.revision==2 and terrain.body_rid==old,"stale revision rejected with old terrain retained")
	grid.heights[0]=NAN
	check(not terrain.request_apply() and terrain.revision==2,"NaN input rejected before queue")
	grid.heights[0]=1.2;grid.width=10
	check(not terrain.request_apply(),"wrong sample count rejected")
	grid.width=11
	terrain.scale=Vector3(2,1,1)
	check(terrain.request_apply(),"invalid pose queued for native validation")
	await settle(terrain,"pending_request")
	check(not terrain.last_error.is_empty() and terrain.revision==2,"invalid pose rollback")
	terrain.scale=Vector3.ONE
	var changed=Grid.new();changed.width=2;changed.depth=2
	terrain.design=changed;check(terrain.request_apply(),"resolution change queued")
	await settle(terrain,"pending_request")
	check(not terrain.last_error.is_empty() and terrain.revision==2,"fixed resolution enforced")
	terrain.design=grid
	# A queued edit uses a snapshot; later UI changes remain dirty.
	check(terrain.request_apply(),"snapshot edit queued")
	grid.heights[0]=1.4
	await settle(terrain,"pending_request")
	check(terrain.revision==3 and terrain.dirty(),"pending design mutation does not change queued data")
	grid.heights[0]=1.2
	terrain.position.y=.2
	check(terrain.request_apply(),"translated terrain queued")
	await settle(terrain,"pending_request")
	hit=ray(world,0,2)
	check(not hit.is_empty() and absf(hit.position.y-.5)<1e-5 and is_equal_approx(terrain.get_node("HeightfieldVisual").global_position.y,.2),"translated visual and collision agree")
	terrain.position.y=0
	terrain.rotation=Vector3(.2,.3,0)
	check(terrain.request_apply(),"rotated terrain queued");await settle(terrain,"pending_request")
	var pose=terrain.global_transform
	hit=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pose*Vector3(0,5,2),pose*Vector3(0,-5,2)))
	check(not hit.is_empty() and hit.position.distance_to(pose*Vector3(0,.3,2))<1e-5 and hit.normal.dot(pose.basis.y)>.999,"rotated terrain ray position and normal")
	terrain.rotation=Vector3.ZERO
	check(terrain.request_apply(),"restore terrain pose queued");await settle(terrain,"pending_request")
	# Save authored data and scene, not live RIDs/revisions.
	check(ResourceSaver.save(grid,"res://terrain.tres")==OK,"design saved")
	var saved=Terrain.new();saved.design=load("res://terrain.tres")
	var packed=PackedScene.new();check(packed.pack(saved)==OK and ResourceSaver.save(packed,"res://terrain.tscn")==OK,"terrain scene saved");saved.free()
	for i in 3:
		check(terrain.request_remove(),"remove queued")
		await settle(terrain,"pending_request")
		check(not terrain.body_rid.is_valid() and ray(world,-4.8,-4.8).is_empty(),"removed collision and visual")
		check(terrain.request_apply(),"readd queued")
		await settle(terrain,"pending_request")
		check(terrain.body_rid.is_valid() and terrain.body_rid!=old and terrain.last_error.is_empty(),"readd fresh identity")
	check(world.get_node("First").state().joints==state.joints,"repeated terrain edits preserve other model state")
	check(world.request_pause(false),"resume queued");await settle(world,"command_request")
	check(terrain.request_apply(),"running replacement queued");await settle(terrain,"pending_request")
	check(not world.info().paused and terrain.last_error.is_empty(),"running state restored after replace")
	check(world.request_pause(true),"pause queued");await settle(world,"command_request")
	terrain.queue_free();await process_frame;await process_frame
	var reopened=load("res://terrain.tscn").instantiate();world.add_child(reopened);await settle(reopened,"pending_request")
	check(reopened.body_rid.is_valid() and reopened.revision==1 and not reopened.dirty(),"saved scene reopens authored terrain")
	var count=world.info().ngeom
	var raw=PhysicsServer3D.call("scene_request_heightfield",world.space,RID(),grid.snapshot(Transform3D(),1,1),get_instance_id(),0)
	await physics_frame;await physics_frame
	check(world.info().ngeom==count+1,"raw add committed before result was polled")
	PhysicsServer3D.call("scene_cancel_heightfield",raw)
	ray(world,0,2) # forces normal lazy rebuild after lifetime cleanup
	check(world.info().ngeom==count,"unobserved successful add cleaned up on cancellation")
	var invalid=grid.snapshot(Transform3D(),1,1);invalid.heights[0]=INF
	raw=PhysicsServer3D.call("scene_request_heightfield",world.space,reopened.body_rid,invalid,reopened.get_instance_id(),reopened.revision)
	var failure:Dictionary={}
	for i in 240:
		await process_frame
		failure=PhysicsServer3D.call("scene_heightfield_result",raw)
		if not failure.is_empty(): break
	check(not failure.is_empty() and not failure.success and world.info().ngeom==count,"native invalid data rejected without geometry change")
	# Queue and immediately delete; no orphan request/body may remain.
	var doomed=Terrain.new();doomed.design=grid;world.add_child(doomed);doomed.queue_free()
	await process_frame;await process_frame
	host.queue_free();await process_frame;await process_frame
	print("HEIGHTFIELD_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(0 if failed==0 else 1)
