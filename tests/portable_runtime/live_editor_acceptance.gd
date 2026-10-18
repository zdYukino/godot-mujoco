@tool
extends RefCounted
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label);printerr("FAIL ",label)
func wait_for(plugin: EditorPlugin, condition: Callable) -> bool:
	for unused in 200:
		if condition.call(): return true
		await plugin.get_tree().create_timer(.1).timeout
	return false
func run(plugin: EditorPlugin) -> void:
	var panel: Control = plugin.panel
	var file := FileAccess.open("res://g1-resource-path.txt",FileAccess.READ)
	var path := file.get_as_text().strip_edges()
	file.close()
	check(panel.open_project_model(path),"editor opens saved design")
	EditorInterface.play_main_scene()
	var connected: bool = await wait_for(plugin,func():return plugin.live_debugger.instances.size()==2)
	check(connected,"two actual runtime instances register through debugger")
	if connected:
		panel.refresh_runtime_targets()
		var target: String = panel.runtime_target_key
		check(panel.execute({"op":"set","kind":"body","name":"left_elbow_link","values":{"mass":1.4}}),"edit design independently of runtime")
		check(not panel.apply_runtime_model(),"unsaved design cannot apply silently")
		panel.save_project_model()
		check(panel.apply_runtime_model(),"actual Apply-to-runtime button handler sends resource revision")
		check(not panel.apply_runtime_model(),"repeated Apply blocked pending acknowledgement")
		check(await wait_for(plugin,func():return plugin.live_debugger.instances.has(target) and plugin.live_debugger.instances[target].revision==1),"native commit acknowledged in editor")
		var info: Dictionary = plugin.live_debugger.instances[target]
		check(info.resource==panel.project_model_path and info.error.is_empty() and not info.pending,"editor shows applied resource and clean revision")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--live-capture="):
				EditorInterface.set_main_screen_editor("MuJoCo")
				for unused in 3: await plugin.get_tree().process_frame
				RenderingServer.force_draw(false)
				check(plugin.get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--live-capture="))==OK,"capture actual live-edit editor")
		for key in plugin.live_debugger.instances:
			if key!=target: check(plugin.live_debugger.instances[key].revision==0,"unselected robot revision unchanged")
		panel.select_entity("actuator","left_elbow_joint_position")
		check(panel.execute({"op":"control","name":"left_elbow_joint_position","value":.6}),"author control")
		check(panel.send_runtime_control(),"selected control delivered through debugger")
		check(await wait_for(plugin,func():return not plugin.live_debugger.instances[target].pending),"control acknowledgement clears pending")
	EditorInterface.stop_playing_scene()
	check(await wait_for(plugin,func():return plugin.live_debugger.instances.is_empty()),"stopped runtime clears stale instance targets")
	panel.save_project_model()
	if not EditorInterface.get_edited_scene_root():
		EditorInterface.open_scene_from_path("res://RuntimeScene.tscn")
		await plugin.get_tree().process_frame
	var local_model: Node = EditorInterface.get_edited_scene_root().get_node("Model")
	var old_resource = local_model.model
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(local_model)
	check(panel.assign_saved_model(),"assign saved design to selected local scene instance")
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(local_model))
	history.undo()
	check(local_model.model==old_resource,"scene assignment undo")
	history.redo()
	check(local_model.model.resource_path==panel.project_model_path,"scene assignment redo")
	if DisplayServer.get_name() == "headless":
		# Headless editor thumbnails emit an engine ERROR; test scene serialization
		# directly here, and exercise the actual editor Save action in the GUI run.
		var saved := PackedScene.new()
		check(saved.pack(EditorInterface.get_edited_scene_root())==OK and ResourceSaver.save(saved,"res://AssignedDesign.tscn")==OK,"serialize local scene design reference")
	else:
		check(EditorInterface.save_scene()==OK,"editor Save action persists design reference for next F5")
	panel.state.dirty = false
	panel.pending = false
	print("LIVE_EDITOR_RESULT ",JSON.stringify({"failed":failures.size(),"failures":failures}))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
