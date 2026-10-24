extends SceneTree
const Package = preload("res://addons/godot_mujoco/map/package.gd")
func _initialize():
	var source := FileAccess.get_file_as_string("res://saved_path.txt").strip_edges()
	var target := "res://damaged"
	DirAccess.make_dir_recursive_absolute(target)
	DirAccess.copy_absolute(source.path_join("manifest.json"),target.path_join("manifest.json"))
	var missing := Package.validate(target)
	assert(missing.contains("缺少地图依赖"))
	var f := FileAccess.open(target.path_join("map.tscn"),FileAccess.WRITE); f.store_string("tampered"); f.close()
	var damaged := Package.validate(target)
	assert(damaged.contains("哈希不匹配"))
	assert(Package.validate(source).is_empty())
	print("STATIC_MAP_DAMAGE 3 passed"); quit()
