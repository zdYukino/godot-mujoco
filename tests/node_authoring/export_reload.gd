extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	if not document.import_file("res://exported/model.xml"):
		printerr(document.get_error()); quit(1); return
	var stats: Array = document.collision_stats()
	var xml: String = document.snapshot().xml
	var ok: bool = stats.size()==1 and stats[0].depth==6 and stats[0].query_valid
	ok = ok and xml.contains('maxhullvert="8"') and xml.contains('sdf_iterations="17"') and xml.contains('nativeccd="disable"')
	print("EXPORT_RELOAD_RESULT ",JSON.stringify({"passed":4 if ok else 0,"failed":0 if ok else 1,"stats":stats}))
	quit(0 if ok else 1)
