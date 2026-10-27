@tool
extends RefCounted
## Rendering only: never replace an authored visual mesh/material or add physics.
static func lines(points: PackedVector3Array, color := Color(1,.65,.08)) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if points.is_empty(): return instance
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
	for point in points: surface.add_vertex(point)
	instance.mesh=surface.commit()
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color; material.no_depth_test=false
	instance.material_override=material
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

static func wireframe(mesh: Mesh) -> MeshInstance3D:
	var points := PackedVector3Array()
	var seen := {}
	var faces := mesh.get_faces()
	for i in range(0,faces.size(),3):
		for edge in [[0,1],[1,2],[2,0]]:
			var a: Vector3=faces[i+edge[0]]; var b: Vector3=faces[i+edge[1]]
			var key: String=str(a)+"/"+str(b) if a<b else str(b)+"/"+str(a)
			if seen.has(key): continue
			seen[key]=true; points.append(a); points.append(b)
	return lines(points)

static func bounds(box: AABB) -> MeshInstance3D:
	var points := PackedVector3Array()
	for i in 8:
		for bit in [1,2,4]:
			if (i & bit)==0: points.append(box.get_endpoint(i)); points.append(box.get_endpoint(i|bit))
	return lines(points,Color(.1,.85,1))
