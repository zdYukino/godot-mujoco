extends SceneTree
const Xml = preload("author_xml.gd")
const Author = preload("author_resource.gd")
var request: Dictionary
var source_files := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1:
		quit(2)
		return
	var input := FileAccess.open(arguments[0].path_join("request.bin"), FileAccess.READ)
	if not input:
		quit(2)
		return
	var value: Variant = input.get_var(false)
	if not value is Dictionary:
		quit(2)
		return
	request = value
	var result := compile_request()
	var temporary: String = request.directory.path_join("result.tmp")
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if not output:
		quit(2)
		return
	output.store_var(result)
	output.close()
	DirAccess.rename_absolute(temporary, request.directory.path_join("result.bin"))
	quit(0)

func compile_request() -> Dictionary:
	if request.get("op", "") == "world": return compile_world()
	if request.get("op", "") == "mesh_asset": return copy_mesh_asset()
	var design := Author.new()
	if request.get("op", "compile") == "import":
		var imported := import_source(request.get("source", ""))
		if not imported.error.is_empty(): return {"success":false, "error":imported.error}
		design = imported.design
	else:
		var error: String = design.restore_author(request.get("author", {}))
		if not error.is_empty(): return {"success":false, "error":error}
	if request.get("op","")=="import_author":
		var source_path: String=request.source
		if not FileAccess.file_exists(source_path) or FileAccess.get_sha256(source_path)!=request.get("source_sha256",""): return {"success":false,"error":"Source package changed while importing"}
		source_files[source_path]=request.source_sha256
		var copied := copy_project_dependencies(design,source_path)
		if not copied.error.is_empty(): return {"success":false,"error":copied.error}
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.compile_author(design.worker_xml(), design.native_initial_pose()):
		return {"success":false, "error":document.get_error(), "author":design.author_snapshot()}
	var path: String = request.directory.path_join("model.mjb")
	if not document.save_compiled(path): return {"success":false, "error":"Cannot write compiled model"}
	var description: Dictionary = document.inspect()
	var geometry: Array = document.geometry()
	var geometry_error := cache_visual_meshes(geometry)
	if not geometry_error.is_empty(): return {"success":false, "error":geometry_error}
	var collision_geometry: Array = document.collision_preview(.33,65)
	var boundaries := collision_geometry.filter(func(g): return g.get("preview_kind", "") in ["compiled_convex_hull", "analytic_boundary"])
	geometry_error = cache_visual_meshes(boundaries)
	if not geometry_error.is_empty(): return {"success":false, "error":geometry_error}
	return {"success":true, "error":"", "author":design.author_snapshot(), "snapshot":document.snapshot(), "entities":description.entities, "geometry":geometry, "collision_geometry":collision_geometry, "compiled_path":path, "mujoco_version":description.version}

func copy_mesh_asset() -> Dictionary:
	var path: String = request.source
	if not FileAccess.file_exists(path): return {"success":false,"error":"Missing mesh asset"}
	var digest := FileAccess.get_sha256(path)
	var folder: String = "res://mujoco_models/" + str(request.document_id) + "/assets"
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return {"success":false,"error":"Cannot create mesh folder"}
	var target := folder.path_join(digest + "." + path.get_extension())
	if DirAccess.copy_absolute(path,target) != OK or FileAccess.get_sha256(target) != digest: return {"success":false,"error":"Mesh changed during copy"}
	return {"success":true,"error":"","path":target,"sha256":digest}

func cache_visual_meshes(geometry: Array) -> String:
	var directory := "res://mujoco_models/visual_cache"
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Cannot create project visual asset cache"
	var visual = load("res://addons/godot_mujoco/model/model_visual.gd")
	for geom in geometry:
		if geom.has("texture_image"):
			var data: Dictionary = geom.texture_image
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(var_to_bytes(data))
			var texture_hash := digest.finish().hex_encode()
			var texture_path := directory.path_join(texture_hash + ".res")
			if not FileAccess.file_exists(texture_path):
				var texture: Texture2D = visual.texture(data)
				var temporary := directory.path_join("." + texture_hash + "_" + str(hash(request.directory)) + ".tmp.res")
				if not texture or ResourceSaver.save(texture, temporary, ResourceSaver.FLAG_COMPRESS) != OK: return "Cannot cache visual texture"
				if ResourceSaver.set_uid(temporary, texture_hash.left(15).hex_to_int()) != OK or DirAccess.rename_absolute(temporary, texture_path) != OK: return "Cannot publish visual texture"
			geom.texture_path = texture_path
			geom.texture_alpha = data.channels == 4
		var hasher := HashingContext.new()
		hasher.start(HashingContext.HASH_SHA256)
		hasher.update(var_to_bytes([Engine.get_version_info().hash, geom.type, geom.size, geom.get("vertices", []), geom.get("normals", []), geom.get("uvs", []), geom.has("texture_path"), geom.get("texture_uniform", false)]))
		var fingerprint := hasher.finish().hex_encode()
		var path := directory.path_join(fingerprint + ".res")
		if not FileAccess.file_exists(path):
			var instance: MeshInstance3D = visual.create(geom)
			if not instance: return "Cannot create visual geometry: " + str(geom.name)
			var temporary := directory.path_join("." + fingerprint + "_" + str(hash(request.directory)) + ".tmp.res")
			var error := ResourceSaver.save(instance.mesh, temporary, ResourceSaver.FLAG_COMPRESS)
			instance.free()
			if error != OK: return "Cannot save visual mesh"
			if ResourceSaver.set_uid(temporary, fingerprint.left(15).hex_to_int()) != OK: return "Cannot assign visual asset identity"
			if DirAccess.rename_absolute(temporary, path) != OK: return "Cannot publish visual asset"
		geom.mesh_path = path
		geom.erase("vertices")
		geom.erase("normals")
		geom.erase("uvs")
		geom.erase("texture_image")
	return ""

