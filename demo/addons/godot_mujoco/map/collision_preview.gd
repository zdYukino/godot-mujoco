@tool
extends RefCounted
## Display only compiled collision geometry or a labelled native distance slice.
static func material(color: Color, vertex_colors := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.albedo_color = color; result.no_depth_test = true
	result.vertex_color_use_as_albedo = vertex_colors
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return result

static func create(geometries: Array, pose: Transform3D) -> Node3D:
	var root := Node3D.new(); root.transform = pose
	for geom in geometries:
		if geom.preview_kind == "native_sdf_distance_slice":
			var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			var n: int = geom.slice_resolution
			for z in n-1:
				for x in n-1:
					var a := z*n+x
					for i in [a,a+n+1,a+1,a,a+n,a+n+1]:
						surface.set_color(Color(1,.15,.1,.45) if geom.slice_distances[i]<0 else Color(.1,.35,1,.25))
						surface.add_vertex(geom.slice_points[i])
			var field := MeshInstance3D.new(); field.mesh=surface.commit(); field.material_override=material(Color.WHITE,true); root.add_child(field)
			if not geom.slice_contour.is_empty():
				var lines := SurfaceTool.new(); lines.begin(Mesh.PRIMITIVE_LINES)
				for point in geom.slice_contour: lines.add_vertex(point)
				var contour := MeshInstance3D.new(); contour.mesh=lines.commit(); contour.material_override=material(Color(1,1,0)); root.add_child(contour)
		elif geom.preview_kind in ["compiled_convex_hull","analytic_boundary"]:
			var instance := preload("../model/model_visual.gd").create(geom)
			if instance:
				instance.material_override=material(Color(1,.65,.05,.4)); root.add_child(instance)
	return root
