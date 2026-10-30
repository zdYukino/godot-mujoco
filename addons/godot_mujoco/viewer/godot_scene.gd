extends Node3D
## Convert official abstract diagnostic geoms; authored surfaces keep their materials.
## MuJoCo 3.16 classic/render_gl3.c shape conventions; see src/viewer/UPSTREAM.md.
var pool: Array[Node3D] = []
var meshes := {}
func primitive(kind: int, dimensions: Vector3) -> Mesh:
	var key := "%d:%s" % [kind,dimensions]
	if meshes.has(key): return meshes[key]
	var mesh: PrimitiveMesh
	if kind in [103,108]:
		var vertices := PackedVector3Array([Vector3.ZERO,Vector3(0,dimensions.z,0)]) if kind==103 else PackedVector3Array([Vector3.ZERO,Vector3(dimensions.x,0,0),Vector3(0,0,-dimensions.y)])
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
		var shape := ArrayMesh.new(); shape.add_surface_from_arrays(Mesh.PRIMITIVE_LINES if kind==103 else Mesh.PRIMITIVE_TRIANGLES,arrays)
		if meshes.size()>512: meshes.clear()
		meshes[key]=shape
		return shape
	if kind==104:
		var vertices := PackedVector3Array()
		var corners: Array[Vector3]=[]
		for x in [-1,1]:
			for y in [-1,1]:
				for z in [-1,1]: corners.append(Vector3(x*dimensions.x,y*dimensions.z,z*dimensions.y))
		for a in 8:
			for bit in [1,2,4]:
				var b: int=a^bit
				if a<b: vertices.append(corners[a]); vertices.append(corners[b])
		var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices
		var wire := ArrayMesh.new(); wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		if meshes.size()>512: meshes.clear()
		meshes[key]=wire
		return wire
	match kind:
		2,4:
			mesh=SphereMesh.new(); mesh.radius=maxf(.0001,dimensions.x); mesh.height=2*mesh.radius
		3:
			mesh=CapsuleMesh.new(); mesh.radius=maxf(.0001,dimensions.x); mesh.height=maxf(2*mesh.radius,2*(dimensions.z+dimensions.x))
		5,100,101,102:
			mesh=CylinderMesh.new(); mesh.top_radius=maxf(.0002,dimensions.x); mesh.bottom_radius=mesh.top_radius; mesh.height=maxf(.0001,2*dimensions.z)
		200:
			mesh=CylinderMesh.new(); mesh.top_radius=0; mesh.bottom_radius=maxf(.0002,dimensions.x); mesh.height=maxf(.0001,dimensions.z)
		6:
			mesh=BoxMesh.new(); mesh.size=Vector3(dimensions.x,dimensions.z,dimensions.y)*2
		_:
			return null
	if meshes.size()>512: meshes.clear()
	meshes[key]=mesh
	return mesh
func apply(frame: Dictionary, world: Node3D) -> void:
	visible=not world.native_view_active
	if not visible: return
	var geoms: Array=frame.get("decorations",[])
	while pool.size()<geoms.size():
		var root := Node3D.new(); add_child(root)
		var surface := MeshInstance3D.new(); root.add_child(surface)
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test=false
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		surface.material_override=material
		var label := Label3D.new(); label.billboard=BaseMaterial3D.BILLBOARD_ENABLED; label.font_size=24; label.pixel_size=.002; root.add_child(label)
		for unused in 2:
			var head := MeshInstance3D.new(); head.material_override=material; root.add_child(head)
		pool.append(root)
	for i in pool.size():
		var root := pool[i]; root.visible=i<geoms.size()
		if not root.visible: continue
		var data: Dictionary=geoms[i]; root.global_transform=data.transform
		var surface: MeshInstance3D=root.get_child(0); var label: Label3D=root.get_child(1)
		var dimensions: Vector3=data.size; surface.scale=Vector3.ONE
		surface.position=Vector3.ZERO
		surface.mesh=null if data.model_geom else primitive(data.type,dimensions)
		for index in [2,3]: root.get_child(index).visible=false
		if data.type in [100,101,102] and not data.model_geom:
			var double_arrow: bool=data.type==102
			# The official arrow's z size is twice its visual length. Single
			# arrows start at the origin; double arrows are centered there.
			surface.scale.y=1./3 if double_arrow else 1./6
			surface.position.y=0 if double_arrow else dimensions.z/6
			if dimensions.x>0: surface.scale.z=dimensions.y/dimensions.x
			for index in (2 if double_arrow else 1):
				var head: MeshInstance3D=root.get_child(2+index)
				head.mesh=primitive(200,Vector3(dimensions.x*(1 if data.type==101 else 1.75),0,dimensions.z/6)); head.visible=true
				head.scale=Vector3(1,1,dimensions.y/dimensions.x if dimensions.x>0 else 1)
				head.position.y=dimensions.z*5./12*(1 if index==0 else -1); head.rotation.z=0 if index==0 else PI
		if data.type==4 and dimensions.x>0: surface.scale=Vector3(1,dimensions.z/dimensions.x,dimensions.y/dimensions.x)
		surface.material_override.albedo_color=data.color
		label.text=data.label; label.modulate=data.color; label.visible=not label.text.is_empty()
