extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for name in ["package-path.txt","cube-package-path.txt"]:
		var design: Resource = load(FileAccess.get_file_as_string("res://"+name))
		var error: String = design.validate_dependencies()
		if error.is_empty(): error = await Builder.compile_design(design)
		if not error.is_empty(): printerr(error);quit(1);return
		if name.begins_with("cube") and design.dependencies.size()!=6:quit(1);return
	print("RELOCATED_MODEL_PASS");quit()
