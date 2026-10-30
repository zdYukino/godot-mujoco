extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: call_deferred("run")
func settled(world: Node) -> bool:
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		if world.author_started and world.command_request == 0: return true
		if world.info().get("compile_status") == "failed": return false
		await process_frame
	return false
func wait_for(test: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	return false
func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func check_original_ui(viewer: Node) -> void:
	check(viewer.left_panel.visible and viewer.right_panel.visible,"MuJoCo original sidebars available without opening F11")
	check(not viewer.info_enabled and not viewer.windows.help.visible,"MuJoCo original overlays use independent defaults")
	check(viewer.sections.size()==12 and not viewer.extras_sections.has("Simulation") and not viewer.controls.visible,"all entry points keep native groups outside Godot extras")
func godot_picture(world: Node, path: String) -> void:
	var viewer: Node=world.runtime_viewer
	check(await wait_for(func():return viewer.last_backend=="godot" and viewer.presented_frame_id>0 and viewer.presented_layout==viewer.layout_generation),"actual Godot displayed frame is acknowledged")
	var viewport: Viewport=world.get_viewport()
	check(not world.native_view_active and world.visible and not viewport.disable_3d and viewport.get_camera_3d()!=null,"real Godot 3D, visible world and active camera replace no native picture")
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var folder := OS.get_environment("GMJ_EXAMPLE_OUT").path_join("frames").path_join(OS.get_environment("GMJ_EXAMPLE_NAME"))
	DirAccess.make_dir_recursive_absolute(folder)
	var image_path := folder.path_join(path.get_file().get_basename()+".png")
	check(not image.is_empty() and image.get_width()>0 and image.get_height()>0 and image.save_png(image_path)==OK,"actual frame_post_draw Godot picture captured: "+path)
	print("EXAMPLE_GRAPHICS_FRAME ",JSON.stringify({"scene":path,"display":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"backend":viewer.last_backend,"native_active":world.native_view_active,"world_visible":world.visible,"disable_3d":viewport.disable_3d,"camera_active":viewport.get_camera_3d()!=null,"left":viewer.left_panel.visible,"right":viewer.right_panel.visible,"godot_extras":viewer.controls.visible,"native_groups":viewer.sections.size(),"displayed_frame":viewer.presented_frame_id,"layout":viewer.layout_generation,"presented_layout":viewer.presented_layout,"image":image_path,"width":image.get_width(),"height":image.get_height()}))
func graphics_probe() -> void:
	var path := str(ProjectSettings.get_setting("application/run/main_scene"))
	var packed := load(path) as PackedScene
	check(packed!=null,"normal C# main scene opens for Godot picture evidence")
	if packed:
		var scene: Node=packed.instantiate(); root.add_child(scene); current_scene=scene
		var world: Node=scene.get_node_or_null("Environment")
		check(world is MjRuntimeWorld,"C# main scene retains its real author world")
		if world is MjRuntimeWorld and await settled(world):
			check(await wait_for(func():return is_instance_valid(world.runtime_viewer) and not world.runtime_viewer.frame.is_empty()),"C# runtime viewer and frozen frame initialize")
			check_original_ui(world.runtime_viewer)
			await godot_picture(world,path)
		else: check(false,"C# world did not initialize for real picture")
		scene.queue_free()
		for unused in 5: await process_frame
	print("EXAMPLE_GRAPHICS_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(1 if failed else 0)
func g1_budget_roundtrip(scene: Node) -> void:
	const BUDGET_KEY := "rendering/mujoco_native_view/max_model_mib"
	var configured_limit: int=ProjectSettings.get_setting(BUDGET_KEY,64)
	var viewer: Node=scene.runtime_viewer
	var robot: Node=scene.get_node("G1_1")
	var was_paused: bool=scene.info().paused
	check(scene.set_paused(true),"G1 budget probe freezes dynamic state for an exact comparison")
	await process_frame
	check(await wait_for(func():return not viewer.frame.is_empty() and viewer.presented_frame_id>0 and viewer.presented_layout==viewer.layout_generation),"G1 admitted native frame is stable before budget probe")
	var original_camera: Transform3D=viewer.frame.camera.transform
	var original_joints: Dictionary=robot.state().joints.duplicate(true)
	var original_time: float=scene.info().time
	var original_revision: int=viewer.frame.revision
	var original_rid: RID=robot.model_rid
	var original_design_id: int=robot.design.get_instance_id()
	var original_space: RID=scene.space
	var transport_bytes: int=scene.native_view.latest.get("serialized_bytes",0)
	check(configured_limit==192 and transport_bytes>64*1048576 and transport_bytes<=192*1048576,"G1 real serialized model exceeds default 64 MiB and fits explicit 192 MiB")
	var cleanup: Dictionary=scene.stop_native_view()
	check(cleanup.get("cleanup_complete",false) and cleanup.get("live_textures",-1)==0,"G1 releases the admitted display resources before changing budget")
	ProjectSettings.set_setting(BUDGET_KEY,64)
	var started: bool=scene.start_native_view()
	check(started,"G1 default-budget admission attempt reaches the real display adapter")
	var fallback := await wait_for(func():return not scene.native_view_active and not scene.native_view_error.is_empty() and scene.native_view.stopped)
	var fallback_reason: String=scene.native_view_error
	check(fallback and ProjectSettings.get_setting(BUDGET_KEY)==64 and fallback_reason.contains("configured transport limit"),"G1 default 64 MiB produces the actual configured-transport-limit fallback")
	check(await wait_for(func():return viewer.last_backend=="godot" and not viewer.frame.is_empty() and viewer.presented_frame_id>0 and viewer.presented_layout==viewer.layout_generation),"G1 fallback presents a valid interactive Godot frame")
	check(scene.visible and not scene.get_viewport().disable_3d and scene.rendering_status().contains("Godot"),"G1 budget failure restores the Godot picture with an explicit status reason")
	check(scene.info().paused and scene.info().time==original_time and robot.state().joints==original_joints,"G1 budget fallback preserves the authoritative paused state")
	check(scene.space==original_space and robot.model_rid==original_rid and robot.design.get_instance_id()==original_design_id and int(viewer.frame.get("revision",-1))==original_revision,"G1 budget fallback retains the world, author resource, model and revision")
	check(viewer.frame.camera.transform.is_equal_approx(original_camera),"G1 budget fallback preserves the current camera")
	var left: bool=viewer.left_panel.visible
	var right: bool=viewer.right_panel.visible
	root.gui_release_focus()
	await key(KEY_TAB)
	check(viewer.left_panel.visible!=left and viewer.right_panel.visible==right and not viewer.controls.visible,"G1 fallback retains original Tab sidebar interaction without F11")
	await key(KEY_TAB)
	var info_visible: bool=viewer.info_enabled
	await key(KEY_F2)
	check(viewer.info_enabled!=info_visible and not viewer.controls.visible,"G1 fallback retains original F2 Info without F11")
	await key(KEY_F2)
	ProjectSettings.set_setting(BUDGET_KEY,configured_limit)
	check(scene.start_native_view(),"G1 explicit 192 MiB admission can restart after fallback")
	var restored := await wait_for(func():return scene.native_view_active and viewer.last_backend=="native" and not viewer.frame.is_empty() and viewer.presented_frame_id>0 and viewer.presented_layout==viewer.layout_generation)
	check(restored and scene.native_view_error.is_empty(),"G1 explicit 192 MiB resumes actual native rendering")
	check(scene.info().paused and scene.info().time==original_time and robot.state().joints==original_joints and viewer.frame.camera.transform.is_equal_approx(original_camera),"G1 re-admission preserves the exact simulation state and camera")
	check(scene.set_paused(was_paused) and scene.info().paused==was_paused,"G1 budget round trip restores the caller's original run/pause mode")
	print("G1_BUDGET_RESULT ",JSON.stringify({"default_limit_mib":64,"explicit_limit_mib":configured_limit,"transport_bytes":transport_bytes,"default_fallback":fallback,"fallback_reason":fallback_reason,"native_restored":restored,"same_space":scene.space==original_space,"same_model":robot.model_rid==original_rid,"same_design":robot.design.get_instance_id()==original_design_id,"original_time":original_time,"camera":str(original_camera),"cleanup":cleanup}))
func run() -> void:
	if DisplayServer.get_name()!="headless": root.grab_focus(); DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "MuJoCo","project selects MuJoCo")
	check(not ProjectSettings.get_setting("physics/3d/run_on_separate_thread",false),"main-thread physics")
	check("res://addons/mujoco_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled",PackedStringArray()),"editor plugin enabled")
	if "--graphics-probe" in OS.get_cmdline_user_args():
		await graphics_probe(); return
	var paths := [str(ProjectSettings.get_setting("application/run/main_scene"))]
	if ProjectSettings.get_setting("application/config/name") == "MuJoCo Editable Pendulum": paths = ["res://Main.tscn","res://ChaosPendulum.tscn","res://VisualDebug.tscn"]
	for path in paths:
		var packed := load(path) as PackedScene
		check(packed != null,"saved scene opens: "+path)
		if not packed: continue
		var scene: Node = packed.instantiate(); root.add_child(scene)
		check(scene is MjRuntimeWorld and scene.world_design != null,"scene owns author world")
		var registration_failed := false
		for node in preload("res://addons/godot_mujoco/model/world_layout.gd").nodes(scene):
			if node is MjModelInstance:
				check(node.model_rid.is_valid(),"model registered: "+str(node.name)+" "+node.last_error)
				registration_failed = registration_failed or not node.model_rid.is_valid()
		if registration_failed:
			scene.queue_free(); await process_frame; continue
		if not await settled(scene):
			check(false,"background startup: "+str(scene.info().get("last_error")))
			scene.queue_free(); await process_frame; continue
		check(is_instance_valid(scene.runtime_viewer) and not scene.runtime_viewer.controls.visible,"shared viewer installed with Godot F11 extras initially closed")
		var viewer_deadline := Time.get_ticks_msec()+30000
		while scene.runtime_viewer.frame.is_empty() and Time.get_ticks_msec()<viewer_deadline: await process_frame
		check(not scene.runtime_viewer.frame.is_empty(),"shared interaction frame available: "+scene.runtime_viewer.feedback)
		check_original_ui(scene.runtime_viewer)
		if ProjectSettings.get_setting("rendering/mujoco_native_view/renderer",-1)==1 and DisplayServer.get_name()!="headless":
			var deadline := Time.get_ticks_msec()+30000
			while not scene.native_view_active and scene.native_view_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
			check(scene.native_view_active,"real native renderer active: "+scene.native_view_error)
			if scene.native_view_active:
				check(scene.native_view.latest.get("authoritative_scene",false) and scene.native_view.latest.get("bridge_step_calls",-1)==0 and scene.native_view.latest.get("gl_errors",-1)==0,"native scene uses real data without extra integration or GL errors")
				if scene.name=="PassiveG1Gallery": await g1_budget_roundtrip(scene)
		elif DisplayServer.get_name()!="headless":
			await godot_picture(scene,path)
		check(not scene.editor_connected,"standalone has no design editor")
		check(scene.request_editor_design({"op":"duplicate_model"}) == 0,"standalone design requests disabled")
		var initial_y := 0.0
		if scene.name == "PassiveG1Gallery":
			initial_y = scene.get_node("G1_1").state().bodies.pelvis.transform.origin.y
		check(scene.set_paused(false),"simulation can start after compilation")
		for frame in 360: await physics_frame; await process_frame
		var info: Dictionary = scene.info()
		check(info.time>1.0,"real shared simulation advances")
		check(info.warning_count==0,"no native warnings")
		var models := []
		for node in preload("res://addons/godot_mujoco/model/world_layout.gd").nodes(scene):
			if node is MjModelInstance: models.append(node)
		for model in models:
			check(model.design!=null and not "model" in model,"formal author source replaces packaged runtime model")
			check(not model.author_scene.nodes.is_empty(),"semantic body/geom/joint hierarchy")
			check(model.visuals.size()==model.design.cached_geometry.size(),"all persisted visual meshes loaded")
		match String(scene.name):
			"ShapeGallery":
				check(scene.get_node("Model").state().joints.size()==scene.get_node("Model").design.entities().filter(func(e):return e.kind=="joint").size(),"current authored joints are all simulated")
				check(info.ncon>0,"shapes contact floor")
			"PassiveG1Gallery":
				var robot = scene.get_node("G1_1")
				check(robot.state().joints.size()==30 and info.nu==0,"one free base and 29 passive hinges")
				check(robot.state().bodies.pelvis.transform.origin.y<initial_y-.3,"single G1 falls under gravity")
				check(scene.runtime_viewer.extension_help.has("gallery"),"G1 help registered in shared viewer")
				check(not scene.get_node("DisplayControls").has_method("request_add"),"runtime G1 design button removed")
				check(scene.get_node("Heightfield").get_child_count()>0,"saved extra terrain retained")
			"SdfTerrainWorld":
				var map = scene.get_node("Map")
				check(map.get_node("DisplayControls").slice.disabled==scene.native_view_active,"SDF slice availability explains the active renderer limitation")
				check(map.native_rids.size()==3 and map.last_error.is_empty(),"three saved SDF chunks")
				for rid in map.native_rids:
					var geometry: Array = PhysicsServer3D.call("scene_geometry",scene.space,rid)
					check(not geometry.is_empty() and geometry.all(func(g):return g.type==8),"actual native SDF")
				check(absf(map.get_node("PitBall").position.y+.23)<.04,"concave pit contacts preserved")
			"Main":
				if path.ends_with("ChaosPendulum.tscn"):
					check(models[0].state().joints.size()==2,"chaotic double pendulum in shared world")
				elif path.ends_with("VisualDebug.tscn"):
					check(models[0].state().joints.size()==4 and info.ncon>0,"four balls contact floor")
					check(not info.contact_details.is_empty() and info.contact_details[0].force is Vector3,"debug contact world force available")
				elif not models.is_empty():
					check(absf(models[0].state().joints.hinge.qpos[0])>.00001,"motor-driven pendulum moves")
					check(models[0].state().joints.hinge.anchor is Vector3,"world joint anchor and axis available")
				else: check(scene.get_node("Ball").position.y<1.,"template ball contacts native floor")
		scene.queue_free(); await process_frame; await process_frame
	print("EXAMPLE_PROJECT_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(1 if failed else 0)
