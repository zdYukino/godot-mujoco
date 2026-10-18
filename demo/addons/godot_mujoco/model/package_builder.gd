@tool
extends RefCounted
const ModelResource = preload("model_resource.gd")

static func remove_staging(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory:
		for name in directory.get_files():
			directory.remove(name)
		for name in directory.get_directories():
			remove_staging(path.path_join(name))
	DirAccess.remove_absolute(path)

static func failure(stage: String, error: String) -> Dictionary:
	remove_staging(stage)
	return {"error":error}

static func source_files(path: String, visited: Dictionary) -> String:
	if visited.has(path): return ""
	if not FileAccess.file_exists(path): return "Missing source include: " + path
	visited[path] = true
	var parser := XMLParser.new()
	if parser.open(path) != OK: return "Cannot read source XML: " + path
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name() == "include":
			var file := parser.get_named_attribute_value_safe("file")
			var error := source_files(file if file.is_absolute_path() else path.get_base_dir().path_join(file).simplify_path(), visited)
			if not error.is_empty(): return error
	return ""

static func pack(document: RefCounted, parent := "res://mujoco_models", label := "model", previous_provenance: Dictionary = {}) -> Dictionary:
	# Only a project-owned directory may be published. Existing immutable packages
	# are never overwritten: model-content hash handles duplicate names/imports.
	if not parent.begins_with("res://") or parent.contains(".."):
		return {"error":"Choose a directory inside this Godot project (res://)"}
	var stage := parent.path_join(".staging_" + str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(stage.path_join("assets")) != OK:
		return {"error":"Cannot create package staging directory"}
	var manifest: Dictionary = document.asset_manifest()
	var mapping := {}
	var hashes := {}
	var provenance := previous_provenance.duplicate(true)
	provenance["source"] = document.snapshot().source
	provenance["assets"] = provenance.get("assets", {})
	for original in manifest.assets:
		if not FileAccess.file_exists(original):
			return failure(stage, "Missing source dependency: " + original)
		var hash := FileAccess.get_sha256(original)
		var relative: String = "assets/" + hash + "." + original.get_extension().to_lower()
		if hash.is_empty() or DirAccess.copy_absolute(original, stage.path_join(relative)) != OK:
			return failure(stage, "Cannot copy dependency: " + original)
		if FileAccess.get_sha256(stage.path_join(relative)) != hash:
			return failure(stage, "Dependency changed while copying: " + original)
		mapping[original] = relative
		hashes[relative] = hash
		provenance.assets[original] = hash
	# Includes are expanded in canonical MJCF; retain original XML/include bytes
	# separately for provenance. They are not runtime path dependencies.
	DirAccess.make_dir_recursive_absolute(stage.path_join("sources"))
	provenance["sources"] = provenance.get("sources", {})
	var sources := {}
	var original_source: String = document.snapshot().source
	if FileAccess.file_exists(original_source):
		var source_error := source_files(original_source, sources)
		if not source_error.is_empty(): return failure(stage, source_error)
	for source in sources:
		if FileAccess.file_exists(source):
			var hash := FileAccess.get_sha256(source)
			if DirAccess.copy_absolute(source, stage.path_join("sources/" + hash + ".xml")) != OK:
				return failure(stage, "Cannot preserve source: " + source)
			provenance.sources[source] = hash
	var portable: Dictionary = document.portable_snapshot(mapping)
	if portable.is_empty():
		return failure(stage, "Could not serialize portable MJCF")
	var xml_file := FileAccess.open(stage.path_join("model.xml"), FileAccess.WRITE)
	if not xml_file: return failure(stage, "Cannot write canonical MJCF")
	xml_file.store_string(portable.xml)
	xml_file.close()
	var resource := ModelResource.new()
	resource.snapshot = portable
	resource.dependencies = hashes
	resource.provenance = provenance
	var resource_file := stage.path_join("model.tres")
	if ResourceSaver.save(resource, resource_file) != OK:
		return failure(stage, "Cannot write model resource")
	# Validate from staged relative paths before publishing anything.
	var check_resource = ResourceLoader.load(resource_file, "", ResourceLoader.CACHE_MODE_IGNORE)
	var loaded: Dictionary = check_resource.open_document()
	if not loaded.error.is_empty():
		return failure(stage, loaded.error)
	portable = check_resource.snapshot
	var content_hash := (JSON.stringify(portable, "", true, true) + JSON.stringify(hashes)).sha256_text()
	var safe_label := label.validate_filename().replace(".", "_")
	if safe_label.is_empty(): safe_label = "model"
	var destination := parent.path_join(safe_label + "_" + content_hash)
	if DirAccess.dir_exists_absolute(destination):
		var existing = ResourceLoader.load(destination.path_join("model.tres"), "", ResourceLoader.CACHE_MODE_IGNORE)
		if not existing or not existing is ModelResource or existing.snapshot != portable or not existing.validate_package().is_empty():
			return failure(stage, "Existing package conflicts or is damaged: " + destination)
		remove_staging(stage)
	else:
		if DirAccess.rename_absolute(stage, destination) != OK:
			return failure(stage, "Atomic package publication failed")
	return {"error":"", "path":destination.path_join("model.tres")}
