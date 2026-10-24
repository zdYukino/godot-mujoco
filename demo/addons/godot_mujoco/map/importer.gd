@tool
extends RefCounted
## External input is read-only. Every successful result owns an unattached Node3D.
const LIMIT := 2000000
var diagnostics: Array = []
var dependencies: Array = []
var source_hashes: Dictionary = {}
var error := ""

func fail(message: String) -> Node3D:
	error = message
	return null

func track(path: String, required := true) -> bool:
	if not dependencies.has(path): dependencies.append(path)
	if not FileAccess.file_exists(path):
		source_hashes[path] = "missing"
		diagnostics.append("缺依赖: " + path)
		if required: error = "缺依赖: " + path
		return false
	source_hashes[path] = FileAccess.get_sha256(path)
	return true

func import_file(path: String, unit: String, axes: String) -> Node3D:
	error = ""; diagnostics = []; dependencies = []; source_hashes = {}
	if not unit in ["m", "cm", "mm"]: return fail("未知单位：必须显式选择 m / cm / mm")
	if not axes in ["Y_UP", "Z_UP"]: return fail("必须选择右手 Y_UP 或右手 Z_UP；左手输入暂不支持")
	if not track(path): return null
	var result: Node3D
	match path.get_extension().to_lower():
		"glb", "gltf": result = _gltf(path)
		"obj": result = _obj(path)
		"stl": result = _stl(path)
		_: return fail("不支持的静态几何格式: " + path.get_extension())
	if not result: return null
	for dependency in source_hashes:
		var current := FileAccess.get_sha256(dependency) if FileAccess.file_exists(dependency) else "missing"
		if current != source_hashes[dependency]: result.free(); return fail("导入期间来源变化；旧地图保留: " + dependency)
	var root := Node3D.new(); root.name = "Map"
	var conversion := Node3D.new(); conversion.name = "SourceCoordinates"
	var scale_value: float = {"m":1.0, "cm":0.01, "mm":0.001}[unit]
	conversion.transform = Transform3D(Basis(Vector3.RIGHT, -PI/2) if axes == "Z_UP" else Basis.IDENTITY, Vector3.ZERO).scaled(Vector3.ONE * scale_value)
	root.add_child(conversion); conversion.add_child(result)
	root.set_meta("contract", {"version":1,"source":path,"unit":unit,"axes":axes,"metres_per_unit":scale_value,"target":"right-handed Y-up metres", "conversion":conversion.transform})
	root.set_meta("diagnostics", diagnostics)
	_owners(root, root)
	return root

static func _owners(node: Node, root: Node) -> void:
	for child in node.get_children(): child.owner = root; _owners(child, root)

func _gltf(path: String) -> Node3D:
	var data: Variant
	if path.get_extension().to_lower() == "gltf": data = JSON.parse_string(FileAccess.get_file_as_string(path))
	else:
		var f := FileAccess.open(path, FileAccess.READ)
		if not f or f.get_length() < 20: return fail("GLB 文件头截断")
		if f.get_32() != 0x46546c67 or f.get_32() != 2: return fail("仅支持 GLB 2")
		if f.get_32() != f.get_length(): return fail("GLB 长度不匹配")
		var size := f.get_32()
		if f.get_32() != 0x4e4f534a or size > f.get_length()-20: return fail("GLB JSON 块无效")
		data = JSON.parse_string(f.get_buffer(size).get_string_from_utf8())
	if not data is Dictionary: return fail("glTF JSON 无效")
	if not data.get("skins", []).is_empty(): return fail("静态导入不支持蒙皮；请导出静态网格")
	for node in data.get("nodes", []):
		if node.has("weights"): return fail("静态导入不支持 morph weights")
	for mesh in data.get("meshes", []):
		for primitive in mesh.get("primitives", []):
			if primitive.has("targets"): return fail("静态导入不支持 morph targets")
	if not data.get("animations", []).is_empty(): diagnostics.append("动画不导入；保留静态初始变换")
	for collection in ["buffers", "images"]:
		for item in data.get(collection, []):
			var uri: String = item.get("uri", "")
			if uri.is_empty() or uri.begins_with("data:"): continue
			if uri.contains(":") or uri.is_absolute_path(): return fail("拒绝非本地相对 glTF URI: " + uri)
			if not track(path.get_base_dir().path_join(uri.uri_decode()).simplify_path()): return null
	var document := GLTFDocument.new(); var state := GLTFState.new()
	if document.append_from_file(path, state) != OK: return fail("glTF 解析失败；旧地图保持不动")
	var result := document.generate_scene(state)
	if not result: return fail("glTF 场景生成失败")
	_clear_import_owners(result)
	result = _bake_importer_meshes(result)
	_strip_nonvisual(result)
	return result

