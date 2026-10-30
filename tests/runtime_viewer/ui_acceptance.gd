extends RefCounted
## Observable UI boundaries and actual input against the running shared viewer.
## Keeps GUI evidence separate from the existing physics/ownership regression.
const LEFT := ["File","Option","Simulation","Watch","Physics","Rendering","Visualization","Group enable","Logging"]
const RIGHT := ["Joint","Control","Equality"]
const ALT_KEYS := [KEY_F,KEY_O,KEY_S,KEY_W,KEY_P,KEY_R,KEY_V,KEY_G,KEY_L,KEY_J,KEY_C,KEY_E]
var test
var viewer: Node
var captures: Array = []
var layout_samples: Array = []

func check(ok: bool, name: String) -> void:
	test.check(ok,name)

func settle() -> bool:
	return await test.wait_for(func():return viewer.presented_frame_id>0 and viewer.presented_layout==viewer.layout_generation and viewer.pending.is_empty(),20)

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
	captures.append({"name":label,"file":path,"native":test.native,"native_active":viewer.runtime_world.native_view_active,"world":viewer.runtime_world.get_instance_id(),"left":viewer.left_panel.visible,"right":viewer.right_panel.visible,"extras":viewer.controls.visible,"help":viewer.windows.help.visible,"info":viewer.info_enabled,"profiler":viewer.windows.profiler.visible,"sensors":viewer.windows.sensors.visible,"render_rect":str(viewer.render_rect),"outer_rect":str(viewer.outer_rect),"layout":viewer.layout_generation,"presented_layout":viewer.presented_layout,"revision":viewer.presented_revision,"frame":viewer.presented_frame_id,"system_windows":DisplayServer.get_window_list().size()})

