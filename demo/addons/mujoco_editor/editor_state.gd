@tool
extends RefCounted
signal changed
# Undo history references this session, never a freed plugin Control or native pointer.
var document: RefCounted
var content: Dictionary = {}
var file_path := ""
var dirty := false
var draft: Dictionary = {}

func activate() -> void:
	document = ClassDB.instantiate("MjEditorDocument")
	if not content.is_empty():
		document.restore(content)
	else:
		content = document.snapshot()

func deactivate() -> void:
	if document:
		content = document.snapshot()
	document = null

func restore_snapshot(value: Dictionary) -> void:
	if document and not document.restore(value):
		push_error("MuJoCo undo/redo failed: " + document.get_error())
		return
	content = value.duplicate(true)
	dirty = true
	changed.emit()
