extends RefCounted
## Observable UI boundaries and actual input against the running shared viewer.
## Keeps GUI evidence separate from the existing physics/ownership regression.
const LEFT := ["File","Option","Simulation","Watch","Physics","Rendering","Visualization","Group enable","Logging"]
const RIGHT := ["Joint","Control","Equality"]
const ALT_KEYS := [KEY_F,KEY_O,KEY_S,KEY_W,KEY_P,KEY_R,KEY_V,KEY_G,KEY_L,KEY_J,KEY_C,KEY_E]
var test
var viewer: Node
var extras: Node
var captures: Array = []
var layout_samples: Array = []
var layout_events: Array = []

func check(ok: bool, name: String) -> void:
	test.check(ok,name)

func settle() -> bool:
	var result: bool=await test.wait_for(func():return viewer._session.presented_frame_id>0 and viewer._session.presented_layout==viewer._session.layout_generation and viewer._session.pending.is_empty() and viewer.read_state().get("presentation",{}).get("ready",false),20)
	if not result:
		var diagnostic := {"frame":viewer._session.presented_frame_id,"presented_layout":viewer._session.presented_layout,"layout":viewer._session.layout_generation,"pending":viewer._session.pending,"consumer_status":viewer.status,"error":viewer.last_error,"frame_retiring":viewer._session.frames_retiring,"retire_request":viewer._session.frame_retire_request,"retire_target":viewer._session._retire_target,"seeded_revision":viewer._session.seeded_revision,"initial_camera_required":viewer._session._initial_camera_required,"camera_sync_request":viewer._session._camera_sync_request,"camera_sync_error":viewer._session.camera_sync_error,"camera_control":viewer._session.camera_control,"packet_frame":viewer._session.frame.get("frame_id",-1),"packet_revision":viewer._session.frame.get("revision",-1),"known_revision":viewer._session.known_revision,"world_revision":viewer.bound_world.info().get("revision",-1),"applied_layout":viewer._session.applied_layout,"consumer_instance":viewer._session.consumer.get_instance_id() if is_instance_valid(viewer._session.consumer) else -1,"session_process_delta":viewer._session.get_process_delta_time(),"session_processing":viewer._session.is_processing(),"source_region":str(viewer._session.render_rect_in_source()),"component_region":str(viewer._last_region),"actual_ui_region":str(viewer.ui.render_region.get_global_rect()),"layout_pending":viewer._layout_pending,"layout_event_count":layout_events.size(),"recent_layout_events":layout_events.slice(-10)}
		print("UI_SETTLE_TIMEOUT ",JSON.stringify(diagnostic))
		FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("ui-settle-timeout.json"),FileAccess.WRITE).store_string(JSON.stringify(diagnostic,"  "))
	return result

func capture(label: String) -> void:
	check(await settle(),"displayed frame matches layout for "+label)
	if DisplayServer.get_name()=="headless": return
	await test.process_frame
	await RenderingServer.frame_post_draw
	var folder: String=OS.get_environment("GMJ_VIEWER_OUT").path_join("ui")
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(label+".png")
	var code: int=test.root.get_texture().get_image().save_png(path)
	check(code==OK,"capture actual "+label+" UI")
	captures.append({"name":label,"file":path,"native":test.native,"native_active":viewer.bound_world.native_view_active,"world":viewer.bound_world.get_instance_id(),"left":viewer.ui.left_panel.visible,"right":viewer.ui.right_panel.visible,"extras":extras.ui.controls.visible,"help":viewer.ui.windows.help.visible,"info":viewer.ui.info_enabled,"profiler":viewer.ui.windows.profiler.visible,"sensors":viewer.ui.windows.sensors.visible,"render_rect":str(viewer.ui.render_rect),"outer_rect":str(viewer.ui.outer_rect),"layout":viewer._session.layout_generation,"presented_layout":viewer._session.presented_layout,"revision":viewer._session.presented_revision,"frame":viewer._session.presented_frame_id,"system_windows":DisplayServer.get_window_list().size()})

