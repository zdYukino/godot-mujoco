extends SceneTree
const Xml = preload("author_xml.gd")
const Author = preload("author_resource.gd")
const Collision = preload("collision_settings.gd")
const Artifact = preload("editor_artifact.gd")
var request: Dictionary
var source_files := {}
var verified_preview_files := {}
var repaired_preview_paths: Array = []

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
	if request.get("op","")=="import_design":
		var source_path: String=request.source
		if not FileAccess.file_exists(source_path) or FileAccess.get_sha256(source_path)!=request.get("source_sha256",""): return {"success":false,"error":"Source package changed while importing"}
		var source_error: String = preload("asset_files.gd").source_files(source_path, source_files)
		if not source_error.is_empty(): return {"success":false,"error":source_error}
		for file in source_files: source_files[file] = FileAccess.get_sha256(file)
		var copied := copy_project_dependencies(design,source_path)
		if not copied.error.is_empty(): return {"success":false,"error":copied.error}
	var context: Dictionary = request.get("context",Collision.context(null,design))
	var source_observation := Artifact.observe_files(design.dependencies.keys())
	var dependency_error := stable_dependencies(design, source_observation)
	if not dependency_error.is_empty(): return {"success":false, "error":dependency_error}
	var stamp: Dictionary = request.get("editor_artifact_stamp", {})
	# Only previously qualified bytes can be reused during a producing compile.
	# File existence alone must never bless an old or replaced generated resource.
	if stamp.get("schema") == Artifact.SCHEMA and stamp.get("producer") == Artifact.producer() and stamp.get("preview_files") is Dictionary:
		for file in stamp.preview_files:
			if Artifact.project_path(file) and FileAccess.file_exists(file) and FileAccess.get_sha256(file) == stamp.preview_files[file]: verified_preview_files[file] = stamp.preview_files[file]
	var miss_reason := "compile requested"
	if request.get("op", "") == "verify_or_compile":
		var payload: Dictionary = request.get("payload", {})
		miss_reason = Artifact.candidate_reason(design.author_snapshot(), context, payload, stamp)
		if miss_reason.is_empty():
			for file in Artifact.preview_paths(payload):
				if not verified_preview_files.has(file): miss_reason = "preview resource missing or changed"; break
		if miss_reason.is_empty():
			dependency_error = stable_dependencies(design, source_observation)
			if not dependency_error.is_empty(): return {"success":false, "error":dependency_error}
			# A file can change while the other source/resource files are hashed.
			for file in verified_preview_files:
				if FileAccess.get_sha256(file) != verified_preview_files[file]:
					verified_preview_files.erase(file)
					miss_reason = "preview resource changed during verification"; break
			if miss_reason.is_empty():
				dependency_error = stable_dependencies(design, source_observation)
				if not dependency_error.is_empty(): return {"success":false, "error":dependency_error}
				return qualification(design, context, stamp, "hit", "")
	var inputs := snapshot_dependencies(design)
	if not inputs.error.is_empty(): return {"success":false, "error":inputs.error}
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.compile_author(design.worker_xml(context.collision_options, inputs.paths), design.native_initial_pose(), design.native_mesh_options(), design.native_initial_controls()):
		return {"success":false, "error":document.get_error(), "author":design.author_snapshot()}
	dependency_error = stable_dependencies(design, source_observation)
	if not dependency_error.is_empty(): return {"success":false, "error":dependency_error}
	if request.get("op") == "capture_preset":
		var value: Dictionary = preload("res://addons/mujoco_editor/control_presets.gd").capture(document)
		return {"success":not value.has("error"), "error":value.get("error", ""), "preset":value}
	if request.get("op") == "preset":
		var candidate: Dictionary = document.preset_candidate(request.get("preset", {}))
		if not candidate.get("error", "").is_empty(): return {"success":false, "error":candidate.error}
		var kinds := {}
		for entity in document.inspect().entities:
			if entity.kind == "actuator": kinds[entity.name] = entity.properties.type
		return {"success":true, "error":"", "drives":request.preset.drives.duplicate(true), "kinds":kinds}
	var stats: Array = document.collision_stats()
	var error := Collision.validate_stats(stats,context.limits)
	if not error.is_empty(): return {"success":false,"error":error,"author":design.author_snapshot()}
	var path: String = request.directory.path_join("model.mjb")
	if not document.save_compiled(path): return {"success":false, "error":"Cannot write compiled model"}
	var description: Dictionary = document.inspect()
	var geometry: Array = document.geometry()
	error = Collision.validate_geometry(geometry,description.entities,context.limits)
	if not error.is_empty(): return {"success":false,"error":error,"author":design.author_snapshot()}
	var geometry_error := cache_visual_meshes(geometry)
	if not geometry_error.is_empty(): return {"success":false, "error":geometry_error}
	var collision_geometry: Array = document.collision_preview(.33,65)
	var boundaries := collision_geometry.filter(func(g): return g.get("preview_kind", "") in ["compiled_convex_hull", "analytic_boundary"])
	geometry_error = cache_visual_meshes(boundaries)
	if not geometry_error.is_empty(): return {"success":false, "error":geometry_error}
	var result := {"snapshot":design.portable_snapshot(document.snapshot()), "entities":description.entities, "geometry":geometry, "collision_geometry":collision_geometry, "collision_stats":stats, "compiled_path":path, "mujoco_version":description.version, "repaired_preview_paths":repaired_preview_paths}
	var payload := Artifact.result_payload(result)
	if not Artifact.payload_complete(payload): return {"success":false, "error":"Compiler produced an incomplete portable preview"}
	var files := {}
	for file in Artifact.preview_paths(payload):
		if not FileAccess.file_exists(file): return {"success":false, "error":"Generated preview disappeared: " + str(file)}
		files[file] = FileAccess.get_sha256(file)
		if verified_preview_files.get(file) != files[file]: return {"success":false, "error":"Generated preview changed during publication: " + str(file)}
	dependency_error = stable_dependencies(design, source_observation)
	if not dependency_error.is_empty(): return {"success":false, "error":dependency_error}
	result.merge(qualification(design, context, Artifact.make_stamp(design.author_snapshot(), context, payload, files), "compiled", miss_reason))
	return result

