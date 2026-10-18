extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
const SceneBuilder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not doc.import_g1("res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf"):
		printerr(doc.get_error()); quit(1); return
	for command in [
		{"op":"set","kind":"actuator","name":"left_elbow_joint_position","values":{"kp":120.0,"kv":12.0}},
		{"op":"qpos","name":"left_elbow_joint","value":.4},
		{"op":"control","name":"left_elbow_joint_position","value":.4},
		{"op":"set","kind":"body","name":"left_elbow_link","values":{"mass":.8}}
	]:
		if not doc.edit(command): printerr(doc.get_error()); quit(1); return
	var packaged: Dictionary = Builder.pack(doc,"res://models","g1")
	if not packaged.error.is_empty(): printerr(packaged.error); quit(1); return
	var model = ResourceLoader.load(packaged.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var world = SceneBuilder.create(model)
	world.start_paused = false
	world.get_node("Model").position.y = 1.1
	var second = Instance.new()
	second.name = "SecondModel"
	second.model = model
	second.position = Vector3(2.0,1.1,0)
	world.add_child(second)
	second.owner = world
	var floor := StaticBody3D.new()
	floor.name = "Floor"
	floor.position.y = -.05
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(8,.1,8)
	add_body(world,floor,floor_shape,Color("55646b"))
	var box := RigidBody3D.new()
	box.name = "Obstacle"
	box.mass = .5
	box.collision_layer = 1
	box.collision_mask = 3
	box.position = Vector3(0,3,0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(.6,.4,.6)
	add_body(world,box,shape,Color("df9443"))
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(4,2.5,4)
	camera.look_at_from_position(camera.position,Vector3(.8,.8,0))
	world.add_child(camera); camera.owner = world
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-30,0)
	world.add_child(light); light.owner=world
	var scene := PackedScene.new()
	if scene.pack(world)!=OK or ResourceSaver.save(scene,"res://RuntimeScene.tscn")!=OK:
		printerr("Could not save runtime scene");quit(1);return
	world.free()
	var f := FileAccess.open("res://g1-resource-path.txt",FileAccess.WRITE)
	f.store_string(packaged.path);f.close()
	# A multi-free-root model exercises whole-spec attachment, not the G1-only path.
	f=FileAccess.open("res://multi.xml",FileAccess.WRITE)
	f.store_string("<mujoco><worldbody><geom name='base' type='plane' size='4 4 .1'/><body name='a' pos='0 0 1'><freejoint name='a_free'/><geom name='a_geom' type='sphere' size='.2' mass='2'/></body><body name='b' pos='1 0 1'><freejoint name='b_free'/><geom name='b_geom' type='cylinder' size='.2 .3' mass='3'/></body></worldbody></mujoco>")
	f.close()
	if not doc.import_file("res://multi.xml"):printerr(doc.get_error());quit(1);return
	var multi: Dictionary = Builder.pack(doc,"res://models","multi")
	if not multi.error.is_empty():printerr(multi.error);quit(1);return
	f=FileAccess.open("res://multi-resource-path.txt",FileAccess.WRITE);f.store_string(multi.path);f.close()
	var conflicts := {}
	for key in ["gravity", "timestep", "solver"]:
		var attrs := "gravity='0 0 -9.8' integrator='implicitfast'"
		if key=="gravity": attrs="gravity='0 0 -8' integrator='implicitfast'"
		if key=="timestep": attrs += " timestep='0.003'"
		if key=="solver": attrs += " solver='PGS'"
		f=FileAccess.open("res://conflict.xml",FileAccess.WRITE)
		f.store_string("<mujoco><option "+attrs+"/><worldbody><body name='object'><geom type='box' size='.1 .1 .1'/></body></worldbody></mujoco>");f.close()
		if not doc.import_file("res://conflict.xml"): printerr(doc.get_error());quit(1);return
		var result: Dictionary = Builder.pack(doc,"res://models",key)
		if not result.error.is_empty():printerr(result.error);quit(1);return
		conflicts[key] = result.path
	f=FileAccess.open("res://conflict-resources.json",FileAccess.WRITE);f.store_string(JSON.stringify(conflicts));f.close()
	ProjectSettings.set_setting("application/run/main_scene","res://RuntimeScene.tscn")
	ProjectSettings.save()
	print("AUTHOR_RUNTIME_PASS ",packaged.path)
	quit(0)
func add_body(world: Node3D, body: PhysicsBody3D, shape: BoxShape3D, color: Color) -> void:
	world.add_child(body);body.owner=world
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision);collision.owner=world
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new();mesh.size=shape.size;visual.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=color;visual.material_override=material
	body.add_child(visual);visual.owner=world