func _clear_import_owners(node: Node) -> void:
	# Reparenting editor-generated ImporterMesh nodes must not retain owners from
	# the temporary glTF scene. Normalize once, after conversion, in _owners.
	node.owner = null
	for child in node.get_children(): _clear_import_owners(child)

func _bake_importer_meshes(node: Node3D) -> Node3D:
	# Godot's editor generates ImporterMeshInstance3D; runtime generates MeshInstance3D.
	if node is ImporterMeshInstance3D:
		var replacement := MeshInstance3D.new(); replacement.name = node.name; replacement.transform = node.transform
		if node.mesh: replacement.mesh = node.mesh.get_mesh()
		for child in node.get_children(): node.remove_child(child); replacement.add_child(child)
		node.free(); node = replacement
	for child in node.get_children():
		if not child is Node3D: continue
		var index := child.get_index(); node.remove_child(child)
		var baked := _bake_importer_meshes(child); node.add_child(baked); node.move_child(baked,index)
	return node

func _strip_nonvisual(node: Node) -> void:
	for child in node.get_children():
		if child is AnimationPlayer or child is Camera3D or child is Light3D:
			diagnostics.append("静态查看器忽略节点: " + str(child.name)); child.free()
		else: _strip_nonvisual(child)

func _mesh(vertices: PackedVector3Array, uv: PackedVector2Array = PackedVector2Array(), normals: PackedVector3Array = PackedVector3Array()) -> ArrayMesh:
	if vertices.is_empty() or vertices.size() % 3 != 0: return null
	var tool := SurfaceTool.new(); tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in vertices.size():
		if not vertices[i].is_finite(): return null
		if uv.size() == vertices.size(): tool.set_uv(uv[i])
		if normals.size() == vertices.size(): tool.set_normal(normals[i])
		tool.add_vertex(vertices[i])
	if normals.size() != vertices.size(): tool.generate_normals()
	return tool.commit()

func _stl(path: String) -> Node3D:
	var bytes := FileAccess.get_file_as_bytes(path); var vertices := PackedVector3Array()
	if bytes.size() >= 84 and 84 + bytes.decode_u32(80) * 50 == bytes.size():
		var count := bytes.decode_u32(80)
		if count == 0 or count*3 > LIMIT: return fail("STL 三角形数无效或超出轻量上限")
		for t in count:
			var face := []
			for j in 3:
				var offset := 84 + t*50 + 12 + j*12
				face.append(Vector3(bytes.decode_float(offset), bytes.decode_float(offset+4), bytes.decode_float(offset+8)))
			vertices.append_array(PackedVector3Array([face[0], face[2], face[1]]))
	else:
		var text := bytes.get_string_from_utf8()
		if not text.strip_edges().begins_with("solid") or not text.contains("endsolid"): return fail("STL 二进制长度或 ASCII 结构无效")
		var face := []; var inside := false
		for line in text.split("\n"):
			var parts := line.strip_edges().replace("\t", " ").split(" ", false)
			if parts.is_empty(): continue
			if parts[0] == "facet":
				if inside: return fail("STL facet 嵌套无效")
				inside = true; face = []
			elif parts[0] == "vertex":
				if not inside or parts.size() != 4: return fail("STL vertex 无效")
				for v in parts.slice(1):
					if not v.is_valid_float(): return fail("STL 非数值坐标")
				face.append(Vector3(float(parts[1]),float(parts[2]),float(parts[3])))
			elif parts[0] == "endfacet":
				if not inside or face.size() != 3: return fail("STL facet 必须有三个顶点")
				vertices.append_array(PackedVector3Array([face[0],face[2],face[1]])); inside = false
			if vertices.size() > LIMIT: return fail("STL 超出轻量顶点上限")
		if inside: return fail("STL facet 截断")
	var mesh := _mesh(vertices)
	if not mesh: return fail("STL 无有效有限三角形")
	var result := MeshInstance3D.new(); result.name = "STLGeometry"; result.mesh = mesh
	diagnostics.append("STL 显式几何适配器：无单位、层级、材质或纹理语义")
	return result

