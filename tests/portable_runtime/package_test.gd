extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print("AUTHOR_ASSETS ",label," ",ok)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var source := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
	var imported: Dictionary = await Builder.import_file(source,"res://designs","included_mesh")
	check(imported.error.is_empty(), "external include and mesh import")
	if not imported.error.is_empty(): printerr(imported.error);quit(1);return
	var design: Resource = imported.design
	check(not design.xml().contains(source.get_base_dir()), "MJCF references project copies")
	check(design.provenance.source_archives.size() >= 2, "original include bytes archived")
	check(design.validate_dependencies().is_empty(), "project dependency hashes match")
	check(not design.cached_geometry.is_empty(), "portable preview mesh cached")
	var saved := FileAccess.open("res://package-path.txt",FileAccess.WRITE);saved.store_string(imported.path);saved.close()
	var asset: String = design.dependencies.keys()[0]
	check(DirAccess.rename_absolute(asset,asset+".missing")==OK, "hide project dependency")
	check(design.validate_dependencies().contains("Missing"), "missing dependency diagnosed")
	check(DirAccess.rename_absolute(asset+".missing",asset)==OK, "restore project dependency")
	var before := FileAccess.get_file_as_bytes(asset)
	var changed := FileAccess.open(asset,FileAccess.WRITE);changed.store_string("changed");changed.close()
	check(design.validate_dependencies().contains("hash mismatch"), "changed bytes diagnosed")
	changed=FileAccess.open(asset,FileAccess.WRITE);changed.store_buffer(before);changed.close()
	var alternate := await Builder.import_file(source.get_base_dir()+"_other/model.xml","res://designs","included_mesh")
	check(alternate.error.is_empty() and alternate.path!=imported.path,"same label retains independent author identity")
	check(alternate.design.dependencies.values()!=design.dependencies.values(),"same asset basename cannot overwrite different bytes")
	check(design.validate_dependencies().is_empty(),"original design unchanged by another import")
	check((await Builder.import_file("res://removed.gmj.json")).error.contains(".xml"),"removed model format is rejected before opening")
	# Six cube faces exercise native string-vector access and portable texture resources.
	var attributes := ""
	var faces := ["right","left","up","down","front","back"]
	for i in faces.size():
		var face := source.get_base_dir().path_join("face_"+faces[i]+".png")
		var image := Image.create(4,4,false,Image.FORMAT_RGB8);image.fill(Color.from_hsv(float(i)/6,1,1))
		check(image.save_png(face)==OK,"create cube face "+faces[i])
		attributes += " file"+faces[i]+"='"+face+"'"
	var cube_source := source.get_base_dir().path_join("cube.xml")
	var file := FileAccess.open(cube_source,FileAccess.WRITE)
	file.store_string("<mujoco><asset><texture name='cube' type='cube'"+attributes+"/><material name='mat' texture='cube'/></asset><worldbody><geom name='cube' type='box' size='.1 .1 .1' material='mat'/></worldbody></mujoco>");file.close()
	var cube := await Builder.import_file(cube_source,"res://designs","cube")
	check(cube.error.is_empty(),"six cube faces import")
	if cube.error.is_empty():
		check(cube.design.dependencies.size()==6,"six distinct texture dependencies")
		file=FileAccess.open("res://cube-package-path.txt",FileAccess.WRITE);file.store_string(cube.path);file.close()
	print("PACKAGE_RESULT ",JSON.stringify({"failed":failures}));quit(0 if failures==0 else 1)
