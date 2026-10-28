@tool
extends RefCounted
static func create(geom: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var size: Vector3 = geom.get("source_size", geom.size)
	if geom.has("mesh_path"):
		instance.mesh = ResourceLoader.load(geom.mesh_path, "Mesh")
	else:
		_create_mesh(instance, geom, size)
		if geom.has("texture_image") or geom.has("texture_path"): _project_texture(instance, geom, size)
	if not instance.mesh:
		instance.free()
		return null
	var material := StandardMaterial3D.new()
	material.albedo_color = geom.get("color",Color("8094a8"))
	if geom.has("texture_path"):
		material.albedo_texture = ResourceLoader.load(geom.texture_path, "Texture2D")
	elif geom.has("texture_image"):
		material.albedo_texture = texture(geom.texture_image)
	var repeat: Vector2 = geom.get("texture_repeat", Vector2.ONE)
	material.uv1_scale = Vector3(repeat.x, repeat.y, 1.0)
	if material.albedo_color.a < 1.0 or geom.get("texture_alpha", false) or geom.get("texture_image", {}).get("channels", 3) == 4:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = .85
	instance.material_override = material
	instance.transform = geom.transform
	if geom.type == 4: instance.scale = Vector3(size.x,size.z,size.y)
	return instance

static func texture(data: Dictionary) -> ImageTexture:
	var format: int = {1:Image.FORMAT_L8, 3:Image.FORMAT_RGB8, 4:Image.FORMAT_RGBA8}.get(data.channels, -1)
	if format < 0: return null
	var image := Image.create_from_data(data.width, data.height, false, format, data.pixels)
	return ImageTexture.create_from_image(image)

static func _project_texture(instance: MeshInstance3D, geom: Dictionary, size: Vector3) -> void:
	if not instance.mesh or geom.has("uvs"): return
	# MJCF 2D textures use a projection along local Z when the source has no UVs.
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	var extent := Vector2(size.x, size.y if geom.type in [0, 1, 4, 6] else size.x)
	if geom.get("texture_uniform", false): extent = Vector2.ONE
	for vertex in vertices:
		if geom.type == 4: vertex *= Vector3(size.x, size.z, size.y)
		uvs.append(Vector2(vertex.x / maxf(extent.x, .000001), -vertex.z / maxf(extent.y, .000001)) * .5 + Vector2(.5, .5))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	instance.mesh = mesh

static func _create_mesh(instance: MeshInstance3D, geom: Dictionary, size: Vector3) -> void:
	match geom.type:
		0:
			var mesh := PlaneMesh.new()
			mesh.size = Vector2(maxf(2*size.x,10),maxf(2*size.y,10))
			instance.mesh = mesh
		2:
			var mesh := SphereMesh.new()
			mesh.radius = size.x
			mesh.height = 2*size.x
			instance.mesh = mesh
		3:
			var mesh := CapsuleMesh.new()
			mesh.radius = size.x
			mesh.height = 2*(size.x+size.y)
			instance.mesh = mesh
		4:
			var mesh := SphereMesh.new()
			mesh.radius = 1
			mesh.height = 2
			instance.mesh = mesh
		5:
			var mesh := CylinderMesh.new()
			mesh.top_radius = size.x
			mesh.bottom_radius = size.x
			mesh.height = 2*size.y
			instance.mesh = mesh
		6:
			var mesh := BoxMesh.new()
			mesh.size = Vector3(size.x,size.z,size.y)*2
			instance.mesh = mesh
		1, 7, 8:
			var mesh := ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = geom.vertices
			arrays[Mesh.ARRAY_NORMAL] = geom.normals
			if geom.has("uvs"): arrays[Mesh.ARRAY_TEX_UV] = geom.uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			instance.mesh = mesh