func _mtl(path: String, materials: Dictionary) -> void:
	if not track(path, false): return
	var material: StandardMaterial3D
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var parts := line.strip_edges().replace("\t", " ").split(" ", false)
		if parts.is_empty() or parts[0].begins_with("#"): continue
		match parts[0]:
			"newmtl":
				if parts.size() < 2: continue
				material = StandardMaterial3D.new(); material.resource_name = parts[1]; materials[parts[1]] = material
			"Kd":
				if material and parts.size() == 4: material.albedo_color = Color(float(parts[1]),float(parts[2]),float(parts[3]))
			"map_Kd":
				if not material: continue
				if parts.size() != 2 or parts[1].begins_with("-"): diagnostics.append("MTL map_Kd 选项/带空格路径暂不支持: " + line); continue
				var texture_path := path.get_base_dir().path_join(parts[1]).simplify_path()
				if track(texture_path, false):
					var image := Image.load_from_file(texture_path)
					if image: material.albedo_texture = ImageTexture.create_from_image(image)
					else: diagnostics.append("无法解码纹理: " + texture_path)
			"Ns", "Ka", "Ks", "illum", "d", "Tr", "map_Bump", "bump": diagnostics.append("MTL 未支持属性: " + parts[0])

func _obj(path: String) -> Node3D:
	var positions := []; var texcoords := []; var normals := []; var materials := {}; var groups := {}
	var group := "Object"; var material := ""; var emitted := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var parts := line.split("#")[0].strip_edges().replace("\t", " ").split(" ", false)
		if parts.is_empty(): continue
		match parts[0]:
			"v", "vt", "vn":
				var count := 3 if parts[0] != "vt" else 2
				if parts.size() != count+1: return fail("OBJ 坐标分量数不支持: " + line)
				for token in parts.slice(1):
					if not token.is_valid_float() or not is_finite(float(token)): return fail("OBJ 非有限坐标")
				if parts[0] == "v": positions.append(Vector3(float(parts[1]),float(parts[2]),float(parts[3])))
				elif parts[0] == "vn": normals.append(Vector3(float(parts[1]),float(parts[2]),float(parts[3])))
				else: texcoords.append(Vector2(float(parts[1]),1.0-float(parts[2])))
			"mtllib":
				for file in parts.slice(1): _mtl(path.get_base_dir().path_join(file).simplify_path(), materials)
			"o", "g": group = "_".join(parts.slice(1)).validate_node_name()
			"usemtl": material = parts[1] if parts.size() > 1 else ""
			"f":
				# Deliberately require triangulated OBJ: fan triangulation is wrong for concave n-gons.
				if parts.size() != 4: return fail("OBJ 仅支持三角面；请先三角化，拒绝猜测凹多边形")
				var key := group + "|" + material
				if not groups.has(key): groups[key] = {"name":group,"material":material,"v":PackedVector3Array(),"uv":PackedVector2Array(),"n":PackedVector3Array()}
				for corner in [parts[1],parts[3],parts[2]]:
					var indices: PackedStringArray = corner.split("/", true)
					if indices.size() > 3: return fail("OBJ 顶点索引无效")
					for i in indices.size():
						if indices[i].is_empty() and i > 0: continue
						if not indices[i].is_valid_int(): return fail("OBJ 索引不是整数")
						var collection: Array = [positions,texcoords,normals][i]
						var index := int(indices[i]); index = index-1 if index > 0 else collection.size()+index
						if int(indices[i]) == 0 or index < 0 or index >= collection.size(): return fail("OBJ 索引越界")
						groups[key][["v","uv","n"][i]].append(collection[index])
					emitted += 1
					if emitted > LIMIT: return fail("OBJ 超出轻量顶点上限")
			"s": pass
			_: diagnostics.append("OBJ 忽略属性: " + parts[0])
	if groups.is_empty(): return fail("OBJ 没有三角形")
	var root := Node3D.new(); root.name = "OBJ"
	for item in groups.values():
		if not item.uv.is_empty() and item.uv.size() != item.v.size(): diagnostics.append("OBJ 部分 UV 缺失：该对象不使用 UV")
		if not item.n.is_empty() and item.n.size() != item.v.size(): diagnostics.append("OBJ 部分法线缺失：该对象重新计算法线")
		var mesh := _mesh(item.v, item.uv, item.n)
		if not mesh: root.free(); return fail("OBJ 网格无效")
		var instance := MeshInstance3D.new(); instance.name = item.name if not item.name.is_empty() else "Object"; instance.mesh = mesh
		if materials.has(item.material): instance.material_override = materials[item.material]
		elif not item.material.is_empty(): diagnostics.append("缺材质定义: " + item.material)
		root.add_child(instance, true)
	return root
