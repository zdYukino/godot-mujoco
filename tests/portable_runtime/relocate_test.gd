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
	var cube = ResourceLoader.load(FileAccess.get_file_as_string("res://cube-package-path.txt"))
	if cube.dependencies.size()!=6 or not cube.open_document().error.is_empty():
		printerr("Relocated cube textures failed");quit(1);return
	print("RELOCATED_MODEL_PASS ",doc.inspect())
	quit(0)
