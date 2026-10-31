extends RefCounted
## Refresh saved scene/data dependencies without hot-reloading executing scripts.
class CachedScripts extends ResourceFormatLoader:
	var extensions: PackedStringArray
	func _get_recognized_extensions() -> PackedStringArray:
		return extensions
	func _handles_type(type: StringName) -> bool:
		return type in ["Script","GDScript","CSharpScript"]
	func _recognize_path(path: String, _type: StringName) -> bool:
		return ResourceLoader.get_cached_ref(path) is Script
	func _load(path: String, _original: String, _threads: bool, _cache: int) -> Variant:
		return ResourceLoader.get_cached_ref(path)

static func load_scene(path: String) -> PackedScene:
	var scripts := CachedScripts.new()
	scripts.extensions=ResourceLoader.get_recognized_extensions_for_type("Script")
	ResourceLoader.add_resource_format_loader(scripts,true)
	var scene := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	ResourceLoader.remove_resource_format_loader(scripts)
	return scene as PackedScene
