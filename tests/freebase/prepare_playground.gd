extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
const SceneBuilder=preload("res://addons/godot_mujoco/model/scene_builder.gd")
func _initialize() -> void: call_deferred("run")
func add_visual_body(world: Node,body: PhysicsBody3D,shape: Shape3D,color: Color) -> void:
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var visual:=MeshInstance3D.new()
	if shape is BoxShape3D:
		var mesh:=BoxMesh.new();mesh.size=shape.size;visual.mesh=mesh
	else:
		var mesh:=SphereMesh.new();mesh.radius=shape.radius;mesh.height=shape.radius*2;visual.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=color;visual.material_override=material
	body.add_child(visual);world.add_child(body);body.owner=world;collision.owner=world;visual.owner=world
func run() -> void:
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	if not doc.import_g1("res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf",true,true):printerr(doc.get_error());quit(1);return
	var package: Dictionary=Builder.pack(doc,"res://models","freebase_playground")
	if not package.error.is_empty():printerr(package.error);quit(1);return
	var resource=load(package.path)
	var world=SceneBuilder.create(resource);world.start_paused=true
	world.get_node("Model").position.y=.8
	var floor:=StaticBody3D.new();floor.name="Ground";floor.position.y=-.05;floor.collision_mask=3
	var box:=BoxShape3D.new();box.size=Vector3(12,.1,12);add_visual_body(world,floor,box,Color(.2,.24,.3))
	var obstacle:=RigidBody3D.new();obstacle.name="Obstacle";obstacle.position=Vector3(.6,.5,0);obstacle.mass=2;obstacle.collision_mask=3
	box=BoxShape3D.new();box.size=Vector3(.4,.4,.4);add_visual_body(world,obstacle,box,Color(.9,.5,.15))
	var camera:=Camera3D.new();camera.set_script(preload("res://addons/godot_mujoco/model/orbit_camera.gd"));world.add_child(camera);camera.owner=world
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);world.add_child(light);light.owner=world
	var environment:=PackedScene.new()
	if environment.pack(world)!=OK or ResourceSaver.save(environment,"res://FreebaseEnvironment.tscn")!=OK:quit(1);return
	world.free()
	var playground=SceneBuilder.playground(load("res://FreebaseEnvironment.tscn"))
	var scene:=PackedScene.new()
	if scene.pack(playground)!=OK or ResourceSaver.save(scene,"res://FreebasePlayground.tscn")!=OK:quit(1);return
	playground.free()
	print("FREEBASE PLAYGROUND SAVED: res://FreebasePlayground.tscn")
	quit(0)
