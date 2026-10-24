@tool
extends RefCounted
signal changed
# Undo history references this session, never a freed plugin Control or native pointer.
var source_watch = preload("res://addons/godot_mujoco/map/source_watch.gd").new()
var document: RefCounted
var content: Dictionary = {}
var file_path := ""
var dirty := false
var draft: Dictionary = {}

func activate() -> void:
	document = ClassDB.instantiate("MjEditorDocument")
	if not content.is_empty():
		if document.restore(content): source_watch.restore(content.get("source_tracking",{}))
	else:
		content = snapshot()

func deactivate() -> void:
	if document:
		content = snapshot()
	document = null

func restore_snapshot(value: Dictionary) -> void:
	if document and not document.restore(value):
		push_error("MuJoCo undo/redo failed: " + document.get_error())
		return
	source_watch.restore(value.get("source_tracking",{}))
	content = value.duplicate(true)
	dirty = true
	changed.emit()

func snapshot() -> Dictionary:
	var value: Dictionary = document.snapshot()
	value["source_tracking"] = source_watch.snapshot()
	return value