func run(tree) -> void:
	test=tree; viewer=test.viewer; extras=test.extras
	viewer.ui.layout_changed.connect(func():
		if not is_instance_valid(viewer.ui) or not is_instance_valid(viewer._session):return
		layout_events.append({"time":Time.get_ticks_msec(),"generation":viewer._session.layout_generation,"region":str(viewer.ui.render_region.get_global_rect()),"left":viewer.ui.left_panel.visible,"right":viewer.ui.right_panel.visible})
		if layout_events.size()>100:layout_events.pop_front())
	check(viewer.ui.left_panel.visible and viewer.ui.right_panel.visible,"A01 original left and right panels initially visible")
	var ordered := true
	for titles in [LEFT,RIGHT]:
		for index in range(1,titles.size()):
			if viewer.ui.sections[titles[index-1]].button.get_index()>=viewer.ui.sections[titles[index]].button.get_index(): ordered=false
	check(ordered,"A01 native group order is left nine followed by right three")
	for title in LEFT+RIGHT:
		var section: Dictionary=viewer.ui.sections[title]
		var panel: Control=viewer.ui.left_panel if title in LEFT else viewer.ui.right_panel
		check(panel.is_ancestor_of(section.button) and panel.is_ancestor_of(section.box),"A01 "+title+" belongs to its original sidebar")
		check(not extras.ui.controls.is_ancestor_of(section.button),"A01 "+title+" is independent of F11")
	check(not extras.ui.extras_sections.is_empty() and not extras.ui.extras_sections.has("Simulation") and not extras.ui.extras_sections.has("Rendering") and not extras.ui.extras_sections.has("Watch"),"A01 F11 owns Godot extras rather than native menus")
	for name in ["help","info","profiler","sensors"]:
		check(viewer.ui.windows[name] is Control and not viewer.ui.windows[name] is Window,"A04 "+name+" is a scene overlay without a window titlebar")
		check(not viewer.ui.windows[name].visible,"A04 "+name+" initially closed")
	check(viewer.ui.render_region.size.x<viewer.ui.outer_rect.size.x,"A09 initial sidebars reserve central rendering space")
	var saved_h: float=viewer._session.camera.h_offset
	var saved_v: float=viewer._session.camera.v_offset
	viewer._session.camera.h_offset=.2; viewer._session.camera.v_offset=.1
	var optical_seed: Dictionary=viewer._session.capture_camera_seed()
	check(optical_seed.transform.is_equal_approx(viewer._session.camera.get_camera_transform()),"A09 authored seed includes Godot optical horizontal and vertical offsets")
	viewer._session.camera.h_offset=saved_h; viewer._session.camera.v_offset=saved_v
	await settle()
	check(viewer.ui.feedback.is_empty(),"A01 initial native UI synchronization sends no invalid commands")
	await capture("default")
	var initial_time: float=test.world.info().time
	test.root.gui_release_focus()
	var states := [[KEY_TAB,false,false,true,"sidebars-01"],[KEY_TAB,true,false,false,"sidebars-00"],[KEY_TAB,false,true,false,"sidebars-10"],[KEY_TAB,true,true,true,"sidebars-11"]]
	for row in states:
		await test.key(row[0],false,row[1])
		check(viewer.ui.left_panel.visible==row[2] and viewer.ui.right_panel.visible==row[3],"A02 real Tab/Shift+Tab yields "+str(row[4]))
		check(not extras.ui.controls.visible,"A02 sidebar shortcut leaves F11 closed")
		await capture(row[4])
		if "--layout-diagnostic" in OS.get_cmdline_user_args():
			write_evidence();return
	check(test.world.info().paused and test.world.info().time==initial_time,"A08 menu visibility does not advance a paused simulation")
	for i in ALT_KEYS.size():
		var title: String=(LEFT+RIGHT)[i]
		var before: bool=viewer.ui.sections[title].button.button_pressed
		await test.key(ALT_KEYS[i],false,false,true)
		check(viewer.ui.sections[title].button.button_pressed!=before,"A03 Alt shortcut toggles original "+title+" section")
		check(not extras.ui.controls.visible,"A03 Alt "+title+" never opens F11")
		await test.key(ALT_KEYS[i],false,false,true)
	if DisplayServer.get_name()!="headless":
		var section_states := {}
		for title in LEFT+RIGHT: section_states[title]=viewer.ui.sections[title].button.button_pressed
		viewer.ui.left_panel.scroll_vertical=0
		await test.process_frame
		await click_pixel(viewer.ui.sections.File.button.get_global_rect().get_center())
		var left_state: bool=viewer.ui.sections.File.button.button_pressed
		check(LEFT.all(func(title):return viewer.ui.sections[title].button.button_pressed==left_state),"A03 real section double-click folds or unfolds its original sidebar")
		check(RIGHT.all(func(title):return viewer.ui.sections[title].button.button_pressed==section_states[title]),"A03 section double-click leaves the opposite sidebar unchanged")
		for title in section_states: viewer.ui.sections[title].button.button_pressed=section_states[title]
	test.root.gui_release_focus()
	for row in [[KEY_F1,"help"],[KEY_F2,"info"],[KEY_F3,"profiler"],[KEY_F4,"sensors"]]:
		await test.key(row[0])
		check(viewer.ui.windows[row[1]].visible and not extras.ui.controls.visible,"A04 "+row[1]+" opens without F11")
		check(viewer.ui.left_panel.visible and viewer.ui.right_panel.visible,"A04 overlay leaves sidebars visible")
		await capture(row[1])
		await test.key(row[0])
		check(not viewer.ui.windows[row[1]].visible,"A04 "+row[1]+" closes independently")
	await test.key(KEY_F3); await test.key(KEY_F4)
	await test.process_frame; await test.process_frame
	check(not viewer.ui.windows.profiler.get_global_rect().intersects(viewer.ui.windows.sensors.get_global_rect()),"A04 simultaneous Profiler and Sensors occupy independent original figure regions")
	extras.ui.refresh_hud()
	check(not extras.ui.hud.get_global_rect().intersects(viewer.ui.run_label.get_global_rect()),"A05 Godot FPS remains readable beside native PAUSE and analysis figures")
	check(not extras.ui.hud.get_global_rect().intersects(viewer.ui.windows.profiler.get_global_rect()),"A05 Godot FPS avoids the actual visible Profiler figure")
	check(not extras.ui.hud.get_global_rect().intersects(viewer.ui.windows.sensors.get_global_rect()),"A05 Godot FPS avoids the actual visible Sensors figure")
	await capture("profiler-sensors")
	await test.key(KEY_F3); await test.key(KEY_F4)
	viewer.show_info(true); extras.show_performance(false)
	check(viewer.ui.info_enabled and viewer.ui.windows.info.visible and not extras.ui.hud.visible,"A05 disabling Godot performance leaves native Info visible")
	viewer.save_view_preferences(true);extras.save_view_preferences(true)
	var saved := ConfigFile.new()
	var extra_saved := ConfigFile.new()
	check(saved.load(viewer._config_path)==OK and extra_saved.load(extras._config_path)==OK and viewer._config_path!=extras._config_path and saved.get_value("view","info",false) and not saved.has_section_key("view","performance") and not extra_saved.get_value("view","performance",true),"A12 independent original Info and Godot performance preferences persist")
	check(not saved.has_section_key("ui","overlay") and not saved.has_section_key("metrics","simulation"),"A12 saved preferences remove obsolete combined-overlay keys")
	await test.key(KEY_F2)
	check(not viewer.ui.info_enabled and not extras.ui.overlay_enabled,"A05 F2 leaves disabled Godot performance disabled")
	await test.key(KEY_F2)
	extras.show_extras(true)
	check(viewer.ui.info_enabled and viewer.ui.left_panel.visible and viewer.ui.right_panel.visible,"A05 F11 opens without changing native visibility")
	extras.show_performance(true)
	check(viewer.ui.info_enabled and extras.ui.overlay_enabled,"A05 native Info and Godot performance can coexist")
	await capture("godot-extras")
	extras.ui.extras_sections.Tools.button.button_pressed=true
	var edit: LineEdit=extras.ui.fields.step_count.get_line_edit()
	edit.grab_focus()
	var old_focus: Control=extras.ui.controls.gui_get_focus_owner()
	await test.key(KEY_TAB)
	check(extras.ui.controls.gui_get_focus_owner()!=old_focus and viewer.ui.left_panel.visible and viewer.ui.right_panel.visible,"A07 Tab in Godot extras moves focus without hiding sidebars")
	edit.grab_focus()
	await test.key(KEY_F11)
	check(not extras.ui.controls.visible and viewer.ui.info_enabled,"A07 F11 closes with Godot text field focused")
	extras.show_extras(true)
	var selectors: Array[Node]=extras.ui.controls.find_children("*","OptionButton",true,false)
	if not selectors.is_empty():
		var selector: OptionButton=selectors[0]
		selector.get_popup().popup()
		await test.process_frame
		await test.key(KEY_F11)
		check(not extras.ui.controls.visible,"A07 F11 closes with an embedded Godot dropdown focused")
		# Preserve the failed focus assertion while keeping a popup from masking
		# all subsequent scene-input and equality checks.
		selector.get_popup().hide()
		extras.show_extras(false)
	else:
		extras.show_extras(false)
	viewer.show_info(false)
	# Native text editing has its own focus scope and works while F11 stays closed.
	viewer.ui.sections.Watch.button.button_pressed=true
	viewer.ui.fields.watch_edit.grab_focus()
	var original_camera: Transform3D=viewer._session.frame.camera.transform
	var original_joint_flag: bool=viewer._session.frame.settings.vis[2]
	await test.key(KEY_J)
	await test.key(KEY_A,true)
	check(viewer._session.frame.settings.vis[2]==original_joint_flag and viewer._session.frame.camera.transform.is_equal_approx(original_camera),"A03 native Watch text consumes characters and Ctrl+A")
	test.root.gui_release_focus()
	viewer.ui.watch_field="qpos"; viewer.ui.watch_index=0; viewer._update_inspection()
	check(await test.wait_for(func():return viewer.ui.watch_label.text.contains("qpos[0]") and not viewer.ui.watch_label.text.contains("等待")),"A06 Watch refreshes real data with F11 closed")
	viewer.ui.watch_index=100000000; viewer._update_inspection()
	check(await test.wait_for(func():return viewer._session.details.get("watch_index",-1)==100000000 and not str(viewer._session.details.get("watch_error","")).is_empty()),"A06 Watch rejects an out-of-range index with feedback")
	viewer.ui.watch_field="not_a_numeric_field"; viewer.ui.watch_index=0; viewer._update_inspection()
	check(await test.wait_for(func():return viewer._session.details.get("watch_field","")=="not_a_numeric_field" and not str(viewer._session.details.get("watch_error","")).is_empty()),"A06 Watch rejects an unknown field without reading memory")
	viewer.ui.watch_field="qpos"; viewer.ui.watch_index=0; viewer._update_inspection()
	check(await test.wait_for(func():return viewer.ui.fields.has("log_console")),"A06 Logging controls are populated with F11 closed")
	for title in RIGHT: viewer.ui.sections[title].button.button_pressed=true
	check(await test.wait_for(func():return viewer.ui.fields.has("control:0") and viewer.ui.fields.has("equality:0") and not viewer._session.details.get("joints",[]).is_empty()),"A06 native editing widgets populate without F11")
	var robot: Node=test.world.get_node("Robot")
	var control: Range=viewer.ui.fields.get("control:0")
	check(is_instance_valid(control),"A06 Control exposes a native scalar range widget")
	if is_instance_valid(control):
		control.value=.12
		check(await test.wait_for(func():return abs(robot.state().controls.drive-.12)<1e-8 and abs(control.value-.12)<1e-8),"A06 original Control widget edits authoritative actuator input")
		control.value=0
		check(await test.wait_for(func():return robot.state().controls.drive==0),"A06 original Control widget resets actual input")
	if not viewer._session.details.get("joints",[]).is_empty():
		var joint: Range=viewer.ui.fields.get("joint:%d" % int(viewer._session.details.joints[0].id))
		check(is_instance_valid(joint),"A06 Joint exposes a paused scalar range widget")
		if is_instance_valid(joint):
			joint.value=.15
			check(await test.wait_for(func():return abs(robot.state().joints.hinge.qpos[0]-.15)<1e-8),"A06 original Joint widget edits authoritative paused position")
	var equality: CheckBox=viewer.ui.fields.get("equality:0")
	if is_instance_valid(equality):
		equality.button_pressed=true
		check(await test.wait_for(func():return viewer._session.details.equalities[0].value and equality.button_pressed),"A06 original Equality widget enables actual constraint")
		equality.button_pressed=false
		check(await test.wait_for(func():return not viewer._session.details.equalities[0].value and not equality.button_pressed),"A06 original Equality widget disables actual constraint")
	await test.issue({"action":"reset_initial"})
	var ui_catalog: Array=viewer.ui.get_native_ui_catalog()
	check(ui_catalog.any(func(row):return row.section=="Logging" and row.name=="Info topics" and row.item=="SEPARATOR"),"A10 Logging retains original foldable Info topics subsection")
	var initial_depth: int=viewer._session.frame.settings.get("bvh_depth",0)
	await test.issue({"action":"tree_depth","value":3})
	check(await test.wait_for(func():return viewer._session.frame.settings.get("bvh_depth",0)==3 and int(viewer.ui.fields.tree_depth.value)==3),"A10 Tree depth widget follows authoritative display settings")
	viewer.save_view_preferences(true)
	await test.issue({"action":"tree_depth","value":1})
	viewer._restore_display_preferences()
	var queued_count: int=viewer._preference_commands.size()
	viewer._restore_display_preferences()
	check(viewer._preference_commands.size()==queued_count,"A14 repeated preference restoration keeps one bounded latest queue")
	check(await test.wait_for(func():return viewer._preference_commands.is_empty() and viewer._session.pending.is_empty() and viewer._session.frame.settings.get("bvh_depth",0)==3 and int(viewer.ui.fields.tree_depth.value)==3),"A12 saved Tree depth restores through the shared command boundary")
	await test.issue({"action":"tree_depth","value":initial_depth})
	viewer.save_view_preferences(true)
	# Native display changes must survive without opening Godot extras, saving
	# explicitly, toggling a menu, or exiting the game.
	await test.issue({"action":"tree_depth","value":4})
	var read_saved_depth := func():
		var current := ConfigFile.new()
		if current.load(viewer._config_path)!=OK: return false
		var settings: Dictionary=current.get_value("display","settings",{})
		return settings.get("bvh_depth",-1)==4
	check(not extras.ui.controls.visible and await test.wait_for(read_saved_depth),"A12 native display change autosaves with F11 closed")
	var autosaved := ConfigFile.new(); autosaved.load(viewer._config_path)
	var contains_dynamics := false
	for section in autosaved.get_sections():
		for key in autosaved.get_section_keys(section):
			if key in ["qpos","qvel","ctrl","time","state","snapshot"]: contains_dynamics=true
	var saved_display: Dictionary=autosaved.get_value("display","settings",{})
	for key in saved_display:
		if key in ["qpos","qvel","ctrl","time","state","snapshot"]: contains_dynamics=true
	check(not contains_dynamics,"A12 preferences contain display settings without simulation dynamics")
	await test.issue({"action":"tree_depth","value":initial_depth})
	for code in [KEY_F8,KEY_F9,KEY_F10,KEY_F12]:
		var event := InputEventKey.new(); event.keycode=code; event.pressed=true
		check(not viewer.key_input(event),"A07 viewer preserves Godot debugger key "+str(code))
	await layout_picking("root",test.world.get_node("Robot").state().bodies.ball.transform.origin)
	var initial_size: Vector2i=test.root.size
	test.root.size=Vector2i(920,680)
	await test.process_frame
	await test.process_frame
	await layout_picking("resized",test.world.get_node("Robot").state().bodies.ball.transform.origin)
	test.root.size=initial_size
	await test.process_frame
	viewer.show_native_panels(true,true)
	await settle()
	write_evidence()

