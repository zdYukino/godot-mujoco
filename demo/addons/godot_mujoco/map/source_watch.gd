@tool
extends RefCounted
## Content hashes, never mtimes. Sources are observation-only.
var source := ""
var hashes: Dictionary = {}
var exported_hash := ""
var error := ""

func capture(path: String, dependencies: Array = []) -> bool:
	var candidate := {}
	var files: Array = dependencies.duplicate()
	files.append(path)
	if path.get_extension().to_lower() == "xml":
		var visited := {}
		error = preload("../model/package_builder.gd").source_files(path, visited)
		if not error.is_empty(): return false
		files.append_array(visited.keys())
	for file in files:
		if not FileAccess.file_exists(file): error = "缺少来源依赖: " + str(file); return false
		var hash := FileAccess.get_sha256(file)
		if hash.is_empty(): error = "无法读取来源: " + str(file); return false
		candidate[file] = hash
	source = path; hashes = candidate; error = ""
	return true

func inspect(dirty: bool) -> Dictionary:
	var changes := []
	for path in hashes:
		var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
		if current != hashes[path]: changes.append(path)
	var state := "已对齐"
	if not error.is_empty(): state = "解析失败"
	elif not changes.is_empty(): state = "冲突" if dirty else "源已变"
	elif dirty: state = "本地脏"
	return {"state":state, "changes":changes, "error":error, "exported_hash":exported_hash}
