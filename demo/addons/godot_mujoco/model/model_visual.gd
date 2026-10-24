@tool
extends RefCounted
static func create(geom: Dictionary) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var size: Vector3 = geom.get("source_size", geom.size)
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
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			instance.mesh = mesh
	if not instance.mesh:
		instance.free()
		return null
	var material := StandardMaterial3D.new()
	material.albedo_color = geom.get("color",Color("8094a8"))
	material.roughness = .85
	instance.material_override = material
	instance.transform = geom.transform
	if geom.type == 4: instance.scale = Vector3(size.x,size.z,size.y)
	return instance
