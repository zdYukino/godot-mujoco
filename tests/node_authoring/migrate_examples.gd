extends SceneTree
## Development migration: run only in an isolated copy of an example project.
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Scene = preload("res://addons/godot_mujoco/model/author_scene.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
var compiler: Node
var result: Dictionary
func _initialize() -> void: call_deferred("run")
func fail(message: String) -> void:
	push_error(message)
	quit(1)
func compile_design(design: Resource) -> bool:
	result = {}
	compiler.submit({"author":design.author_snapshot(),"revision":design.revision})
	while compiler.busy(): await process_frame
	if not result.get("success", false): fail(str(result.get("error", "Missing compilation result"))); return false
	design.validated_revision = design.revision
	design.cached_entities = result.entities
	design.cached_geometry = result.geometry
	design.collision_geometry = result.collision_geometry
	design.compiled_snapshot = result.snapshot
	design.cache_path = ""
	return true
func build_model(model: Node, owner: Node) -> bool:
	if not model.design:
		var error: String = model.upgrade_author_model()
		if not error.is_empty(): fail(error); return false
	if not await compile_design(model.design): return false
	var helper := Scene.new()
	helper.initialize(model)
	while not helper.geometry_queue.is_empty(): helper.build_geometry_step()
	model.model = null
	model.owner = owner
	return true
func plain_design() -> Resource:
	return Author.from_xml('<mujoco><compiler angle="radian"/><option timestep=".002" gravity="0 0 -9.81"/><worldbody/></mujoco>').design
func set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		set_owners(child, owner)
func save_scene(scene: Node, path: String) -> void:
	var packed := PackedScene.new()
	if packed.pack(scene) != OK or ResourceSaver.save(packed,path) != OK: fail("Cannot save " + path); return
	scene.free()
func run() -> void:
	compiler = Service.new(); root.add_child(compiler)
	compiler.completed.connect(func(value): result = value)
	var kind := OS.get_cmdline_user_args()[0]
	if kind == "light_workflow":
		await light_workflow()
	else:
		var paths := ["G1.tscn"] if kind == "g1_passive" else ["Main.tscn", "ChaosPendulum.tscn", "VisualDebug.tscn"] if kind == "pendulum" else ["Main.tscn"]
		for path in paths:
			var scene: Node = load("res://" + path).instantiate()
			if kind == "sdf_terrain":
				var wrapper := World.new(); wrapper.name = "SdfTerrainWorld"; wrapper.world_design = plain_design()
				scene.name = "Map"; scene.scene_file_path = ""; wrapper.add_child(scene); set_owners(wrapper,wrapper)
				scene = wrapper
			elif kind == "new_project":
				scene.set_script(World); scene.world_design = plain_design()
			elif kind == "pendulum":
				await migrate_pendulum(scene,path)
			else:
				if not scene.world_design: scene.world_design = Author.from_legacy(scene.world_model).design
				for child in scene.get_children():
					if child is Model and not await build_model(child,scene): return
				scene.world_model = null
			save_scene(scene,"res://" + path)
	compiler.queue_free(); await process_frame
	print("NODE_EXAMPLE_MIGRATED ",kind)
	quit()
func migrate_pendulum(scene: Node, path: String) -> void:
	var source: String = {"Main.tscn":"pendulum", "ChaosPendulum.tscn":"double_pendulum", "VisualDebug.tscn":"contacts"}[path]
	var design: Resource = Author.from_xml(FileAccess.get_file_as_string("res://models/" + source + ".xml")).design
	if path == "ChaosPendulum.tscn":
		for entity in design.entities():
			if entity.kind == "joint": design.initial_pose[entity.id] = [3.1 if entity.name == "shoulder" else .2]
	scene.world_design = design.fork()
	var model := Model.new(); model.name = "Model"; model.design = design
	scene.add_child(model); model.owner = scene
	await build_model(model,scene)
	if path == "Main.tscn":
		var old := scene.get_node("Pendulum")
		var visual: MeshInstance3D = model.get_node("pendulum").find_child("_Visual",true,false)
		visual.material_override = old.get_node("Rod").material_override
		var hub := old.get_node("Pivot"); hub.owner = null; old.remove_child(hub); model.get_node("pendulum").add_child(hub); hub.owner = scene
		scene.remove_child(old); old.free()
	elif path == "ChaosPendulum.tscn":
		var pivot := scene.get_node("Pivot/UpperPivot")
		model.get_node("upper/upper_rod/_Visual").material_override = pivot.get_node("UpperRod").material_override
		model.get_node("upper/lower/lower_rod/_Visual").material_override = pivot.get_node("LowerPivot/LowerRod").material_override
		var tip := pivot.get_node("LowerPivot/Tip"); tip.owner = null; tip.get_parent().remove_child(tip); model.get_node("upper/lower").add_child(tip); tip.owner = scene
		pivot.get_parent().remove_child(pivot); pivot.free()
	else:
		var ground := scene.get_node("Ground")
		model.get_node("floor/_Visual").material_override = ground.material_override
		scene.remove_child(ground); ground.free()
		var index := 0
		for entity in design.entities():
			if entity.kind != "body": continue
			var body: Node = model.get_node(entity.name)
			var visual: MeshInstance3D = body.find_child("_Visual",true,false)
			visual.material_override.albedo_color = Color.from_hsv(float(index+1)/5.0,.55,.9)
			index += 1
func light_workflow() -> void:
	var scene := Node.new(); scene.name = "LightWorkflow"
	# Attach C# after generating the complete scene; no runtime resource preparation.
	var world := World.new(); world.name = "Environment"; world.start_paused = true
	world.world_design = plain_design(); scene.add_child(world)
	var xml := '<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0" damping="1" range="-1 1"/><geom name="arm_geom" type="box" size=".1 .1 .3" mass="1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="20"/></actuator></mujoco>'
	for index in 2:
		var model := Model.new(); model.name = "First" if index == 0 else "Second"
		model.position.x = index*2.0; model.design = Author.from_xml(xml).design
		world.add_child(model); model.owner = scene
		if not await build_model(model,scene): return
	var box := RigidBody3D.new(); box.name = "Box"; box.position = Vector3(4,2,0)
	var collider := CollisionShape3D.new(); collider.name = "Collider"; collider.shape = BoxShape3D.new(); collider.shape.size = Vector3.ONE*.4
	box.add_child(collider)
	var mesh := MeshInstance3D.new(); mesh.name = "Visual"; mesh.mesh = BoxMesh.new(); mesh.mesh.size = Vector3.ONE*.4; box.add_child(mesh); world.add_child(box)
	var terrain: Node = load("res://addons/godot_mujoco/model/static_heightfield.gd").new(); terrain.name = "Terrain"
	terrain.design = load("res://addons/godot_mujoco/model/heightfield_data.gd").new(); terrain.design.width=11;terrain.design.depth=11;terrain.design.heights.resize(121);terrain.design.heights.fill(.3);world.add_child(terrain)
	var camera := Camera3D.new(); camera.name = "Camera"; camera.position = Vector3(8,7,11); camera.current = true
	camera.basis = Basis.looking_at(Vector3(1,0,0)-camera.position); scene.add_child(camera)
	var light := DirectionalLight3D.new(); light.name = "Sun"; light.rotation_degrees = Vector3(-55,-25,0); scene.add_child(light)
	set_owners(scene,scene)
	save_scene(scene,"res://Main.tscn")
	# The final root script is a normal C# binding, attached without loading Mono here.
	var text := FileAccess.get_file_as_string("res://Main.tscn")
	var marker := text.find("\n\n")
	text = text.insert(marker,'\n\n[ext_resource type="Script" path="res://LightWorkflow.cs" id="99_workflow"]')
	text = text.replace('[node name="LightWorkflow" type="Node"]','[node name="LightWorkflow" type="Node"]\nscript = ExtResource("99_workflow")')
	# Godot 4.7 writes unique_id on scene nodes.
	if not text.contains('script = ExtResource("99_workflow")'):
		var node_start := text.find('[node name="LightWorkflow"')
		text = text.insert(text.find("\n",node_start),'\nscript = ExtResource("99_workflow")')
	var output := FileAccess.open("res://Main.tscn",FileAccess.WRITE); output.store_string(text); output.close()