func stable_dependencies(design: Resource, observation: Dictionary) -> String:
	var error: String = design.validate_dependencies()
	if not error.is_empty(): return error
	if Artifact.observe_files(design.dependencies.keys()) != observation: return "Author dependency changed during validation"
	for file in source_files:
		if not FileAccess.file_exists(file) or FileAccess.get_sha256(file) != source_files[file]: return "Source/include changed during import: " + str(file)
	return ""

func snapshot_dependencies(design: Resource) -> Dictionary:
	# Native compilation reads immutable, operation-private verified bytes. An
	# external A->B->A source race cannot make it consume B between two hashes of
	# A. These paths never enter saved payloads or runtime authoritative requests.
	var paths := {}
	if design.dependencies.is_empty(): return {"error":"", "paths":paths}
	var directory: String = request.directory.path_join("dependencies")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"error":"Cannot snapshot author dependencies"}
	for path in design.dependencies:
		var target := directory.path_join(str(design.dependencies[path]) + "." + str(path).get_extension())
		if DirAccess.copy_absolute(path, target) != OK or FileAccess.get_sha256(target) != design.dependencies[path]: return {"error":"Author dependency changed while snapshotting: " + str(path)}
		paths[path] = target
	return {"error":"", "paths":paths}

func qualification(design: Resource, context: Dictionary, stamp: Dictionary, kind: String, reason: String) -> Dictionary:
	var paths: Array = design.dependencies.keys()
	for path in stamp.preview_files:
		if not paths.has(path): paths.append(path)
	var result := {"success":true, "error":"", "artifact_kind":kind, "cache_miss_reason":reason, "author_digest":stamp.author_digest, "context_digest":stamp.context_digest, "editor_artifact_stamp":stamp, "file_observation":Artifact.observe_files(paths), "context":Collision.signature(context)}
	if kind == "compiled": result.author = design.author_snapshot()
	return result

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
			var texture_hash := Artifact.digest([Artifact.producer(), data])
			var texture_path := directory.path_join(texture_hash + ".res")
			if not verified_preview_files.has(texture_path):
				var texture: Texture2D = visual.texture(data)
				var temporary := directory.path_join("." + texture_hash + "_" + str(hash(request.directory)) + ".tmp.res")
				if not texture or ResourceSaver.save(texture, temporary, ResourceSaver.FLAG_COMPRESS) != OK: return "Cannot cache visual texture"
				if ResourceSaver.set_uid(temporary, texture_hash.left(15).hex_to_int()) != OK or DirAccess.rename_absolute(temporary, texture_path) != OK: return "Cannot publish visual texture"
				verified_preview_files[texture_path] = FileAccess.get_sha256(texture_path)
				repaired_preview_paths.append(texture_path)
			geom.texture_path = texture_path
			geom.texture_alpha = data.channels == 4
		var fingerprint := Artifact.digest([Artifact.producer(), geom.type, geom.size, geom.get("source_size", geom.size), geom.get("vertices", []), geom.get("normals", []), geom.get("uvs", []), geom.has("texture_path"), geom.get("texture_uniform", false)])
		var path := directory.path_join(fingerprint + ".res")
		if not verified_preview_files.has(path):
			var instance: MeshInstance3D = visual.create(geom)
			if not instance: return "Cannot create visual geometry: " + str(geom.name)
			var temporary := directory.path_join("." + fingerprint + "_" + str(hash(request.directory)) + ".tmp.res")
			var error := ResourceSaver.save(instance.mesh, temporary, ResourceSaver.FLAG_COMPRESS)
			instance.free()
			if error != OK: return "Cannot save visual mesh"
			if ResourceSaver.set_uid(temporary, fingerprint.left(15).hex_to_int()) != OK: return "Cannot assign visual asset identity"
			if DirAccess.rename_absolute(temporary, path) != OK: return "Cannot publish visual asset"
			verified_preview_files[path] = FileAccess.get_sha256(path)
			repaired_preview_paths.append(path)
		geom.mesh_path = path
		geom.erase("vertices")
		geom.erase("normals")
		geom.erase("uvs")
		geom.erase("texture_image")
	return ""

func compile_world() -> Dictionary:
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.compose_author_world(request): return {"success":false, "error":document.get_error()}
	var stats: Array = document.collision_stats()
	var budget: Dictionary = request.get("limits",Collision.limits())
	var error := Collision.validate_stats(stats,budget)
	if not error.is_empty(): return {"success":false,"error":error}
	if not stats.is_empty():
		error = Collision.validate_geometry(document.geometry(),document.inspect().entities,budget)
		if not error.is_empty(): return {"success":false,"error":error}
	var path: String = request.directory.path_join("world.mjb")
	if not document.save_compiled(path): return {"success":false, "error":"Cannot write compiled world"}
	return {"success":true, "error":"", "snapshot":document.snapshot(), "collision_stats":stats, "compiled_path":path, "aliases":request.get("aliases", {}), "reset":request.get("reset", {})}

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
