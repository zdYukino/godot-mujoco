@tool
extends RefCounted
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func button(node: Node, label: String) -> Button:
	if node is Button and node.text==label:return node
	for child in node.get_children():
		var found = button(child,label)
		if found:return found
	return null
func capture(plugin: EditorPlugin, filename: String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			print("CAPTURE_BEGIN ",filename)
			var folder=arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(folder)
			await plugin.get_tree().create_timer(1.0).timeout
			while EditorInterface.get_resource_filesystem().is_scanning(): await plugin.get_tree().process_frame
			for i in range(10):await plugin.get_tree().process_frame
			# A static editor may skip draw frames in low-processor mode.
			RenderingServer.force_draw()
			check(plugin.get_viewport().get_texture().get_image().save_png(folder.path_join(filename))==OK,"editor screenshot "+filename)
func run(plugin: EditorPlugin) -> void:
	await plugin.get_tree().create_timer(3.0).timeout
	var panel = plugin.panel
	EditorInterface.set_main_screen_editor("MuJoCo")
	check(panel.open_project_model(FileAccess.get_file_as_string("res://g1-resource-path.txt")),"open relocated G1 package in editor")
	panel.select_entity("actuator","left_elbow_joint_position")
	panel.inputs["kp"].text="126.0"
	panel.inputs["kp"].text_changed.emit("126.0")
	button(panel.fields,"Apply to physics").pressed.emit()
	check(not panel.pending,"real Apply signal commits G1 drive edit")
	button(panel,"Save project model").pressed.emit()
	check(not panel.state.dirty and not panel.project_model_path.is_empty(),"real Save project model signal publishes resource")
	check(FileAccess.file_exists(panel.project_model_path),"published resource exists")
	var resource=ResourceLoader.load(panel.project_model_path)
	var archives_ok=true
	for hash in resource.provenance.sources.values():
		archives_ok = archives_ok and FileAccess.get_sha256(panel.project_model_path.get_base_dir().path_join("sources/"+hash+".xml"))==hash
	check(archives_ok and not resource.provenance.sources.is_empty(),"relocated editing retains original source archive bytes")
	await capture(plugin,"04-portable-g1-editor.png")
	button(panel,"Create runtime scene").pressed.emit()
	var dialog: EditorFileDialog
	for child in panel.get_children():
		if child is EditorFileDialog:dialog=child
	check(dialog!=null,"runtime scene save dialog opened")
	if dialog:
		dialog.hide()
		dialog.file_selected.emit("res://EditorCreatedScene.tscn")
	check(FileAccess.file_exists("res://EditorCreatedScene.tscn"),"scene saved through real dialog signal")
	var scene: PackedScene=load("res://EditorCreatedScene.tscn")
	check(scene!=null,"saved scene loads")
	if scene:
		var instance=scene.instantiate()
		check(instance.get_node("Model").model.resource_path==panel.project_model_path,"scene pins published resource revision")
		instance.free()
	await plugin.get_tree().process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await plugin.get_tree().process_frame
	print("EDITOR_OPEN_SCENE")
	EditorInterface.open_scene_from_path("res://RuntimeScene.tscn")
	EditorInterface.set_main_screen_editor("3D")
	await capture(plugin,"05-portable-godot-scene.png")
	panel.state.dirty=false
	var failed=0
	for c in checks:if not c.passed:failed+=1
	print("PORTABLE_EDITOR_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	while EditorInterface.get_resource_filesystem().is_scanning(): await plugin.get_tree().process_frame
	plugin.get_tree().quit(0 if failed==0 else 1)
