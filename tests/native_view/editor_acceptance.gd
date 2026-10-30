@tool
extends RefCounted
const Settings = preload("res://addons/godot_mujoco/native_view/settings.gd")
var plugin: EditorPlugin
var output := ""
var run_id := ""
var checks: Array = []
var samples: Array = []
func check(ok: bool, name: String) -> bool:
	checks.append({"name":name,"passed":ok})
	if not ok: printerr("FAIL ",name)
	return ok
func wait_for(test: Callable, seconds := 60.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await plugin.get_tree().process_frame
	return test.call()
func state() -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("state.json"))) if FileAccess.file_exists(output.path_join("state.json")) else {}
	return value if value is Dictionary and value.get("run_id")==run_id else {}
func command(op: String) -> void:
	FileAccess.open(output.path_join("command.tmp"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":run_id,"op":op}))
	DirAccess.rename_absolute(output.path_join("command.tmp"),output.path_join("command.json"))
func run(editor: EditorPlugin) -> void:
	plugin=editor;output=OS.get_environment("GMJ_RENDER_TEST_OUT")
	EditorInterface.set_main_screen_editor("3D");plugin.reveal_scope(0)
	if "--reopen" in OS.get_cmdline_user_args():
		check(Settings.mode()==Settings.MUJOCO,"saved native project choice survives editor restart")
		check(plugin.view_controls.renderer_choice.selected==1,"reopened toolbar shows saved native choice")
		check(plugin.view_controls.renderer_choice.is_visible_in_tree(),"renderer selector is visible in MuJoCo dock")
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor-selector.png"))
		await finish();return
	await scenario()
	await finish()
func scenario() -> void:
	EditorInterface.open_scene_from_path("res://Main.tscn")
	if not check(await wait_for(func():return EditorInterface.get_edited_scene_root() is MjRuntimeWorld),"actual gallery scene opens"): return
	var root: Node = EditorInterface.get_edited_scene_root()
	plugin.reveal_scope(0)
	var probe := Node.new();probe.name="F5RenderProbe";probe.set_script(load("res://runtime_probe.gd"))
	probe.output=output;root.add_child(probe);probe.owner=root
	root.start_paused=true
	var choice: OptionButton = plugin.view_controls.renderer_choice
	check(choice.item_count==2 and choice.get_item_text(0)=="Godot" and choice.get_item_text(1)=="MuJoCo 原生","visible F5 renderer selector has both choices")
	check(choice.is_visible_in_tree(),"renderer selector visible in dock")
	check(plugin.view_controls.menu.get_popup().get_item_index(11)>=0,"viewport display menu also offers native F5 choice")
	if not check(Settings.unavailable_reason().is_empty(),"official X11/OpenGL editor loads native capability: "+Settings.unavailable_reason()): return
	for mode in [Settings.MUJOCO,Settings.GODOT]:
		run_id=("native" if mode==Settings.MUJOCO else "godot")+"-"+str(Time.get_ticks_usec())
		probe.run_id=run_id
		# Deliberately set the opposite legacy flag: the saved project choice wins.
		root.native_view_experimental=mode==Settings.GODOT
		choice.select(mode);choice.item_selected.emit(mode)
		var config := ConfigFile.new()
		check(config.load("res://project.godot")==OK and config.get_value("rendering","mujoco_native_view/renderer",-1)==mode,"toolbar selection is persisted to project.godot")
		var packed := PackedScene.new();packed.pack(root)
		check(ResourceSaver.save(packed,"res://Main.tscn")==OK,"save test gallery before F5")
		var model: Node = root.get_node("Model")
		plugin._apply_changes()
		if not check(await wait_for(func():return model.design.validated_revision==model.design.revision and model.design.validated_context==model.compilation_signature() and model.design.validation_error.is_empty() and model.author_scene.due_ms==0 and model.author_scene.pending_transforms.is_empty() and not model.author_scene.compiler.busy()) and plugin._build(),"gallery author data validates for F5"): return
		EditorInterface.play_main_scene()
		if not check(await wait_for(func():return state().get("ready",false) and (state().get("native",false) if mode==Settings.MUJOCO else state().get("world_visible",false))),"F5 launches requested renderer"): return
		if not check(await wait_for(func():return FileAccess.file_exists(output.path_join(run_id+".png"))),"actual F5 viewport captured"): return
		var snapshot := state();samples.append(snapshot)
		check(snapshot.left_panel and snapshot.right_panel and not snapshot.native_info,"F5 shows original sidebars with native overlays initially closed")
		check(snapshot.native_groups.size()==12 and not "Simulation" in snapshot.extras_groups,"F5 native menus are independent of Godot F11 extras")
		if mode==Settings.MUJOCO:
			check(snapshot.texture and snapshot.native_frame>0 and snapshot.native_geoms>0,"MuJoCo render produces real shared texture frames")
			check(snapshot.disable_3d and not snapshot.world_visible and snapshot.native_step_calls==0 and snapshot.gl_errors==0,"native view replaces Godot 3D without stepping or GL errors")
			check(snapshot.shared_controls and snapshot.control_window_closed and snapshot.native_scene,"native picture uses shared controls and authoritative CPU scene")
			check("MuJoCo 原生" in snapshot.ui_status,"runtime status identifies actual native renderer")
		else:
			check(not snapshot.native and not snapshot.disable_3d and snapshot.world_visible,"Godot choice overrides native scene flag and keeps Godot 3D")
			check(snapshot.shared_controls and snapshot.control_window_closed and "Godot" in snapshot.ui_status,"shared Godot controls and renderer status restored")
		command("step")
		check(await wait_for(func():return float(state().get("time",0))>0 and (is_equal_approx(float(state().get("native_time",-1)),float(state().get("time",0))) if mode==Settings.MUJOCO else true)),"same authoritative simulation steps in selected renderer")
		command("quit")
		if not check(await wait_for(func():return not EditorInterface.is_playing_scene() and plugin.author_debugger.worlds.is_empty()),"F5 game stops cooperatively and debugger disconnects"): return
	choice.select(Settings.MUJOCO);choice.item_selected.emit(Settings.MUJOCO)
func finish() -> void:
	if EditorInterface.is_playing_scene():
		command("quit")
		if not await wait_for(func():return not EditorInterface.is_playing_scene(),10): EditorInterface.stop_playing_scene()
	var failed := checks.filter(func(row):return not row.passed).size()
	var result := {"checks":checks,"passed":checks.size()-failed,"failed":failed,"samples":samples}
	var name := "reopen.json" if "--reopen" in OS.get_cmdline_user_args() else "results.json"
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("F5_RENDERER_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed}))
	plugin.get_tree().quit(0 if failed==0 else 1)
