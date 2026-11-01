extends "res://addons/godot_mujoco/model/compile_worker.gd"
# Deterministic test boundary: mutate a declared source after native production,
# immediately before the real post-compile dependency check. No timing sleeps.
var dependency_checks := 0

func stable_dependencies(design: Resource, observation: Dictionary) -> String:
	dependency_checks += 1
	if dependency_checks == 2 and not design.dependencies.is_empty():
		var path: String = design.dependencies.keys()[0]
		var data := FileAccess.get_file_as_bytes(path)
		data[0] = 32 if data[0] != 32 else 35
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(data); file.close()
	return super.stable_dependencies(design, observation)
