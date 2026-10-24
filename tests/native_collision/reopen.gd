extends SceneTree
func _initialize(): call_deferred("run")
func run():
	var path := FileAccess.get_file_as_string("res://saved_path.txt")
	var error := preload("res://addons/godot_mujoco/map/package.gd").validate(path)
	if not error.is_empty(): print(error); quit(1); return
	var scene = load(path.path_join("map.tscn")).instantiate(); root.add_child(scene)
	await physics_frame; await process_frame
	var ok: bool = scene.native_rids.size()==1 and scene.last_error.is_empty() and scene.native_collisions[0].contract.actual_mode=="sdf"
	var info: Dictionary = PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
	ok = ok and info.runtime_options.solver==1 and info.runtime_options.cone==1 and (int(info.runtime_options.disableflags) & (1<<17))!=0 and (int(info.runtime_options.disableflags) & (1<<19))!=0
	var body := RigidBody3D.new(); body.position=Vector3(2,1,-4); body.gravity_scale=0; body.linear_damp_mode=RigidBody3D.DAMP_MODE_REPLACE; body.linear_damp=0
	var shape := CollisionShape3D.new(); shape.shape=SphereShape3D.new(); shape.shape.radius=.2; body.add_child(shape); scene.add_child(body); body.linear_velocity=Vector3(0,0,2)
	var material_ok := false
	for i in 90:
		await physics_frame; await process_frame
		info = PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
		for contact in info.contact_details:
			if contact.geoms.any(func(n): return str(n).ends_with("_collision")) and absf(contact.position.x-2)<.6 and contact.force_contact_frame[0]>0:
				material_ok = material_ok or (contact.condim==4 and absf(contact.friction_components[0]-1.4)<.00001 and absf(contact.friction_components[2]-.02)<.00001 and absf(contact.normal.z)>.8)
	ok = ok and body.position.z < -3.2 and material_ok
	print("NATIVE_REOPEN ",ok," target material/force ",material_ok)
	scene.queue_free(); await process_frame
	var attribute_path:=FileAccess.get_file_as_string("res://attribute_path.txt")
	var attribute_scene=load(attribute_path.path_join("map.tscn")).instantiate(); root.add_child(attribute_scene); await physics_frame; await process_frame
	var attribute_info: Dictionary=PhysicsServer3D.call("scene_info",attribute_scene.get_world_3d().space)
	ok=ok and attribute_info.runtime_options.iterations==100 and attribute_info.runtime_options.noslip_iterations==0 and absf(attribute_info.runtime_options.o_friction[0]-.3)<.00001
	print("NATIVE_ATTRIBUTE_REOPEN ",ok)
	attribute_scene.queue_free(); await process_frame
	var height_path:=FileAccess.get_file_as_string("res://height_attribute_path.txt")
	var height_scene=load(height_path.path_join("map.tscn")).instantiate(); root.add_child(height_scene); await physics_frame; await process_frame
	var height_ball:=RigidBody3D.new(); height_ball.position=Vector3(0,2,0)
	var height_shape:=CollisionShape3D.new(); height_shape.shape=SphereShape3D.new(); height_shape.shape.radius=.2; height_ball.add_child(height_shape); height_scene.add_child(height_ball)
	var height_contact:=false
	for i in 80:
		await physics_frame; await process_frame
		for contact in PhysicsServer3D.call("scene_info",height_scene.get_world_3d().space).contact_details:
			if contact.geoms.any(func(n):return str(n).ends_with("_collision")) and contact.force_contact_frame[0]>0 and absf(contact.friction-1.8)<.00001: height_contact=true
	ok=ok and height_contact
	height_scene.queue_free(); await process_frame
	var pair_path:=FileAccess.get_file_as_string("res://pair_path.txt")
	var pair_scene=load(pair_path.path_join("map.tscn")).instantiate(); root.add_child(pair_scene); await physics_frame; await process_frame
	var pair_info: Dictionary=PhysicsServer3D.call("scene_info",pair_scene.get_world_3d().space)
	ok=ok and pair_info.npair==1 and pair_info.ncon>0 and pair_info.contact_details.any(func(c):return c.condim==4 and absf(c.friction-.7)<.00001) and pair_scene.get_meta("map_contact_relations").pairs.size()==1
	print("NATIVE_HEIGHT_PAIR_REOPEN ",ok)
	pair_scene.queue_free(); await process_frame; quit(0 if ok else 1)