func run(tree) -> void:
	test=tree; viewer=test.viewer
	check(viewer.left_panel.visible and viewer.right_panel.visible,"A01 original left and right panels initially visible")
	check(viewer.sections.keys()==LEFT+RIGHT,"A01 native group order is left nine followed by right three")
	for title in LEFT+RIGHT:
		var section: Dictionary=viewer.sections[title]
		var panel: Control=viewer.left_panel if title in LEFT else viewer.right_panel
		check(panel.is_ancestor_of(section.button) and panel.is_ancestor_of(section.box),"A01 "+title+" belongs to its original sidebar")
		check(not viewer.controls.is_ancestor_of(section.button),"A01 "+title+" is independent of F11")
	check(not viewer.extras_sections.is_empty() and not viewer.extras_sections.has("Simulation") and not viewer.extras_sections.has("Rendering") and not viewer.extras_sections.has("Watch"),"A01 F11 owns Godot extras rather than native menus")
	for name in ["help","info","profiler","sensors"]:
		check(viewer.windows[name] is Control and not viewer.windows[name] is Window,"A04 "+name+" is a scene overlay without a window titlebar")
		check(not viewer.windows[name].visible,"A04 "+name+" initially closed")
	check(viewer.scene_input.size.x<viewer.outer_rect.size.x,"A09 initial sidebars reserve central rendering space")
	var saved_h: float=viewer.camera.h_offset
	var saved_v: float=viewer.camera.v_offset
	viewer.camera.h_offset=.2; viewer.camera.v_offset=.1
	var optical_seed: Dictionary=viewer.capture_camera_seed()
	check(optical_seed.transform.is_equal_approx(viewer.camera.get_camera_transform()),"A09 authored seed includes Godot optical horizontal and vertical offsets")
	viewer.camera.h_offset=saved_h; viewer.camera.v_offset=saved_v
	await settle()
	check(viewer.feedback.is_empty(),"A01 initial native UI synchronization sends no invalid commands")
	await capture("default")
	var initial_time: float=test.world.info().time
	test.root.gui_release_focus()
	var states := [[KEY_TAB,false,false,true,"sidebars-01"],[KEY_TAB,true,false,false,"sidebars-00"],[KEY_TAB,false,true,false,"sidebars-10"],[KEY_TAB,true,true,true,"sidebars-11"]]
	for row in states:
		await test.key(row[0],false,row[1])
		check(viewer.left_panel.visible==row[2] and viewer.right_panel.visible==row[3],"A02 real Tab/Shift+Tab yields "+str(row[4]))
		check(not viewer.controls.visible,"A02 sidebar shortcut leaves F11 closed")
		await capture(row[4])
	check(test.world.info().paused and test.world.info().time==initial_time,"A08 menu visibility does not advance a paused simulation")
	for i in ALT_KEYS.size():
		var title: String=(LEFT+RIGHT)[i]
		var before: bool=viewer.sections[title].button.button_pressed
		await test.key(ALT_KEYS[i],false,false,true)
		check(viewer.sections[title].button.button_pressed!=before,"A03 Alt shortcut toggles original "+title+" section")
		check(not viewer.controls.visible,"A03 Alt "+title+" never opens F11")
		await test.key(ALT_KEYS[i],false,false,true)
	if DisplayServer.get_name()!="headless":
		var section_states := {}
		for title in LEFT+RIGHT: section_states[title]=viewer.sections[title].button.button_pressed
		viewer.left_panel.scroll_vertical=0
		await test.process_frame
		await click_pixel(viewer.sections.File.button.get_global_rect().get_center())
		var left_state: bool=viewer.sections.File.button.button_pressed
		check(LEFT.all(func(title):return viewer.sections[title].button.button_pressed==left_state),"A03 real section double-click folds or unfolds its original sidebar")
		check(RIGHT.all(func(title):return viewer.sections[title].button.button_pressed==section_states[title]),"A03 section double-click leaves the opposite sidebar unchanged")
		for title in section_states: viewer.sections[title].button.button_pressed=section_states[title]
	test.root.gui_release_focus()
	for row in [[KEY_F1,"help"],[KEY_F2,"info"],[KEY_F3,"profiler"],[KEY_F4,"sensors"]]:
		await test.key(row[0])
		check(viewer.windows[row[1]].visible and not viewer.controls.visible,"A04 "+row[1]+" opens without F11")
		check(viewer.left_panel.visible and viewer.right_panel.visible,"A04 overlay leaves sidebars visible")
		await capture(row[1])
		await test.key(row[0])
		check(not viewer.windows[row[1]].visible,"A04 "+row[1]+" closes independently")
	await test.key(KEY_F3); await test.key(KEY_F4)
	await test.process_frame; await test.process_frame
	check(not viewer.windows.profiler.get_global_rect().intersects(viewer.windows.sensors.get_global_rect()),"A04 simultaneous Profiler and Sensors occupy independent original figure regions")
	viewer.refresh_hud()
	check(not viewer.hud.get_global_rect().intersects(viewer.run_label.get_global_rect()),"A05 Godot FPS remains readable beside native PAUSE and analysis figures")
	await capture("profiler-sensors")
	await test.key(KEY_F3); await test.key(KEY_F4)
	viewer.set_info(true); viewer.set_overlay(false)
	check(viewer.info_enabled and viewer.windows.info.visible and not viewer.hud.visible,"A05 disabling Godot performance leaves native Info visible")
	viewer.save_preferences()
	var saved := ConfigFile.new()
	check(saved.load(viewer.config_path)==OK and saved.get_value("simulate_ui","info",false) and not saved.get_value("godot_ui","performance_overlay",true),"A12 independent original Info and Godot performance preferences persist")
	check(not saved.has_section_key("ui","overlay") and not saved.has_section_key("metrics","simulation"),"A12 saved preferences remove obsolete combined-overlay keys")
	await test.key(KEY_F2)
	check(not viewer.info_enabled and not viewer.overlay_enabled,"A05 F2 leaves disabled Godot performance disabled")
	await test.key(KEY_F2)
	viewer.set_controls_visible(true)
	check(viewer.info_enabled and viewer.left_panel.visible and viewer.right_panel.visible,"A05 F11 opens without changing native visibility")
	viewer.set_overlay(true)
	check(viewer.info_enabled and viewer.overlay_enabled,"A05 native Info and Godot performance can coexist")
	await capture("godot-extras")
	viewer.extras_sections.Tools.button.button_pressed=true
	var edit: LineEdit=viewer.fields.output_edit
	edit.grab_focus()
	var old_focus: Control=viewer.controls.gui_get_focus_owner()
	await test.key(KEY_TAB)
	check(viewer.controls.gui_get_focus_owner()!=old_focus and viewer.left_panel.visible and viewer.right_panel.visible,"A07 Tab in Godot extras moves focus without hiding sidebars")
	edit.grab_focus()
	await test.key(KEY_F11)
	check(not viewer.controls.visible and viewer.info_enabled,"A07 F11 closes with Godot text field focused")
	viewer.set_controls_visible(true)
	var selectors: Array[Node]=viewer.controls.find_children("*","OptionButton",true,false)
	if not selectors.is_empty():
		var selector: OptionButton=selectors[0]
		selector.get_popup().popup()
		await test.process_frame
		await test.key(KEY_F11)
		check(not viewer.controls.visible,"A07 F11 closes with an embedded Godot dropdown focused")
		# Preserve the failed focus assertion while keeping a popup from masking
		# all subsequent scene-input and equality checks.
		selector.get_popup().hide()
		viewer.set_controls_visible(false)
	else:
		viewer.set_controls_visible(false)
	viewer.set_info(false)
	# Native text editing has its own focus scope and works while F11 stays closed.
	viewer.sections.Watch.button.button_pressed=true
	viewer.fields.watch_edit.grab_focus()
	var original_camera: Transform3D=viewer.frame.camera.transform
	var original_joint_flag: bool=viewer.frame.settings.vis[2]
	await test.key(KEY_J)
	await test.key(KEY_A,true)
	check(viewer.frame.settings.vis[2]==original_joint_flag and viewer.frame.camera.transform.is_equal_approx(original_camera),"A03 native Watch text consumes characters and Ctrl+A")
	test.root.gui_release_focus()
	viewer.watch_field="qpos"; viewer.watch_index=0; viewer.inspect_due=true
	check(await test.wait_for(func():return viewer.watch_label.text.contains("qpos[0]") and not viewer.watch_label.text.contains("等待")),"A06 Watch refreshes real data with F11 closed")
	viewer.watch_index=100000000; viewer.inspect_due=true
	check(await test.wait_for(func():return viewer.details.get("watch_index",-1)==100000000 and not str(viewer.details.get("watch_error","")).is_empty()),"A06 Watch rejects an out-of-range index with feedback")
	viewer.watch_field="not_a_numeric_field"; viewer.watch_index=0; viewer.inspect_due=true
	check(await test.wait_for(func():return viewer.details.get("watch_field","")=="not_a_numeric_field" and not str(viewer.details.get("watch_error","")).is_empty()),"A06 Watch rejects an unknown field without reading memory")
	viewer.watch_field="qpos"; viewer.watch_index=0; viewer.inspect_due=true
	check(await test.wait_for(func():return viewer.fields.has("log_console")),"A06 Logging controls are populated with F11 closed")
	for title in RIGHT: viewer.sections[title].button.button_pressed=true
	check(await test.wait_for(func():return viewer.fields.has("control:0") and viewer.fields.has("equality:0") and not viewer.details.get("joints",[]).is_empty()),"A06 native editing widgets populate without F11")
	var robot: Node=test.world.get_node("Robot")
	var control: Range=viewer.fields.get("control:0")
	check(is_instance_valid(control),"A06 Control exposes a native scalar range widget")
	if is_instance_valid(control):
		control.value=.12
		check(await test.wait_for(func():return abs(robot.state().controls.drive-.12)<1e-8 and abs(control.value-.12)<1e-8),"A06 original Control widget edits authoritative actuator input")
		control.value=0
		check(await test.wait_for(func():return robot.state().controls.drive==0),"A06 original Control widget resets actual input")
	if not viewer.details.get("joints",[]).is_empty():
		var joint: Range=viewer.fields.get("joint:%d" % int(viewer.details.joints[0].id))
		check(is_instance_valid(joint),"A06 Joint exposes a paused scalar range widget")
		if is_instance_valid(joint):
			joint.value=.15
			check(await test.wait_for(func():return abs(robot.state().joints.hinge.qpos[0]-.15)<1e-8),"A06 original Joint widget edits authoritative paused position")
	var equality: CheckBox=viewer.fields.get("equality:0")
	if is_instance_valid(equality):
		equality.button_pressed=true
		check(await test.wait_for(func():return viewer.details.equalities[0].value and equality.button_pressed),"A06 original Equality widget enables actual constraint")
		equality.button_pressed=false
		check(await test.wait_for(func():return not viewer.details.equalities[0].value and not equality.button_pressed),"A06 original Equality widget disables actual constraint")
	await test.issue({"action":"reset_initial"})
	var ui_catalog: Array=viewer.get_native_ui_catalog()
	check(ui_catalog.any(func(row):return row.section=="Logging" and row.name=="Info topics" and row.item=="SEPARATOR"),"A10 Logging retains original foldable Info topics subsection")
	var initial_depth: int=viewer.frame.settings.get("bvh_depth",0)
	await test.issue({"action":"tree_depth","value":3})
	check(await test.wait_for(func():return viewer.frame.settings.get("bvh_depth",0)==3 and int(viewer.fields.tree_depth.value)==3),"A10 Tree depth widget follows authoritative display settings")
	viewer.save_preferences()
	await test.issue({"action":"tree_depth","value":1})
	viewer.queue_preferences()
	var queued_count: int=viewer.preference_queue.size()
	viewer.queue_preferences()
	check(viewer.preference_queue.size()==queued_count,"A14 repeated preference restoration keeps one bounded latest queue")
	check(await test.wait_for(func():return viewer.preference_queue.is_empty() and viewer.pending.is_empty() and viewer.frame.settings.get("bvh_depth",0)==3 and int(viewer.fields.tree_depth.value)==3),"A12 saved Tree depth restores through the shared command boundary")
	await test.issue({"action":"tree_depth","value":initial_depth})
	viewer.save_preferences()
	# Native display changes must survive without opening Godot extras, saving
	# explicitly, toggling a menu, or exiting the game.
	await test.issue({"action":"tree_depth","value":4})
	var read_saved_depth := func():
		var current := ConfigFile.new()
		if current.load(viewer.config_path)!=OK: return false
		var settings: Dictionary=current.get_value("viewer","settings",{})
		return settings.get("bvh_depth",-1)==4
	check(not viewer.controls.visible and await test.wait_for(read_saved_depth),"A12 native display change autosaves with F11 closed")
	var autosaved := ConfigFile.new(); autosaved.load(viewer.config_path)
	var contains_dynamics := false
	for section in autosaved.get_sections():
		for key in autosaved.get_section_keys(section):
			if key in ["qpos","qvel","ctrl","time","state","snapshot"]: contains_dynamics=true
	var saved_display: Dictionary=autosaved.get_value("viewer","settings",{})
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
	viewer.set_native_panels(true,true)
	await settle()
	write_evidence()

