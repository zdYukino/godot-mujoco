@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func run(plugin):
	var panel = plugin.map_panel
	for i in 15: await panel.get_tree().process_frame
	check(is_instance_valid(panel.camera) and is_instance_valid(panel.tree),"P1 editor panel initialized")
	panel.browse_package()
	var picker: FileDialog
	for child in panel.get_children():
		if child is FileDialog: picker = child
	check(picker != null and picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE and picker.filters.size() == 1 and picker.filters[0].get_slice(";",0).strip_edges() == "*.json", "P3 package picker uses selectable JSON wildcard filter")
	if picker: picker.hide(); picker.canceled.emit()
	await panel.get_tree().process_frame
	panel.path_field.text = "res://fixtures/box.glb"; panel.unit.select(1); panel.axes.select(0)
	check(panel.import_source(false),"P1 viewer imports GLB")
	var path := str(panel.session.visual.get_path_to(panel.session.meshes()[0]))
	panel.items[path].select(0); panel.select_tree()
	check(panel.selected == path,"P1 tree selection links object")
	panel.focus(path); check(panel.center.length()<.001 and panel.distance>1,"P1 focus calibration box")
	panel.pick(panel.camera.unproject_position(Vector3.ZERO)); check(panel.selected == path,"P1 triangle picking links tree")
	panel.toggle_selected(); check(not panel.preview.get_node(NodePath(path)).visible,"P1 hide preview only")
	check(panel.session.visual.get_node(NodePath(path)).visible,"P1 hide preserves original visual data")
	panel.toggle_selected()
	panel.strategy.select(1); panel.friction.value = .4; panel.layer.value = 2; panel.mask.value = 3
	check(panel.configure(),"P2 editor box configuration")
	check(panel.collision_preview.get_child_count()==1,"P2 collision wireframe exists")
	panel.session.history.undo(); panel.rebuild(); check(panel.session.specs.is_empty(),"P3 editor undo")
	panel.session.history.redo(); panel.rebuild(); check(panel.session.specs[path].friction == .4,"P3 editor redo")
	var before = panel.session.visual
	panel.path_field.text = "res://fixtures/bad.glb"; check(not panel.import_source(true) and panel.session.visual==before,"P1 failed viewer reimport preserves document")
	var package = preload("res://addons/godot_mujoco/map/package.gd").pack(panel.session,"res://ui_packages")
	check(package.error.is_empty(),"P3 viewer package save")
	if package.error.is_empty():
		check(panel.open_package(package.path),"P3 viewer package reopen")
		check(panel.session.specs[path].layer==2 and panel.session.specs[path].mask==3,"P3 viewer layer/mask persistence")
	# A correctly rehashed but structurally incomplete package must fail before load.
	if package.error.is_empty():
		var damaged := "res://broken_map"; DirAccess.make_dir_recursive_absolute(damaged)
		var text := FileAccess.get_file_as_string(package.path.path_join("map.tscn"))
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(package.path.path_join("manifest.json")))
		var file := FileAccess.open(damaged.path_join("map.tscn"),FileAccess.WRITE); file.store_string(text.replace('[node name="Visual"','[node name="MissingVisual"')); file.close()
		manifest.files["map.tscn"] = FileAccess.get_sha256(damaged.path_join("map.tscn"))
		file = FileAccess.open(damaged.path_join("manifest.json"),FileAccess.WRITE); file.store_string(JSON.stringify(manifest)); file.close()
		var retained = panel.session.visual
		check(not panel.open_package(damaged) and panel.session.visual==retained and panel.session.error.contains("结构"),"P3 malformed package opens with diagnostic and retains previous view")
	var edit_root := Node3D.new(); edit_root.name = "MapHost"
	var packed := PackedScene.new(); packed.pack(edit_root); ResourceSaver.save(packed,"res://MapHost.tscn"); edit_root.free()
	EditorInterface.open_scene_from_path("res://MapHost.tscn")
	for i in 15: await panel.get_tree().process_frame
	check(panel.apply_scene(),"P3 Apply map to editable scene")
	var edited := EditorInterface.get_edited_scene_root()
	check(edited.has_node("StaticMap/Physics"),"P3 scene contains authored collision")
	check(panel.apply_scene() and edited.get_child_count()==1,"P3 repeated Apply replaces map without duplicates")
	var history = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(edited))
	history.undo(); check(edited.has_node("StaticMap/Physics"),"P3 Undo replacement restores previous map")
	history.redo(); check(edited.get_child_count()==1,"P3 Redo replacement keeps one map")
	if DisplayServer.get_name() == "headless":
		var saved := PackedScene.new(); check(saved.pack(edited)==OK and ResourceSaver.save(saved,"res://MapHost.tscn")==OK,"P3 headless scene save without thumbnail")
	else:
		check(EditorInterface.save_scene()==OK,"P3 GUI editor scene save")
	# MJCF tracker sees main/include and keeps old compiled state on failed reimport.
	check(plugin.panel.import_mjcf("res://fixtures/main.xml"),"P0 MJCF panel import tracked")
	check(plugin.panel.source_watch.hashes.size() == 2,"P0 main/include captured in UI")
	var snapshot: Dictionary = plugin.state.document.snapshot()
	var file := FileAccess.open("res://fixtures/include.xml",FileAccess.WRITE); file.store_string('<mujoco><geom type="invalid"/></mujoco>'); file.close()
	check(not plugin.panel.reimport_source() and plugin.state.document.snapshot()==snapshot,"P0 UI bad source atomic rollback")
	var source_result = preload("res://source_transaction_test.gd").new().run(plugin)
	passed += source_result.passed; failed += source_result.failed
	print("STATIC_MAP_EDITOR ",JSON.stringify({"passed":passed,"failed":failed}))
	panel.session.dirty = false; plugin.state.dirty = false
	panel.get_tree().quit(1 if failed else 0)
