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

func snapshot() -> Dictionary:
	return {"source":source,"hashes":hashes.duplicate(true),"exported_hash":exported_hash,"error":error}

func restore(value: Dictionary) -> void:
	source = value.get("source",""); hashes = value.get("hashes",{}).duplicate(true)
	exported_hash = value.get("exported_hash",""); error = value.get("error","")

static func import_verified(path: String, between_reads: Callable = Callable()) -> Dictionary:
	# Optimistic stable-read check, not an atomic filesystem snapshot. The first
	# compile discovers dependencies; only the second compile may be committed.
	var probe: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not probe.import_file(path): return {"error":probe.get_error()}
	var script = load("res://addons/godot_mujoco/map/source_watch.gd")
	var before = script.new()
	if not before.capture(path,probe.asset_manifest().assets): return {"error":before.error}
	if between_reads.is_valid(): between_reads.call()
	var candidate: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not candidate.import_file(path): return {"error":candidate.get_error()}
	var after = script.new()
	if not after.capture(path,candidate.asset_manifest().assets): return {"error":after.error}
	if before.hashes != after.hashes: return {"error":"导入期间来源/依赖变化，安全拒绝；请重试。旧文档保持不动"}
	return {"error":"","document":candidate,"watch":after}
