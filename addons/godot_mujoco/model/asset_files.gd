@tool
extends RefCounted

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

