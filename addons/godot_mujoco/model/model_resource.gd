@tool
class_name MjModelResource
extends Resource
# Immutable authored data. Each preview/runtime instance allocates independent native state.
@export var format_version := 1
@export var snapshot: Dictionary = {}
@export var provenance: Dictionary = {}
@export var dependencies: Dictionary = {}

func valid_asset_path(path: String) -> bool:
	if not path.begins_with("assets/") or path.contains("\\") or path.contains(":"):
		return false
	for part in path.split("/"):
		if part.is_empty() or part=="." or part=="..": return false
	return true

func validate_package() -> String:
	if format_version != 1 or resource_path.is_empty():
		return "Unsupported or unsaved MuJoCo model resource"
	if not snapshot.get("xml") is String: return "Missing packaged MJCF"
	var parser := XMLParser.new()
	if parser.open_buffer(snapshot.xml.to_utf8_buffer()) != OK: return "Invalid packaged MJCF"
	var referenced := {}
	while true:
		var status := parser.read()
		if status == ERR_FILE_EOF: break
		if status != OK: return "Invalid packaged MJCF"
		if parser.get_node_type() != XMLParser.NODE_ELEMENT: continue
		var tag := parser.get_node_name()
		if tag == "include": return "Packaged MJCF must flatten includes"
		for index in parser.get_attribute_count():
			var key := parser.get_attribute_name(index)
			var value := parser.get_attribute_value(index)
			if tag == "compiler" and key in ["assetdir", "meshdir", "texturedir"] and not value.is_empty():
				return "Packaged MJCF cannot redirect asset directories"
			if not key in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"]: continue
			if value.is_empty(): continue
			if not tag in ["mesh", "texture", "hfield", "skin"]:
				return "Unsupported packaged file reference: " + tag
			if not valid_asset_path(value): return "Invalid dependency path: " + value
			referenced[value] = true
	for relative in referenced:
		if not dependencies.has(relative): return "Unlisted packaged dependency: " + relative
	var folder := resource_path.get_base_dir()
	for relative in dependencies:
		if not relative is String or not valid_asset_path(relative):
			return "Invalid dependency path: " + str(relative)
		if not referenced.has(relative): return "Unreferenced manifest dependency: " + relative
		var path := folder.path_join(relative)
		if not FileAccess.file_exists(path): return "Missing packaged dependency: " + relative
		if not dependencies[relative] is String or FileAccess.get_sha256(path) != dependencies[relative]:
			return "Packaged dependency hash mismatch: " + relative
	return ""

func open_document() -> Dictionary:
	var error := validate_package()
	if not error.is_empty():
		return {"error":error}
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.restore_at(snapshot, resource_path.get_base_dir()):
		return {"error":document.get_error()}
	return {"document":document, "error":""}
