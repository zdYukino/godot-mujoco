extends SceneTree
func _initialize() -> void:
	var path := FileAccess.get_file_as_string("res://package-path.txt")
	var resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var result: Dictionary = resource.open_document()
	if not result.error.is_empty():
		printerr(result.error); quit(1); return
	var doc: RefCounted = result.document
	doc.set_paused(false)
	doc.advance(.02)
	print("RELOCATED_MODEL_PASS ",doc.inspect())
	quit(0)
