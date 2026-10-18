@tool
class_name MjModelResource
extends Resource
# Immutable authored data. Each preview/runtime instance allocates independent native state.
@export var format_version := 1
@export var snapshot: Dictionary = {}
@export var provenance: Dictionary = {}
@export var dependencies: Dictionary = {}

func validate_package() -> String:
	if format_version != 1 or resource_path.is_empty():
		return "Unsupported or unsaved MuJoCo model resource"
	var folder := resource_path.get_base_dir()
	for relative in dependencies:
		if not relative.begins_with("assets/") or relative.contains("..") or relative.is_absolute_path():
			return "Invalid dependency path: " + relative
		var path := folder.path_join(relative)
		if not FileAccess.file_exists(path):
			return "Missing packaged dependency: " + relative
		if FileAccess.get_sha256(path) != dependencies[relative]:
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
