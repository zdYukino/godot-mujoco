@tool
extends RefCounted
## Project-owned author resources and cached previews. All compilation uses isolated workers.
const Author = preload("author_resource.gd")
const Xml = preload("author_xml.gd")
const Collision = preload("collision_settings.gd")
const Service = preload("compile_service.gd")

static func run_worker(request: Dictionary) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var service := Service.new()
	tree.root.add_child(service)
	service.submit(request)
	var result: Dictionary = await service.completed
	service.queue_free()
	return result

static func apply_result(design: Resource, result: Dictionary) -> String:
	if not result.get("success", false): return str(result.get("error", "Compilation failed"))
	var error: String = design.restore_author(result.author)
	if not error.is_empty(): return error
	design.cached_entities = result.entities
	design.cached_geometry = result.geometry
	design.collision_geometry = result.collision_geometry
	design.compiled_snapshot = result.snapshot
	design.collision_stats = result.collision_stats
	design.validated_revision = design.revision
	design.validated_context = result.context
	# Worker scratch paths are never required by a relocated saved design.
	design.cache_path = ""
	return ""

static func compile_design(design: Resource, context: Dictionary = {}) -> String:
	if context.is_empty(): context = Collision.context(null, design)
	return apply_result(design, await run_worker({"op":"compile", "author":design.author_snapshot(), "context":context}))

static func save_design(design: Resource, parent: String, label: String) -> Dictionary:
	if not parent.begins_with("res://") or parent.contains(".."):
		return {"error":"Choose a directory inside the Godot project"}
	var directory := parent.path_join(label.validate_filename() + "_" + design.document_id)
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"error":"Cannot create author resource directory"}
	var path := directory.path_join("design.tres")
	if ResourceSaver.save(design, path) != OK: return {"error":"Cannot save author resource"}
	return {"error":"", "path":path, "design":design}

static func import_file(path: String, parent := "res://mujoco_models", label := "model") -> Dictionary:
	if path.get_extension().to_lower() != "xml": return {"error":"Select an MJCF .xml document"}
	var result := await run_worker({"op":"import", "source":path})
	var design := Author.new()
	var error := apply_result(design, result)
	if not error.is_empty(): return {"error":error}
	return save_design(design, parent, label)

static func save_document(document: RefCounted, parent := "res://mujoco_models", label := "model") -> Dictionary:
	var converted := Author.from_native_document(document)
	if not converted.error.is_empty(): return converted
	var design: Resource = converted.design
	var source: String = document.snapshot().get("source", "")
	if not FileAccess.file_exists(source):
		var folder := parent.path_join("sources")
		if not parent.begins_with("res://") or parent.contains("..") or DirAccess.make_dir_recursive_absolute(folder) != OK:
			return {"error":"Cannot archive generated MJCF"}
		source = folder.path_join(design.xml().sha256_text() + ".xml")
		var file := FileAccess.open(source, FileAccess.WRITE)
		if not file: return {"error":"Cannot write generated MJCF"}
		file.store_string(design.xml()); file.close()
	var result := await run_worker({"op":"import_design", "author":design.author_snapshot(), "source":source, "source_sha256":FileAccess.get_sha256(source)})
	var error := apply_result(design, result)
	if not error.is_empty(): return {"error":error}
	return save_design(design, parent, label)
