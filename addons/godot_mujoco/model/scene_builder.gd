@tool
extends RefCounted
const WorldScript = preload("runtime_world.gd")
const InstanceScript = preload("model_instance.gd")

static func create(model: MjAuthorResource) -> Node3D:
	var world := WorldScript.new()
	world.name = "MuJoCoWorld"
	world.world_design = model.fork()
	var instance := InstanceScript.new()
	instance.name = "Model"
	instance.design = model
	world.add_child(instance)
	instance.owner = world
	instance.author_scene = preload("author_scene.gd").new()
	instance.author_scene.initialize(instance)
	while not instance.author_scene.geometry_queue.is_empty(): instance.author_scene.build_geometry_step()
	return world

static func prepare_tree(root: Node) -> String:
	if root is MjModelInstance and root.design:
		var compiled := false
		if root.design_instance_id.is_empty(): root.design_instance_id = Crypto.new().generate_random_bytes(16).hex_encode()
		if root.design.validated_revision != root.design.revision or root.design.validated_context != root.compilation_signature():
			var error: String = await preload("author_builder.gd").compile_design(root.design,root.compilation_context())
			if not error.is_empty(): return error
			compiled = true
		if not root.author_scene:
			root.author_scene = preload("author_scene.gd").new()
			root.author_scene.initialize(root)
		if compiled:
			root.author_scene.apply_compiled({"entities":root.design.cached_entities,"geometry":root.design.cached_geometry,"collision_geometry":root.design.collision_geometry,"collision_stats":root.design.collision_stats,"context":root.design.validated_context,"snapshot":root.design.compiled_snapshot})
		while not root.author_scene.geometry_queue.is_empty(): root.author_scene.build_geometry_step()
	for child in root.get_children():
		var error := await prepare_tree(child)
		if not error.is_empty(): return error
	return ""

static func save(model: MjAuthorResource, path: String) -> Error:
	if not path.begins_with("res://") or path.contains("..") or path.get_extension() != "tscn": return ERR_INVALID_PARAMETER
	var world := create(model)
	var prepared := await prepare_tree(world)
	if not prepared.is_empty(): world.free(); return ERR_INVALID_DATA
	var scene := PackedScene.new()
	var error := scene.pack(world)
	world.free()
	if error != OK: return error
	return ResourceSaver.save(scene,path)

static func playground(environment: PackedScene) -> Control:
	var root := HBoxContainer.new()
	root.name="SimulationPlayground"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var host := preload("environment_host.gd").new()
	host.name="EnvironmentHost"
	host.environment_scene=environment
	host.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	host.size_flags_vertical=Control.SIZE_EXPAND_FILL
	host.custom_minimum_size=Vector2(640,480)
	root.add_child(host);host.owner=root
	# Retain the named controller API for saved scenes; its legacy UI is hidden.
	var controls := preload("simulation_controls.gd").new()
	controls.name="SimulationControls"
	controls.environment_host=host
	root.add_child(controls);controls.owner=root
	return root

static func save_playground(model: MjAuthorResource,path: String) -> Error:
	if not path.begins_with("res://") or path.contains("..") or path.get_extension()!="tscn": return ERR_INVALID_PARAMETER
	var world := create(model)
	world.start_paused=true
	var camera := Camera3D.new()
	camera.set_script(preload("orbit_camera.gd"))
	world.add_child(camera);camera.owner=world
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-50,-30,0)
	world.add_child(light);light.owner=world
	if not (await prepare_tree(world)).is_empty(): world.free(); return ERR_INVALID_DATA
	var environment := PackedScene.new()
	var error := environment.pack(world)
	world.free()
	if error!=OK:return error
	var root := playground(environment)
	var scene := PackedScene.new()
	error=scene.pack(root)
	root.free()
	if error!=OK:return error
	return ResourceSaver.save(scene,path)