func project_normalized(point: Vector3) -> Vector2:
	# Public frozen frustum contract, independent of the host Camera3D crop.
	var camera: Dictionary=viewer.frame.camera
	var local: Vector3=camera.transform.affine_inverse()*point
	var projected := Vector2(local.x,local.y)
	if not camera.orthographic: projected*=float(camera.near)/-local.z
	var height: float=camera.size
	var width: float=height*maxf(viewer.scene_input.size.x,1)/maxf(viewer.scene_input.size.y,1)
	return Vector2(.5+(projected.x-camera.offset.x)/width,.5-(projected.y-camera.offset.y)/height)

func click(point: Vector2) -> void:
	# Input.parse_input_event drives viewport GUI routing rather than calling send.
	var pixel: Vector2=viewer.scene_input.position+point*viewer.scene_input.size
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
		var changed: bool=viewer.left_panel.visible!=pair[0] or viewer.right_panel.visible!=pair[1]
		viewer.set_native_panels(pair[0],pair[1])
		if changed:
			var stale: int=viewer.send({"action":"select","button":1,"x":.5,"y":.5,"aspect":test.render_aspect()})
			check(stale==0,"A09 layout transition rejects old displayed-frame pick "+label)
		var ready: bool=await settle()
		check(ready,"A09 matching presented frame ready "+label)
		if not ready:
			var diagnostic := {"name":label,"layout":viewer.layout_generation,"presented_layout":viewer.presented_layout,"frame":viewer.presented_frame_id,"render_rect":str(viewer.render_rect),"feedback":viewer.feedback,"native_active":viewer.runtime_world.native_view_active,"native_error":viewer.runtime_world.native_view_error,"stats":viewer.frame.get("stats",{})}
			if is_instance_valid(viewer.runtime_world.native_view): diagnostic["native_latest"]=viewer.runtime_world.native_view.latest.duplicate()
			print("UI_LAYOUT_STATE ",JSON.stringify(diagnostic))
			layout_samples.append(diagnostic)
			write_evidence()
			return
		var expected: Rect2=viewer.outer_rect
		if pair[0]: expected.position.x+=viewer.left_panel.size.x; expected.size.x-=viewer.left_panel.size.x
		if pair[1]: expected.size.x-=viewer.right_panel.size.x
		var rect_agrees: bool=viewer.scene_input.get_global_rect().is_equal_approx(expected)
		check(rect_agrees,"A09 input and reserved sidebars agree "+label)
		if not rect_agrees: print("UI_LAYOUT_RECT ",JSON.stringify({"name":label,"expected":str(expected),"actual":str(viewer.scene_input.get_global_rect()),"outer":str(viewer.outer_rect),"left":str(viewer.left_panel.get_global_rect()),"right":str(viewer.right_panel.get_global_rect())}))
		var normalized := project_normalized(point)
		check(Rect2(Vector2.ZERO,Vector2.ONE).has_point(normalized),"A09 test body lies inside actual central frustum "+label)
		if DisplayServer.get_name()!="headless" and not test.native:
			var source_pixel: Vector2=viewer.camera.unproject_position(point)
			var source_rect: Rect2=viewer.render_rect_in_source()
			var actual_uv: Vector2=(source_pixel-source_rect.position)/source_rect.size
			check(actual_uv.distance_to(normalized)<.003,"A09 rendered Godot projection matches published picking frustum "+label)
		if DisplayServer.get_name()!="headless":
			var cleared: Dictionary=await test.issue({"action":"select","button":1,"x":.02,"y":.98,"aspect":test.render_aspect()})
			var was_cleared: bool=cleared.get("success",false) and int(viewer.frame.selected_body)==0
			check(was_cleared,"A09 clear selection before routed mouse input "+label)
			if was_cleared:
				await click(normalized)
				check(await test.wait_for(func():return viewer.pending.is_empty() and str(viewer.frame.selected_name).ends_with("_ball")),"A09 real displayed-pixel double click selects the same body "+label)
		else:
			await test.issue({"action":"select","button":1,"x":normalized.x,"y":1-normalized.y,"aspect":test.render_aspect()})
			check(str(viewer.frame.selected_name).ends_with("_ball"),"A09 headless frozen-frame pick selects expected body "+label)
		if test.native:
			var latest: Dictionary=viewer.runtime_world.native_view.latest
			check(int(latest.get("width",0))==int(viewer.render_rect_in_source().size.x) and int(latest.get("height",0))==int(viewer.render_rect_in_source().size.y),"A09 native framebuffer matches central render size "+label)
		layout_samples.append({"name":label,"world":viewer.runtime_world.get_instance_id(),"revision":viewer.presented_revision,"frame":viewer.presented_frame_id,"normalized":str(normalized),"render_rect":str(viewer.render_rect),"source_rect":str(viewer.render_rect_in_source()),"left_rect":str(viewer.left_panel.get_global_rect()),"right_rect":str(viewer.right_panel.get_global_rect()),"selected":viewer.frame.selected_name,"camera":str(viewer.frame.camera),"layout":viewer.layout_generation,"presented_layout":viewer.presented_layout})
	viewer.set_native_panels(true,true)
	await settle()
	write_evidence()

func write_evidence() -> void:
	var out: String=OS.get_environment("GMJ_VIEWER_OUT")
	FileAccess.open(out.path_join("ui-evidence.json"),FileAccess.WRITE).store_string(JSON.stringify({"native_requested":test.native,"display":DisplayServer.get_name(),"captures":captures,"layout_samples":layout_samples},"  "))
	FileAccess.open(out.path_join("native-ui-catalog.json"),FileAccess.WRITE).store_string(JSON.stringify(viewer.get_native_ui_catalog(),"  "))
