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
	var world:=Node3D.new();viewport.add_child(world)
	var terrain:=StaticBody3D.new();terrain.collision_layer=16;terrain.collision_mask=0;world.add_child(terrain)
	var collider:=CollisionShape3D.new();var h:=HeightMapShape3D.new();h.map_width=5;h.map_depth=5
	var heights:=PackedFloat32Array()
	for row in 5:
		for col in 5:heights.append(.5 if row in [0,4] or col in [0,4] else -.5)
	h.map_data=heights;collider.shape=h;terrain.add_child(collider)
	await ticks(3)
	var space: RID=world.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
	var state: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	var shapes: Array[Shape3D]=[]
	var sphere:=SphereShape3D.new();sphere.radius=.1;shapes.append(sphere)
	var box:=BoxShape3D.new();box.size=Vector3(.2,.2,.2);shapes.append(box)
	var cylinder:=CylinderShape3D.new();cylinder.radius=.1;cylinder.height=.3;shapes.append(cylinder)
	var capsule:=CapsuleShape3D.new();capsule.radius=.1;capsule.height=.8;shapes.append(capsule)
	var rows: Array=[]
	for target_rotated in [false,true]:
		terrain.transform=Transform3D(Basis.from_euler(Vector3(.2,.3,.1)),Vector3(4,1,-3)) if target_rotated else Transform3D.IDENTITY
		await ticks(2)
		for index in shapes.size():
			var basis:=Basis.from_euler(Vector3(.2,.4,.3))
			var extent:=.1
			if index==1:extent=.1*(absf(basis.x.y)+absf(basis.y.y)+absf(basis.z.y))
			elif index==2:extent=.1*sqrt(maxf(0,1-basis.y.y*basis.y.y))+.15*absf(basis.y.y)
			elif index==3:extent=.1+.3*absf(basis.y.y)
			for margin in [0.,.03]:
				var q:=PhysicsShapeQueryParameters3D.new();q.shape=shapes[index];q.transform=terrain.transform*Transform3D(basis,Vector3(.2,2,.1));q.motion=terrain.basis*Vector3(0,-4,0);q.margin=margin;q.collision_mask=16;q.collide_with_areas=false
				var cast: PackedFloat32Array=state.cast_motion(q)
				var expected: float=(2+.5-extent-margin)/4
				check(cast.size()==2 and cast[0]<=expected+.000002 and cast[1]>=expected-.000002 and cast[1]-cast[0]<.00001,"hfield continuous shape%d rotated=%s margin%.2f expected%.8f got%s" % [index,target_rotated,margin,expected,cast])
				rows.append({"shape":index,"rotated":target_rotated,"margin":margin,"expected":expected,"cast":Array(cast)})
	var params:=PhysicsShapeQueryParameters3D.new();params.shape=box;params.transform=terrain.transform*Transform3D(Basis.IDENTITY,Vector3(0,2,0));params.motion=terrain.basis*Vector3(0,-10000,0);params.collision_mask=16;params.collide_with_areas=false
	var fast: PackedFloat32Array=state.cast_motion(params)
	check(fast.size()==2 and absf(fast[1]-.00024)<.000001,"high speed hfield sweep crosses clear endpoints")
	params.motion=Vector3.ZERO
	check(state.cast_motion(params)==PackedFloat32Array([1,1]),"zero motion outside hfield")
	params.transform=terrain.transform*Transform3D(Basis.IDENTITY,Vector3(0,-.45,0));params.motion=terrain.basis*Vector3(0,-4,0)
	check(state.cast_motion(params)==PackedFloat32Array([1,1]),"initial overlap ignores whole hfield shape rather than a single prism")
	params.transform=terrain.transform*Transform3D(Basis.IDENTITY,Vector3(0,2,0));params.motion=terrain.basis*Vector3(0,-4,0);params.exclude=[terrain.get_rid()]
	check(state.cast_motion(params)==PackedFloat32Array([1,1]),"hfield exclusion by real body RID")
	params.exclude=[];collider.disabled=true;await ticks(2)
	check(state.cast_motion(params)==PackedFloat32Array([1,1]),"disabled hfield is absent from sweep")
	world.queue_free();viewport.queue_free();await ticks(2)
	print("HFIELD_CAST_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"cases":rows,"fast":Array(fast)}));quit(0 if failed==0 else 1)
