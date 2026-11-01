@tool
extends RefCounted
const Model = preload("model_instance.gd")
const Terrain = preload("static_heightfield.gd")
const Xml = preload("author_xml.gd")
const Artifact = preload("editor_artifact.gd")

static func nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child in root.get_children(): result.append_array(nodes(child))
	return result

static func shape_data(shape: Shape3D) -> Dictionary:
	if shape is BoxShape3D: return {"kind":"box", "size":shape.size}
	if shape is SphereShape3D: return {"kind":"sphere", "radius":shape.radius}
	if shape is CapsuleShape3D: return {"kind":"capsule", "radius":shape.radius, "height":shape.height}
	if shape is CylinderShape3D: return {"kind":"cylinder", "radius":shape.radius, "height":shape.height}
	if shape is WorldBoundaryShape3D: return {"kind":"plane", "plane":shape.plane}
	if shape is HeightMapShape3D: return {"kind":"heightmap", "width":shape.map_width, "depth":shape.map_depth, "data":shape.map_data}
	return {}

static func make_shape(value: Dictionary) -> Shape3D:
	match value.get("kind"):
		"box":
			var shape := BoxShape3D.new(); shape.size = value.size; return shape
		"sphere":
			var shape := SphereShape3D.new(); shape.radius = value.radius; return shape
		"capsule":
			var shape := CapsuleShape3D.new(); shape.radius = value.radius; shape.height = value.height; return shape
		"cylinder":
			var shape := CylinderShape3D.new(); shape.radius = value.radius; shape.height = value.height; return shape
		"plane":
			var shape := WorldBoundaryShape3D.new(); shape.plane = value.plane; return shape
		"heightmap":
			var shape := HeightMapShape3D.new(); shape.map_width = value.width; shape.map_depth = value.depth; shape.map_data = value.data; return shape
	return null

static func capture(world: Node3D) -> Dictionary:
	var models := []
	var physical := []
	for node in nodes(world):
		if node == world: continue
		if node is Model and node.design:
			models.append({"instance_id":node.design_instance_id, "name":str(node.name), "author":node.design.author_snapshot(), "compiled_snapshot":node.design.compiled_snapshot, "cache_path":node.design.cache_path, "cached_entities":node.design.cached_entities, "cached_geometry":node.design.cached_geometry, "collision_geometry":node.design.collision_geometry, "collision_stats":node.design.collision_stats, "validated_context":node.design.validated_context, "pose":node.global_transform})
		elif node is Terrain and node.design:
			physical.append({"path":str(world.get_path_to(node)), "kind":"terrain", "pose":node.global_transform, "design":node.design.snapshot(Transform3D.IDENTITY, node.collision_layer, node.collision_mask)})
		elif node.has_meta("map_specs") and node.get("native_collisions") is Array:
			physical.append({"path":str(world.get_path_to(node)), "kind":"map", "pose":node.global_transform, "collisions":node.native_collisions.duplicate(true)})
		elif node is PhysicsBody3D or node is Area3D:
			var properties := {"collision_layer":node.collision_layer, "collision_mask":node.collision_mask}
			if node is RigidBody3D:
				for key in ["mass", "gravity_scale", "linear_damp", "angular_damp", "freeze"]: properties[key] = node.get(key)
			if node is Area3D:
				for key in ["gravity", "gravity_direction", "gravity_space_override", "linear_damp", "angular_damp", "linear_damp_space_override", "angular_damp_space_override"]: properties[key] = node.get(key)
			if (node is RigidBody3D or node is StaticBody3D) and node.physics_material_override:
				var material: PhysicsMaterial = node.physics_material_override
				properties.material = {"friction":material.friction, "bounce":material.bounce, "rough":material.rough, "absorbent":material.absorbent}
			physical.append({"path":str(world.get_path_to(node)), "kind":node.get_class(), "pose":node.global_transform, "properties":properties})
		elif node is CollisionShape3D and node.shape:
			physical.append({"path":str(world.get_path_to(node)), "kind":"shape", "pose":node.transform, "disabled":node.disabled, "shape":shape_data(node.shape)})
	return {"models":models, "physical":physical, "world_xml":world.world_design.worker_xml() if world.get("world_design") else "", "world_author":world.world_design.author_snapshot() if world.get("world_design") else {}}

static func signature(layout: Dictionary) -> String:
	var lean := layout.duplicate()
	# world_xml is derived from the author tree and can differ only in attribute
	# order after a Godot resource round trip.
	lean.erase("world_xml")
	var models := []
	for model in layout.get("models", []):
		var item: Dictionary = model.duplicate()
		for key in ["cache_path","compiled_snapshot","cached_entities","cached_geometry","collision_geometry","collision_stats","validated_context"]: item.erase(key)
		models.append(item)
	lean.models = models
	return var_to_bytes(canonical(lean)).hex_encode().sha256_text()

static func canonical(value: Variant) -> Variant:
	return Artifact.canonical(value)
