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
