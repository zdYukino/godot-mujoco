@tool
extends RefCounted
const Builder = preload("../model/package_builder.gd")
## Immutable, content-addressed directory; all visual resources are embedded.
static func localize(node: Node) -> String:
	if node is MeshInstance3D and node.mesh:
		var mesh := ArrayMesh.new()
		for i in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES: return "仅支持三角面视觉资源"
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,node.mesh.surface_get_arrays(i))
			var material: Material = node.get_active_material(i)
			if material:
				if not material is StandardMaterial3D: return "不支持的材质类型: " + material.get_class()
				material = material.duplicate(true)
				for slot in BaseMaterial3D.TEXTURE_MAX:
					var texture: Texture2D = material.get_texture(slot)
					if texture:
						var image := texture.get_image()
						if not image or image.is_empty(): return "材质纹理无法自包含"
						material.set_texture(slot,ImageTexture.create_from_image(image))
				material.resource_path = ""
				mesh.surface_set_material(i,material)
		node.mesh = mesh; node.material_override = null
		for i in mesh.get_surface_count(): node.set_surface_override_material(i,null)
	for child in node.get_children():
		var error := localize(child)
		if not error.is_empty(): return error
	return ""

static func validate(path: String) -> String:
	if not FileAccess.file_exists(path.path_join("manifest.json")): return "地图 manifest 缺失"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("manifest.json")))
	if not manifest is Dictionary or manifest.get("version") != 1 or not manifest.get("files") is Dictionary: return "地图 manifest 缺失/无效"
	if not manifest.files.has("map.tscn"): return "manifest 未列出 map.tscn"
	for relative in manifest.files:
		if not relative is String or relative.contains("..") or relative.contains(":") or relative.contains("\\") or relative.begins_with("/"): return "非法包相对路径"
		var file := path.path_join(relative)
		if not FileAccess.file_exists(file): return "缺少地图依赖: " + relative
		if FileAccess.get_sha256(file) != manifest.files[relative]: return "地图依赖哈希不匹配: " + relative
	var scene_path := path.path_join("map.tscn")
	var text := FileAccess.get_file_as_string(scene_path)
	# Inspect text dependencies and required direct children before loading resources.
	# Native packages contain only installed addon scripts as external resources.
	if text.contains("script/source =") or text.contains('[sub_resource type="GDScript"'):
		return "地图包不接受内联脚本"
	var allowed := ["res://addons/godot_mujoco/map/map_root.gd","res://addons/godot_mujoco/map/map_camera.gd","res://addons/godot_mujoco/model/static_heightfield.gd","res://addons/godot_mujoco/model/heightfield_data.gd"]
	var attribute := RegEx.new(); attribute.compile('([a-z_]+)="([^"]*)"')
	var required := {"Visual":false,"Physics":false}; var roots := 0
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if not line.begins_with("[ext_resource ") and not line.begins_with("[node "): continue
		var fields := {}
		for match_value in attribute.search_all(line): fields[match_value.get_string(1)] = match_value.get_string(2)
		if line.begins_with("[ext_resource "):
			var dependency: String = fields.get("path","")
			if fields.get("type") != "Script" or dependency not in allowed: return "地图场景含未支持的外部依赖: " + dependency
			if not FileAccess.file_exists(dependency): return "缺少实际场景依赖: " + dependency
		else:
			if not fields.has("parent"):
				roots += 1
				if fields.get("type") != "Node3D": return "地图根节点必须是 Node3D"
			elif fields.parent == "." and required.has(fields.get("name")):
				if fields.get("type") != "Node3D": return "地图 Visual/Physics 节点必须是 Node3D"
				required[fields.name] = true
	if roots != 1 or not required.Visual or not required.Physics: return "地图结构缺少唯一根节点、Visual 或 Physics"
	return ""

static func pack(session: RefCounted, parent: String) -> Dictionary:
	if not parent.begins_with("res://") or parent.contains(".."): return {"error":"地图包必须保存到项目内 res:// 目录"}
	var built: Dictionary = session.build_scene()
	if not built.error.is_empty(): return built
	var scene: Node3D = built.scene
	var error := localize(scene)
	if not error.is_empty(): scene.free(); return {"error":error}
	var stage := parent.path_join(".staging_" + str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(stage) != OK: scene.free(); return {"error":"无法创建暂存目录"}
	var packed := PackedScene.new()
	var status := packed.pack(scene); scene.free()
	if status != OK: return Builder.failure(stage,"地图场景打包失败")
	if ResourceSaver.save(packed,stage.path_join("map.tscn")) != OK: return Builder.failure(stage,"地图保存失败")
	# Reject accidental source/runtime references; scripts are the installed addon only.
	var deps := ResourceLoader.get_dependencies(stage.path_join("map.tscn"))
	for dependency in deps:
		var path: String = dependency.split("::")[-1]
		if not path.begins_with("res://addons/godot_mujoco/"): return Builder.failure(stage,"包仍有外部依赖: " + path)
	var manifest := {"version":1,"backend":"MuJoCo 3.16.0 native primitives and fixed-spacing heightfields","engine":"Godot 4.7.2 .NET","files":{"map.tscn":FileAccess.get_sha256(stage.path_join("map.tscn"))},"sources":session.watch.hashes,"units":session.unit,"axes":session.axes,"diagnostics":session.diagnostics,"physical_readiness":"authored collision; independently verify traversal/contact","requires_addon":"godot_mujoco"}
	var file := FileAccess.open(stage.path_join("manifest.json"),FileAccess.WRITE)
	if not file: return Builder.failure(stage,"manifest 写入失败")
	file.store_string(JSON.stringify(manifest,"\t",true,true)); file.close()
	error = validate(stage)
	if not error.is_empty(): return Builder.failure(stage,error)
	var reloaded := ResourceLoader.load(stage.path_join("map.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not reloaded: return Builder.failure(stage,"暂存场景重开失败")
	var instance := reloaded.instantiate()
	if not instance: return Builder.failure(stage,"暂存场景实例化失败")
	instance.free()
	var destination := parent.path_join("map_" + FileAccess.get_sha256(stage.path_join("manifest.json")))
	if DirAccess.dir_exists_absolute(destination):
		error = validate(destination)
		if not error.is_empty(): return Builder.failure(stage,error)
		Builder.remove_staging(stage)
	elif DirAccess.rename_absolute(stage,destination) != OK: return Builder.failure(stage,"地图包原子发布失败")
	session.dirty = false; session.watch.exported_hash = FileAccess.get_sha256(destination.path_join("manifest.json"))
	return {"error":"", "path":destination}