func compile_world() -> Dictionary:
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.compose_author_world(request): return {"success":false, "error":document.get_error()}
	var path: String = request.directory.path_join("world.mjb")
	if not document.save_compiled(path): return {"success":false, "error":"Cannot write compiled world"}
	return {"success":true, "error":"", "snapshot":document.snapshot(), "compiled_path":path, "aliases":request.get("aliases", {}), "reset":request.get("reset", {})}

func expand_includes(tree: Dictionary, directory: String, visited: Dictionary) -> String:
	for child in tree.get("children", []).duplicate():
		if child.tag == "include":
			var path: String = directory.path_join(child.attrs.get("file", "")).simplify_path()
			if visited.has(path): return "Cyclic include: " + path
			if not FileAccess.file_exists(path): return "Missing include: " + path
			source_files[path] = FileAccess.get_sha256(path)
			var parsed := Xml.parse(FileAccess.get_file_as_string(path))
			if not parsed.error.is_empty(): return parsed.error
			visited[path] = true
			var error := expand_includes(parsed.tree, path.get_base_dir(), visited)
			visited.erase(path)
			if not error.is_empty(): return error
			var index: int = tree.children.find(child)
			tree.children.remove_at(index)
			for element in parsed.tree.children:
				tree.children.insert(index, element)
				index += 1
		else:
			var error := expand_includes(child, directory, visited)
			if not error.is_empty(): return error
	return ""

func import_source(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"error":"Missing MJCF source: " + path}
	source_files[path] = FileAccess.get_sha256(path)
	var text := FileAccess.get_file_as_string(path)
	var parsed := Author.from_xml(text)
	if not parsed.error.is_empty(): return parsed
	var design: Resource = parsed.design
	var error := expand_includes(design.tree, path.get_base_dir(), {path:true})
	if not error.is_empty(): return {"error":error}
	Xml.ensure_names(design.tree)
	design.normalize_geometries()
	return copy_project_dependencies(design,path)

func copy_project_dependencies(design: Resource, path: String) -> Dictionary:
	var compiler: Dictionary = Xml.section(design.tree, "compiler", true).attrs
	var parent: String = "res://mujoco_models/" + path.get_file().get_basename().validate_filename() + "_" + design.document_id.left(12)
	if DirAccess.make_dir_recursive_absolute(parent.path_join("assets")) != OK: return {"error":"Cannot create project asset folder"}
	var files := {}
	design.dependencies.clear()
	for element in Xml.walk(design.tree):
		for key in element.get("attrs", {}):
			if key not in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"]: continue
			var original: String = element.attrs[key]
			if original.is_empty(): continue
			var asset_dir: String = compiler.get("texturedir" if element.tag == "texture" else "meshdir", compiler.get("assetdir", ""))
			if compiler.get("strippath", "false") == "true": original = original.get_file()
			if not original.is_absolute_path(): original = asset_dir.path_join(original) if asset_dir.is_absolute_path() else path.get_base_dir().path_join(asset_dir).path_join(original).simplify_path()
			if not FileAccess.file_exists(original): return {"error":"Missing MJCF dependency: " + original}
			var digest := FileAccess.get_sha256(original)
			var destination: String = parent.path_join("assets/" + digest + "." + original.get_extension())
			if DirAccess.copy_absolute(original, destination) != OK: return {"error":"Cannot copy MJCF dependency"}
			if FileAccess.get_sha256(destination) != digest: return {"error":"Dependency changed while importing"}
			element.attrs[key] = destination
			design.dependencies[destination] = digest
			files[original] = digest
	for key in ["assetdir", "meshdir", "texturedir", "strippath"]: compiler.erase(key)
	DirAccess.make_dir_recursive_absolute(parent.path_join("sources"))
	var archives := {}
	for original in source_files:
		var archived: String = parent.path_join("sources/" + str(source_files[original]) + "." + str(original).get_extension())
		if DirAccess.copy_absolute(original,archived) != OK or FileAccess.get_sha256(archived) != source_files[original]: return {"error":"MJCF source/include changed while importing"}
		archives[original] = archived
	design.provenance = {"source":path, "assets":files, "source_archive":archives[path], "source_archives":archives}
	return {"error":"", "design":design}
