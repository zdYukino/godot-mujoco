extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("PACKAGE ",label," ",ok)
	if not ok: failures += 1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file(source), "external include mesh import")
	var snapshot: Dictionary = doc.snapshot()
	var package: Dictionary = Builder.pack(doc, "res://models", "same_name")
	check(package.error.is_empty(), "atomic portable pack " + str(package))
	if not package.error.is_empty(): quit(1); return
	var again: Dictionary = Builder.pack(doc, "res://models", "same_name")
	check(again.get("path", "") == package.path, "repeat deduplicates")
	var resource = ResourceLoader.load(package.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(not resource.snapshot.xml.contains(source.get_base_dir()), "no source dependency in MJCF")
	check(resource.provenance.sources.size() >= 2, "include provenance retained")
	check(resource.open_document().error.is_empty(), "portable opens")
	check(doc.snapshot() == snapshot, "pack does not mutate document")
	check(doc.edit({"op":"add","shape":"cylinder","name":"extra"}), "edit before second package")
	var other: Dictionary = Builder.pack(doc, "res://models", "same_name")
	check(other.error.is_empty() and other.path != package.path, "same label distinct content")
	var file := FileAccess.open("res://package-path.txt", FileAccess.WRITE)
	file.store_string(package.path)
	file.close()
	# Missing dependency must not replace any published package or active model.
	var asset: String = doc.asset_manifest().assets[0]
	var moved := asset + ".unavailable"
	check(DirAccess.rename_absolute(asset, moved) == OK, "hide external source")
	var failed: Dictionary = Builder.pack(doc, "res://models", "same_name")
	check(not failed.error.is_empty(), "missing dependency refuses publication")
	check(resource.open_document().error.is_empty(), "published package independent of original")
	check(DirAccess.rename_absolute(moved, asset) == OK, "restore disposable fixture")
	var alternate: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(alternate.import_file(source.get_base_dir() + "_other/model.xml"), "same basename alternate asset")
	var alternate_package: Dictionary = Builder.pack(alternate, "res://models", "same_name")
	check(alternate_package.error.is_empty() and alternate_package.path != package.path, "same asset basename does not overwrite")
	var alternate_resource = ResourceLoader.load(alternate_package.path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(alternate_resource.dependencies.keys() != resource.dependencies.keys(), "asset hashes distinguish different bytes")
	var packaged_asset: String = package.path.get_base_dir().path_join(resource.dependencies.keys()[0])
	check(DirAccess.rename_absolute(packaged_asset, packaged_asset + ".missing") == OK, "hide packaged dependency")
	check(not resource.open_document().error.is_empty(), "missing packaged dependency diagnosed")
	check(DirAccess.rename_absolute(packaged_asset + ".missing", packaged_asset) == OK, "restore packaged dependency")
	# Exercise the pinned MuJoCo C string-vector boundary with six cube faces.
	var attributes := ""
	var faces := ["right","left","up","down","front","back"]
	for i in faces.size():
		var face := source.get_base_dir().path_join("face_"+faces[i]+".png")
		var texture := Image.create(4,4,false,Image.FORMAT_RGB8)
		texture.fill(Color.from_hsv(float(i)/6,1,1))
		check(texture.save_png(face)==OK,"write cube fixture "+faces[i])
		attributes += " file"+faces[i]+"='"+face+"'"
	var cube_source := source.get_base_dir().path_join("cube.xml")
	var cube_file := FileAccess.open(cube_source,FileAccess.WRITE)
	cube_file.store_string("<mujoco><asset><texture name='cube' type='cube'"+attributes+"/><material name='mat' texture='cube'/></asset><worldbody><body name='cube'><geom type='box' size='.1 .1 .1' material='mat'/></body></worldbody></mujoco>")
	cube_file.close()
	var cube_doc:RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(cube_doc.import_file(cube_source),"cube faces import without host STL access")
	var cube_package:Dictionary=Builder.pack(cube_doc,"res://models","cube")
	check(cube_package.error.is_empty(),"six cube faces pack")
	if cube_package.error.is_empty():
		var cube_resource=ResourceLoader.load(cube_package.path)
		check(cube_resource.dependencies.size()==6,"six distinct cube dependencies retained")
		var cube_path:=FileAccess.open("res://cube-package-path.txt",FileAccess.WRITE)
		cube_path.store_string(cube_package.path);cube_path.close()
	print("PACKAGE_RESULT ",JSON.stringify({"failed":failures}))
	quit(0 if failures==0 else 1)
