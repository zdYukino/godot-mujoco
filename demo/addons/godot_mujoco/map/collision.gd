@tool
extends RefCounted
## No convex/concave Shape resources: explicitly authored supported primitives only.
static func pose_of(node: Node3D, root: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		pose = parent.transform * pose; parent = parent.get_parent()
	return pose

static func build(mesh: MeshInstance3D, root: Node3D, spec: Dictionary) -> Dictionary:
	var pose := pose_of(mesh, root)
	if not pose.is_finite() or pose.basis.determinant() <= 0: return {"error":"拒绝镜像/非有限碰撞变换"}
	var scale_value := pose.basis.get_scale()
	var rotation := pose.basis.orthonormalized()
	if not pose.basis.is_equal_approx(rotation.scaled_local(scale_value)): return {"error":"拒绝剪切碰撞变换"}
	var kind: String = spec.get("kind", "visual")
	if kind == "visual": return {"error":"仅视觉；碰撞未生成"}
	if kind not in ["box", "sphere", "capsule", "cylinder", "compound_boxes"]: return {"error":"原生凸/凹网格未支持；请显式提供多基础体，不生成整栋单凸包"}
	for field in ["layer","mask"]:
		var value: Variant = spec.get(field, 1)
		if not value is int or value < 0 or value > 4294967295: return {"error":"碰撞层/掩码必须为 uint32"}
	var friction: Variant = spec.get("friction", 1.0)
	if typeof(friction) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(friction) or friction < 0 or friction > 1: return {"error":"摩擦必须为 [0,1] 有限值"}
	var bounds := mesh.mesh.get_aabb()
	var parts: Array = spec.get("parts", []) if kind == "compound_boxes" else [{"center":bounds.get_center(),"size":bounds.size}]
	if parts.is_empty() or parts.size() > 256: return {"error":"组合碰撞需 1..256 个显式 box；未通过建筑可行性门"}
	var body := StaticBody3D.new(); body.name = "Collision"
	body.transform = Transform3D(rotation, pose.origin)
	body.collision_layer = spec.get("layer", 1); body.collision_mask = spec.get("mask", 1)
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = friction; body.physics_material_override.rough = spec.get("rough", false)
	var volume := 0.0
	for part in parts:
		if not part is Dictionary or not part.get("center") is Vector3 or not part.get("size") is Vector3:
			body.free(); return {"error":"组合碰撞需要局部坐标 center/size Vector3"}
		var size: Vector3 = part.size * scale_value
		if not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0 or not part.center.is_finite():
			body.free(); return {"error":"碰撞尺寸必须有限且为正；平面网格请明确给出厚度"}
		var shape: Shape3D
		match kind:
			"box", "compound_boxes":
				shape = BoxShape3D.new(); shape.size = size
			"sphere":
				if not is_equal_approx(size.x,size.y) or not is_equal_approx(size.x,size.z): body.free(); return {"error":"球体包围盒必须等轴；不会自动放大"}
				shape = SphereShape3D.new(); shape.radius = size.x/2
			"capsule", "cylinder":
				if not is_equal_approx(size.x,size.z): body.free(); return {"error":"圆柱/胶囊 XZ 必须等径"}
				if kind == "capsule" and size.y < size.x: body.free(); return {"error":"胶囊总高必须不小于直径"}
				shape = CapsuleShape3D.new() if kind == "capsule" else CylinderShape3D.new(); shape.radius = size.x/2; shape.height = size.y
		var collision := CollisionShape3D.new(); collision.shape = shape; collision.position = part.center * scale_value; body.add_child(collision)
		volume += size.x*size.y*size.z
	var vertex_error := 0.0
	for vertex in mesh.mesh.get_faces():
		var nearest := INF
		for child in body.get_children():
			var point: Vector3 = vertex*scale_value-child.position
			var shape: Shape3D = child.shape
			var signed_distance := 0.0
			if shape is BoxShape3D:
				var q: Vector3 = point.abs()-shape.size/2
				signed_distance = q.max(Vector3.ZERO).length()+minf(maxf(q.x,maxf(q.y,q.z)),0)
			elif shape is SphereShape3D: signed_distance = point.length()-shape.radius
			elif shape is CapsuleShape3D:
				point.y -= clampf(point.y,-(shape.height/2-shape.radius),shape.height/2-shape.radius); signed_distance = point.length()-shape.radius
			elif shape is CylinderShape3D:
				var q := Vector2(Vector2(point.x,point.z).length()-shape.radius,absf(point.y)-shape.height/2)
				signed_distance = q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0)
			nearest = minf(nearest,absf(signed_distance))
		vertex_error = maxf(vertex_error,nearest)
	body.set_meta("vertex_error_m",vertex_error)
	body.set_meta("strategy", kind)
	body.set_meta("error_metric", {"metric":"sum primitive AABB volume / visual AABB volume (not geometric accuracy)","ratio":volume/maxf(0.0000001,bounds.get_volume()*scale_value.x*scale_value.y*scale_value.z),"physical_validation":"待实际接触/通行测试"})
	return {"error":"", "body":body}

static func wireframe(body: StaticBody3D) -> MeshInstance3D:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
	for child in body.get_children():
		if not child is CollisionShape3D: continue
		# Shape debug mesh uses lines; obtain its arrays directly.
		var debug: ArrayMesh = child.shape.get_debug_mesh()
		for i in debug.get_surface_count():
			var arrays: Array = debug.surface_get_arrays(i)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if indices.is_empty():
				for point in points: surface.add_vertex(child.transform * point)
			else:
				for index in indices: surface.add_vertex(child.transform * points[index])
	var result := MeshInstance3D.new(); result.mesh = surface.commit(); result.transform = body.transform
	var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(1,.65,.05); material.no_depth_test = true
	result.material_override = material
	return result