func project_normalized(point: Vector3) -> Vector2:
	# Public frozen frustum contract, independent of the host Camera3D crop.
	var camera: Dictionary=viewer._session.frame.camera
	var local: Vector3=camera.transform.affine_inverse()*point
	var projected := Vector2(local.x,local.y)
	if not camera.orthographic: projected*=float(camera.near)/-local.z
	var height: float=camera.size
	var region: Rect2=viewer._session.render_rect_in_source()
	var width: float=height*maxf(region.size.x,1)/maxf(region.size.y,1)
	return Vector2(.5+(projected.x-camera.offset.x)/width,.5-(projected.y-camera.offset.y)/height)

func click(point: Vector2) -> void:
	# Input.parse_input_event drives viewport GUI routing rather than calling send.
	var pixel: Vector2=viewer.ui.render_region.get_global_rect().position+point*viewer.ui.render_region.size
	await click_pixel(pixel)

func click_pixel(pixel: Vector2) -> void:
	for unused in 2:
		var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=pixel; event.global_position=pixel; event.double_click=unused==1
		Input.parse_input_event(event)
		await test.process_frame
		event=event.duplicate(); event.pressed=false; Input.parse_input_event(event)
		await test.process_frame

func layout_picking(stage: String, point: Vector3) -> void:
	viewer=test.viewer
	test.root.gui_release_focus()
	for pair in [[false,false],[true,false],[false,true],[true,true]]:
		var label := "%s/%d%d" % [stage,int(pair[0]),int(pair[1])]
		var changed: bool=viewer.ui.left_panel.visible!=pair[0] or viewer.ui.right_panel.visible!=pair[1]
		viewer.show_native_panels(pair[0],pair[1])
		if changed:
			var stale: int=viewer._session.send({"action":"select","button":1,"x":.5,"y":.5,"aspect":test.render_aspect()})
			check(stale==0,"A09 layout transition rejects old displayed-frame pick "+label)
		var ready: bool=await settle()
		check(ready,"A09 matching presented frame ready "+label)
		if not ready:
			var diagnostic := {"name":label,"layout":viewer._session.layout_generation,"presented_layout":viewer._session.presented_layout,"frame":viewer._session.presented_frame_id,"render_rect":str(viewer.ui.render_rect),"feedback":viewer.ui.feedback,"native_active":viewer.bound_world.native_view_active,"native_error":viewer.bound_world.native_view_error,"stats":viewer._session.frame.get("stats",{})}
			if is_instance_valid(viewer.bound_world.native_view): diagnostic["native_latest"]=viewer.bound_world.native_view.latest.duplicate()
			print("UI_LAYOUT_STATE ",JSON.stringify(diagnostic))
			layout_samples.append(diagnostic)
			write_evidence()
			return
		var expected: Rect2=viewer.ui.get_node("MainLayout").get_global_rect()
		if pair[0]: expected.position.x+=viewer.ui.left_panel.size.x; expected.size.x-=viewer.ui.left_panel.size.x
		if pair[1]: expected.size.x-=viewer.ui.right_panel.size.x
		var rect_agrees: bool=viewer.ui.render_region.get_global_rect().is_equal_approx(expected)
		check(rect_agrees,"A09 input and reserved sidebars agree "+label)
		if not rect_agrees: print("UI_LAYOUT_RECT ",JSON.stringify({"name":label,"expected":str(expected),"actual":str(viewer.ui.render_region.get_global_rect()),"outer":str(viewer.ui.outer_rect),"left":str(viewer.ui.left_panel.get_global_rect()),"right":str(viewer.ui.right_panel.get_global_rect())}))
		var normalized := project_normalized(point)
		check(Rect2(Vector2.ZERO,Vector2.ONE).has_point(normalized),"A09 test body lies inside actual central frustum "+label)
		if DisplayServer.get_name()!="headless" and not test.native:
			var region_pixel: Vector2=viewer._session._godot_camera.unproject_position(point)
			var source_rect: Rect2=viewer._session.render_rect_in_source()
			var actual_uv: Vector2=region_pixel/source_rect.size
			check(actual_uv.distance_to(normalized)<.003,"A09 rendered Godot projection matches published picking frustum "+label)
		if DisplayServer.get_name()!="headless":
			var cleared: Dictionary=await test.issue({"action":"select","button":1,"x":.02,"y":.98,"aspect":test.render_aspect()})
			var was_cleared: bool=cleared.get("success",false) and int(viewer._session.frame.selected_body)==0
			check(was_cleared,"A09 clear selection before routed mouse input "+label)
			if was_cleared:
				await click(normalized)
				check(await test.wait_for(func():return viewer._session.pending.is_empty() and str(viewer._session.frame.selected_name).ends_with("_ball")),"A09 real displayed-pixel double click selects the same body "+label)
		else:
			await test.issue({"action":"select","button":1,"x":normalized.x,"y":1-normalized.y,"aspect":test.render_aspect()})
			check(str(viewer._session.frame.selected_name).ends_with("_ball"),"A09 headless frozen-frame pick selects expected body "+label)
		if test.native:
			var latest: Dictionary=viewer.bound_world.native_view.latest
			check(int(latest.get("width",0))==int(viewer._session.render_rect_in_source().size.x) and int(latest.get("height",0))==int(viewer._session.render_rect_in_source().size.y),"A09 native framebuffer matches central render size "+label)
		layout_samples.append({"name":label,"world":viewer.bound_world.get_instance_id(),"revision":viewer._session.presented_revision,"frame":viewer._session.presented_frame_id,"normalized":str(normalized),"render_rect":str(viewer.ui.render_rect),"source_rect":str(viewer._session.render_rect_in_source()),"left_rect":str(viewer.ui.left_panel.get_global_rect()),"right_rect":str(viewer.ui.right_panel.get_global_rect()),"selected":viewer._session.frame.selected_name,"camera":str(viewer._session.frame.camera),"layout":viewer._session.layout_generation,"presented_layout":viewer._session.presented_layout})
	viewer.show_native_panels(true,true)
	await settle()
	write_evidence()

func write_evidence() -> void:
	var out: String=OS.get_environment("GMJ_VIEWER_OUT")
	FileAccess.open(out.path_join("ui-evidence.json"),FileAccess.WRITE).store_string(JSON.stringify({"native_requested":test.native,"display":DisplayServer.get_name(),"captures":captures,"layout_samples":layout_samples},"  "))
	FileAccess.open(out.path_join("native-ui-catalog.json"),FileAccess.WRITE).store_string(JSON.stringify(viewer.ui.get_native_ui_catalog(),"  "))
