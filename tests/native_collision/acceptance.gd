extends SceneTree
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var passed := 0
var failed := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int):
	for i in n: await physics_frame; await process_frame
func ball(scene: Node3D, point: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new(); body.position = point; body.gravity_scale = 0; body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE; body.linear_damp = 0
	var shape := CollisionShape3D.new(); shape.shape = SphereShape3D.new(); shape.shape.radius = .2; body.add_child(shape); scene.add_child(body); return body
func run():
	var session := Session.new()
	check(session.import_file("res://fixtures/room.obj","m","Y_UP"),"room import")
	var path := str(session.visual.get_path_to(session.meshes()[0]))
	check(session.configure(path,{"kind":"sdf","friction":.6}),"SDF adapter "+session.error)
	if not session.specs.has(path): session.close(); quit(1); return
	check(session.specs[path].capability.actual_mode=="sdf","requested actual truthful")
	var visual_mesh: MeshInstance3D = session.meshes()[0]
	var original_mesh := visual_mesh.mesh
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	var open_faces := original_mesh.get_faces(); open_faces.resize(open_faces.size()-3); arrays[Mesh.ARRAY_VERTEX]=open_faces
	var open_mesh := ArrayMesh.new(); open_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); visual_mesh.mesh=open_mesh
	var valid_spec := session.specs.duplicate(true)
	check(not session.configure(path,{"kind":"sdf"}) and session.specs==valid_spec and session.last_collision_attempt.actual_mode=="disabled","open mesh rejected without fallback")
	visual_mesh.mesh=original_mesh
	var original_transform := visual_mesh.transform; visual_mesh.transform.basis.x.y=.3
	check(not session.configure(path,{"kind":"sdf"}) and session.specs==valid_spec,"shear atomic rejection")
	visual_mesh.transform=original_transform

	var before := session.specs.duplicate(true)
	check(not session.configure(path,{"kind":"sdf","layer":4294967295}) and session.specs==before,"uint32 truncation rejected atomically")
	session.history.undo(); check(session.specs.is_empty(),"Undo")
	session.history.redo(); check(session.specs==before,"Redo")
	check(session.configure_world({"solver":"CG","cone":"elliptic","nativeccd":false,"multiccd":false}),"global options")
	check(not session.configure_world({"solver":"bad"}) and session.world_settings.solver=="CG","invalid world rollback")
	session.history.undo(); check(session.world_settings.is_empty(),"world Undo preserves native defaults")
	for mode in ["sdf","mesh"]:
		check(session.configure(path,{"kind":mode,"friction":.6}),"configure "+mode)
		var built := session.build_scene(); check(built.error.is_empty(),"scene "+mode)
		if not built.error.is_empty(): continue
		var scene: Node3D = built.scene; root.add_child(scene); await ticks(3)
		check(scene.native_rids.size()==1 and scene.last_error.is_empty(),"runtime attached "+mode+" "+scene.last_error)
		var through := ball(scene,Vector3(0,1,-4)); through.linear_velocity = Vector3(0,0,2)
		var blocked := ball(scene,Vector3(2,1,-4)); blocked.linear_velocity = Vector3(0,0,2)
		var contacts := 0
		var target_force := false
		var normal_ok := false
		for i in 95:
			await ticks(1)
			var info: Dictionary = PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
			contacts=maxi(contacts,info.ncon)
			for contact in info.contact_details:
				if contact.geoms.any(func(n): return str(n).ends_with("_collision")) and absf(contact.position.x-2)<.6:
					target_force = target_force or contact.force_contact_frame[0]>0
					normal_ok = normal_ok or absf(contact.normal.z)>.8
		check(through.position.z > -2 if mode=="sdf" else through.position.z < -3.2,"door discrimination "+mode+" "+str(through.position))
		check(target_force and normal_ok,"target wall contact normal/positive force "+mode)
		check(blocked.position.z < -3.2 and contacts>0,"wall actual contact "+mode+" "+str(blocked.position))
		scene.queue_free(); await ticks(3)
	for solver in ["Newton","CG","PGS"]:
		check(session.configure_world({"solver":solver,"nativeccd":false,"multiccd":false}),"solver configure "+solver)
		var built := session.build_scene(); var scene: Node3D=built.scene; root.add_child(scene); await ticks(2)
		var opt: Dictionary=PhysicsServer3D.call("scene_info",scene.get_world_3d().space).runtime_options
		check(opt.solver=={"Newton":2,"CG":1,"PGS":0}[solver] and (int(opt.disableflags)&(1<<17))!=0 and (int(opt.disableflags)&(1<<19))!=0,"actual mjModel.opt "+solver)
		scene.queue_free(); await ticks(2)
	check(session.configure_world({}),"restore default world")
	check(session.configure(path,{"kind":"sdf","layer":0,"mask":0}),"native filtering")
	var filtered := session.build_scene(); var filter_scene: Node3D=filtered.scene; root.add_child(filter_scene); await ticks(2)
	var ghost := ball(filter_scene,Vector3(2,1,-4)); ghost.linear_velocity=Vector3(0,0,2)
	await ticks(95)
	check(ghost.position.z > -2,"native filtering disables target wall")
	filter_scene.queue_free(); await ticks(2)
	check(session.configure(path,JSON.parse_string('{"kind":"sdf","contact":{"condim":4,"friction":[1.4,0.02,0.001],"priority":2}}')),"contact material serialized "+session.error)
	check(session.configure_world({"solver":"CG","cone":"elliptic","nativeccd":false,"multiccd":false}),"persist world options")
	var packed := Package.pack(session,"res://packages"); check(packed.error.is_empty(),"pack "+packed.error)
	if packed.error.is_empty():
		var f := FileAccess.open("res://saved_path.txt",FileAccess.WRITE); f.store_string(packed.path); f.close()
	check(session.import_file("res://fixtures/box.obj","m","Y_UP",true),"primitive fixture")
	path = str(session.visual.get_path_to(session.meshes()[0]))
	for mode in ["plane","ellipsoid","box","sphere","capsule","cylinder"]:
		check(session.configure(path,{"kind":mode}),"primitive adapter "+mode)
		var built := session.build_scene(); var scene: Node3D = built.scene; root.add_child(scene); await ticks(3)
		var body := ball(scene,Vector3(0,2,0)); body.gravity_scale=1
		await ticks(90)
		check(body.position.y>-.05 and PhysicsServer3D.call("scene_info",scene.get_world_3d().space).ncon>0,"primitive actual contact "+mode)
		scene.queue_free(); await ticks(3)
	check(session.import_file("res://fixtures/hierarchy.gltf","m","Y_UP",true),"asymmetric hierarchy input")
	path = str(session.visual.get_path_to(session.meshes()[0]))
	check(session.configure(path,{"kind":"ellipsoid"}),"asymmetric ellipsoid")
	var transformed := session.build_scene(); var transform_scene: Node3D=transformed.scene; root.add_child(transform_scene); await ticks(2)
	var falling := ball(transform_scene,Vector3(3,6,4)); falling.gravity_scale=1; await ticks(90)
	check(absf(falling.position.y-4.2)<.1,"hierarchy scale and position actual contact")
	transform_scene.queue_free(); await ticks(2)
	session.close()
	print("NATIVE_COLLISION_RESULT ",JSON.stringify({"passed":passed,"failed":failed})); quit(0 if failed==0 else 1)
