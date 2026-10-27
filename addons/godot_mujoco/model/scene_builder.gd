@tool
extends RefCounted
const WorldScript = preload("runtime_world.gd")
const InstanceScript = preload("model_instance.gd")

static func create(model: MjModelResource) -> Node3D:
	var world := WorldScript.new()
	world.name = "MuJoCoWorld"
	world.world_model = model
	var instance := InstanceScript.new()
	instance.name = "Model"
	instance.model = model
	world.add_child(instance)
	instance.owner = world
	return world

static func save(model: MjModelResource, path: String) -> Error:
	if not path.begins_with("res://") or path.contains("..") or path.get_extension() != "tscn": return ERR_INVALID_PARAMETER
	var world := create(model)
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
	var controls := preload("simulation_controls.gd").new()
	controls.name="SimulationControls"
	controls.environment_host=host
	controls.custom_minimum_size.x=360
	root.add_child(controls);controls.owner=root
	return root

static func save_playground(model: MjModelResource,path: String) -> Error:
	if not path.begins_with("res://") or path.contains("..") or path.get_extension()!="tscn": return ERR_INVALID_PARAMETER
	var world := create(model)
	world.start_paused=true
	var camera := Camera3D.new()
	camera.set_script(preload("orbit_camera.gd"))
	world.add_child(camera);camera.owner=world
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-50,-30,0)
	world.add_child(light);light.owner=world
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
