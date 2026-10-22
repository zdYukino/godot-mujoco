@tool
class_name MjHeightFieldData
extends Resource
## Fixed resolution, one metre between samples, row-major increasing local Z.
@export_range(2, 256, 1) var width := 2
@export_range(2, 256, 1) var depth := 2
@export var heights := PackedFloat32Array([0, 0, 0, 0])

func validate() -> String:
	if width < 2 or width > 256 or depth < 2 or depth > 256 or heights.size() != width * depth:
		return "Grid dimensions must be 2..256 with exactly width*depth heights"
	for h in heights:
		if not is_finite(h) or absf(h) > 10000: return "Heights must be finite, within +/-10000 metres; holes unsupported"
	return ""

func snapshot(pose: Transform3D, layer: int, mask: int) -> Dictionary:
	return {"width":width, "depth":depth, "heights":heights.duplicate(), "pose":pose, "layer":layer, "mask":mask}

func mesh() -> ArrayMesh:
	if not validate().is_empty(): return null
	var vertices := PackedVector3Array()
	var low := heights[0] - 1.0
	for h in heights: low = minf(low, h - 1.0)
	# After Z-up conversion MuJoCo's cell diagonal joins (+X,-Z) to (-X,+Z).
	for z in depth - 1:
		for x in width - 1:
			var a := _point(x,z)
			var b := _point(x+1,z)
			var c := _point(x,z+1)
			var d := _point(x+1,z+1)
			vertices.append_array(PackedVector3Array([a,b,c,b,d,c]))
	# Draw the solid base and side walls too, matching the one-metre base depth.
	for z in depth - 1:
		_wall(vertices,_point(0,z+1),_point(0,z),low)
		_wall(vertices,_point(width-1,z),_point(width-1,z+1),low)
	for x in width - 1:
		_wall(vertices,_point(x,0),_point(x+1,0),low)
		_wall(vertices,_point(x+1,depth-1),_point(x,depth-1),low)
	var a := _point(0,0); a.y = low
	var b := _point(width-1,0); b.y = low
	var c := _point(0,depth-1); c.y = low
	var d := _point(width-1,depth-1); d.y = low
	vertices.append_array(PackedVector3Array([a,c,b,b,c,d]))
	var normals := PackedVector3Array()
	for i in range(0,vertices.size(),3):
		var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		normals.append_array(PackedVector3Array([normal,normal,normal]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	var result := ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func _point(x: int,z: int) -> Vector3:
	return Vector3(x-(width-1)*0.5,heights[z*width+x],z-(depth-1)*0.5)
func _wall(vertices: PackedVector3Array,a: Vector3,b: Vector3,low: float) -> void:
	var c := Vector3(a.x,low,a.z)
	var d := Vector3(b.x,low,b.z)
	vertices.append_array(PackedVector3Array([a,c,b,b,c,d]))
