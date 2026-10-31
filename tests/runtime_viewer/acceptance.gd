extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const Viewer = preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd")
const SceneBuilder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const UiAcceptance = preload("res://ui_acceptance.gd")
const SavedSceneProbe = preload("res://saved_scene_probe.gd")
const ContractProbe = preload("res://contract_probe.gd")
const ComponentProbe = preload("res://component_probe.gd")
const BindingProbe = preload("res://binding_probe.gd")
var checks: Array=[]
var viewer: Node
var extras: Node
var world: Node3D
var game_root: Node3D
var native := false
var ui_only := false
var analysis_only := false
var bindings_only := false
var component_only := false
var contract_only := false
var layout_diagnostic := false
var saved_scenes_only := false
var split_only := false
var mujoco_abi := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	print("PASS " if ok else "FAIL ",name)
func wait_for(test: Callable, seconds := 10.0) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<end:
		if test.call(): return true
		await process_frame
	return false
func issue(command: Dictionary, expect_success := true) -> Dictionary:
	var component: Node=extras if str(command.action) in ["step","capture_snapshot","restore_snapshot","renderer"] else viewer
	var origin: Dictionary=component.read_state().frame
	var origin_sequence: int=component._session._sequence+1 if is_instance_valid(component._session) else -1
	var arguments := command.duplicate(); arguments.erase("action")
	var request: int=component.execute(str(command.action),arguments)
	check(request>0,"queue "+str(command.action))
	if request==0: return {}
	var result := {}
	check(await wait_for(func():return not component.action_result(request).is_empty(),125. if command.action=="reload" else 10.),"complete "+str(command.action))
	result=component.action_result(request)
	check(bool(result.get("success",false))==expect_success,"result "+str(command.action)+": "+str(result.get("error","")))
	if command.action in ["step","reset_initial","capture_snapshot","restore_snapshot"] and not origin.is_empty():
		check(result.get("space",-1)==origin.space and result.get("revision",-1)==origin.revision and result.get("frame_id",-1)==origin.frame_id and result.get("sequence",-1)==origin_sequence,"deferred "+str(command.action)+" completion retains its submitted frame and sequence")
	await process_frame
	return result
func update_saved_external_design(path: String) -> PackedByteArray:
	var original_bytes := FileAccess.get_file_as_bytes(path)
	var live: Resource=world.get_node("Robot").design
	var live_snapshot: Dictionary=live.author_snapshot()
	var fresh: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(fresh!=live,"disk design edit uses a distinct uncached author Resource")
	var candidate: Dictionary=fresh.author_snapshot()
	var queue: Array=[candidate.tree];var changed := 0
	while not queue.is_empty():
		var element: Dictionary=queue.pop_back()
		if element.get("tag","")=="geom" and element.get("attrs",{}).get("name","")=="ball_geom":element.attrs.mass="3.25";changed+=1
		queue.append_array(element.get("children",[]))
	check(changed==1,"prepare a real saved external geometry mass edit")
	candidate.revision+=1
	check(fresh.restore_author(candidate).is_empty() and ResourceSaver.save(fresh,path)==OK,"write the new external author design to disk before saved-scene reload")
	check(live.author_snapshot()==live_snapshot and is_equal_approx(float(world.get_node("Robot").state().bodies.ball.mass),2.),"saving a separate resource does not mutate the cached live world design")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("external-resource-reload.json"),FileAccess.WRITE).store_string(JSON.stringify({"path":path,"saved_mass":3.25,"old_live_mass":world.get_node("Robot").state().bodies.ball.mass,"saved_bytes":FileAccess.get_file_as_bytes(path).size(),"live_resource_untouched":live.author_snapshot()==live_snapshot},"  "))
	return original_bytes

func key(code: Key, control := false, shift := false, alt := false) -> void:
	var event := InputEventKey.new(); event.keycode=code; event.physical_keycode=code; event.pressed=true; event.ctrl_pressed=control; event.shift_pressed=shift; event.alt_pressed=alt
	if int(code)>=32 and int(code)<127 and not control and not alt: event.unicode=int(code) if shift else String.chr(int(code)).to_lower().unicode_at(0)
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event)
	await process_frame
func render_aspect() -> float:
	var region: Rect2=viewer._session.render_rect_in_source()
	return maxf(region.size.x,1)/maxf(region.size.y,1)
func run() -> void:
	Engine.max_fps=120
	# Headless Window starts at 64x64 despite the project viewport size. Give
	# layout/projection checks the same representative game size as GUI runs.
	if DisplayServer.get_name()=="headless": root.size=Vector2i(1100,760)
	if DisplayServer.get_name()!="headless":
		root.grab_focus()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	native="--native" in OS.get_cmdline_user_args()
	layout_diagnostic="--layout-diagnostic" in OS.get_cmdline_user_args()
	ui_only="--ui-only" in OS.get_cmdline_user_args() or layout_diagnostic
	analysis_only="--analysis-only" in OS.get_cmdline_user_args()
	bindings_only="--bindings-only" in OS.get_cmdline_user_args()
	component_only="--component-only" in OS.get_cmdline_user_args()
	contract_only="--contract-only" in OS.get_cmdline_user_args()
	split_only="--split-only" in OS.get_cmdline_user_args()
	saved_scenes_only="--saved-scenes-only" in OS.get_cmdline_user_args()
	if saved_scenes_only:
		SavedSceneProbe.run(check)
		finish();return
	if not (component_only or contract_only or ui_only or bindings_only or analysis_only):SavedSceneProbe.run(check)
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",1 if native else 0)
	var file:=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
	var fixture_xml := '<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody><geom name="ground" type="plane" size="5 5 .1"/><body name="ball" pos="0 0 2"><freejoint name="root"/><geom name="ball_geom" type="sphere" size=".25" mass="2"/></body><body name="arm" pos="1 0 2"><joint name="hinge" range="-1 1"/><geom type="capsule" size=".1 .3" mass="1"/></body><camera name="side" pos="0 -6 3" xyaxes="1 0 0 0 .2 1"/></worldbody><actuator><position name="drive" joint="hinge" kp="10" ctrllimited="true" ctrlrange="-1 1"/></actuator><equality><weld name="hold" body1="ball" active="false"/></equality><sensor><jointpos name="joint_position" joint="hinge"/></sensor>'
	file.store_string(fixture_xml+'</mujoco>');file.close()
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file("res://fixture.xml"),"import viewer fixture")
	var package: Dictionary=await Builder.save_document(doc,"res://models","viewer")
	check(package.error.is_empty(),"save fixture resources")
	if not package.error.is_empty(): finish();return
	var resource=load(package.path)
	world=World.new(); world.name="ViewerWorld"; world.world_design=resource.fork(); world.start_paused=true
	var robot=Instance.new(); robot.name="Robot"; robot.design=resource; world.add_child(robot); robot.owner=world
	var camera:=Camera3D.new(); camera.position=Vector3(0,2,5); world.add_child(camera); camera.owner=world
	var rigid := RigidBody3D.new(); rigid.name="ExternalForceBody"; rigid.position=Vector3(-1,2,0); rigid.mass=2; world.add_child(rigid); rigid.owner=world
	var collision := CollisionShape3D.new(); collision.shape=SphereShape3D.new(); collision.shape.radius=.2; rigid.add_child(collision); collision.owner=world
	game_root=SceneBuilder.with_runtime_ui(world,"ViewerFixture")
	var packed:=PackedScene.new(); packed.pack(game_root); ResourceSaver.save(packed,"res://SavedWorld.tscn")
	game_root.free(); game_root=load("res://SavedWorld.tscn").instantiate()
	root.add_child(game_root); current_scene=game_root; world=game_root.get_node("Runtime")
	robot=world.get_node("Robot"); rigid=world.get_node("ExternalForceBody")
	check(await wait_for(func():return world.author_started and world.command_request==0,120),"compile authoritative world")
	viewer=game_root.get_node("RuntimeViewer")
	extras=game_root.get_node("GodotExtras")
	check(is_instance_valid(viewer),"explicit scene-owned viewer component")
	if not is_instance_valid(viewer): finish();return
	check(await wait_for(func():return not viewer._session.frame.is_empty() and not viewer._session.catalog.is_empty(),30),"versioned CPU scene frame and catalog")
	mujoco_abi=int(viewer._session.frame.get("scene_abi",0))
	if native: check(await wait_for(func():return world.native_view_active,30),"native renderer actually active")
	if split_only:
		await preload("res://split_probe.gd").new().run(self)
		finish(); return
	if contract_only:
		await ContractProbe.new().run(self)
		finish(); return
	if component_only:
		await ComponentProbe.new().run(self)
		finish(); return
	if bindings_only:
		var probe := BindingProbe.new()
		await probe.run(self)
		finish(); return
	if analysis_only:
		await analysis_capture()
		finish(); return
	check(not extras.ui.controls.visible,"F11 window initially closed")
	check(extras.ui.metrics.fps and extras.ui.overlay_enabled,"FPS-only initial HUD")
	var system: Dictionary=extras._performance_source.sample({"cpu":true,"ram":true,"gpu":true,"vram":true})
	await create_timer(.15).timeout
	system=extras._performance_source.sample({"cpu":true,"ram":true,"gpu":true,"vram":true})
	check(system.has("cpu") and system.cpu>=0 and system.cpu<=100,"whole-system CPU counter is sampled from procfs")
	check(system.has("ram") and system.ram_total>system.ram and system.ram>0,"system memory uses MemTotal minus MemAvailable")
	check(viewer._session.catalog.vis.size()>25 and viewer._session.catalog.rnd.size()>8 and viewer._session.catalog.visual.size()>60,"complete official display catalogs")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("catalog.json"),FileAccess.WRITE).store_string(JSON.stringify({"native_requested":native,"catalog":viewer._session.catalog,"physics":viewer._session.details.get("physics",{}),"logging":viewer._session.details.get("logging",{})},"  "))
	check(world.request_editor_design({"op":"duplicate_model"})==0,"runtime design writeback rejected")
	var system_windows := DisplayServer.get_window_list().size()
	await key(KEY_F11)
	check(extras.ui.controls.visible,"real F11 opens embedded floating window")
	check(not extras.ui.controls.force_native and not extras.ui.controls.unresizable,"embedded movable/resizable window")
	check(DisplayServer.get_window_list().size()==system_windows,"no extra system window")
	await key(KEY_F11)
	check(not extras.ui.controls.visible,"F11 closes while floating window focused")
	await key(KEY_F1); check(viewer.ui.windows.help.visible,"F1 help opens")
	await key(KEY_F1); check(not viewer.ui.windows.help.visible,"F1 help closes")
	await key(KEY_F2); check(viewer.ui.info_enabled and extras.ui.overlay_enabled,"F2 opens MuJoCo Info without hiding Godot performance")
	await key(KEY_F2); check(not viewer.ui.info_enabled and extras.ui.overlay_enabled,"F2 closes MuJoCo Info independently")
	var ui := UiAcceptance.new()
	await ui.run(self)
	await issue({"action":"save_xml","path":OS.get_environment("GMJ_VIEWER_OUT").path_join("reference-model.xml")})
	var reference_camera := await issue({"action":"copy_camera"})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("reference-camera.xml"),FileAccess.WRITE).store_string(str(reference_camera.get("text","")))
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("reference-camera.json"),FileAccess.WRITE).store_string(JSON.stringify(viewer._session.frame.camera,"  "))
	if ui_only:
		world.stop_native_view(); game_root.queue_free()
		for unused in 5: await process_frame
		finish(); return
	var old_joint_flag: bool=viewer._session.frame.settings.vis[2]
	await key(KEY_J)
	check(await wait_for(func():return viewer._session.frame.settings.vis[2]!=old_joint_flag),"official J visualization shortcut without Unicode dependency")
	var old_tree_flag: bool=viewer._session.frame.settings.vis[28]
	await key(KEY_QUOTELEFT)
	check(await wait_for(func():return viewer._session.frame.settings.vis[28]!=old_tree_flag),"native backtick Body Tree shortcut preserved")
	await key(KEY_F6); check(await wait_for(func():return viewer._session.frame.settings.frame>0),"F6 frame shortcut")
	await key(KEY_F7); check(await wait_for(func():return viewer._session.frame.settings.label>0),"F7 label shortcut")
	await issue({"action":"select","button":1,"x":.5,"y":.5,"aspect":render_aspect()})
	check(await wait_for(func():return viewer._session.frame.selected_body>0),"official CPU picking selects visible body")
	var hide_request: int=viewer._session.send({"action":"group","name":"geom","id":0,"value":false})
	var pick_request: int=viewer._session.send({"action":"select","button":1,"x":.5,"y":.5,"aspect":render_aspect()})
	check(hide_request>0 and pick_request>0,"queue visibility change and pick against the presented frame")
	check(await wait_for(func():return not viewer._session.pending.has(hide_request) and not viewer._session.pending.has(pick_request)),"presented-frame pick completes")
	check(viewer._session.frame.selected_body>0,"picking uses frozen visibility rather than a newer display setting")
	await issue({"action":"group","name":"geom","id":0,"value":true})
	var before: Dictionary=robot.state()
	await issue({"action":"perturb_begin","mode":1})
	await issue({"action":"move","mouse":4,"dx":.12,"dy":0.,"perturb":true})
	viewer.cancel_interaction()
	check(await wait_for(func():return viewer._session.pending.is_empty() and viewer._session.frame.perturb_active==0),"component gesture cancellation reaches the authoritative command boundary")
	var after: Dictionary=robot.state()
	check(after.joints.root.qpos!=before.joints.root.qpos,"paused perturb changes authoritative free joint")
	await issue({"action":"perturb_begin","mode":1})
	viewer._session.send({"action":"move","mouse":4,"dx":.03,"dy":0.,"perturb":true}); viewer._session.cancel_gesture()
	check(await wait_for(func():return viewer._session.pending.is_empty() and viewer._session.frame.perturb_active==0 and robot.state().joints.root.qpos!=after.joints.root.qpos),"normal same-tick release commits the final paused motion before ending perturbation")
	await issue({"action":"reset_initial"})
	rigid=world.get_node("ExternalForceBody")
	rigid.constant_force=Vector3(6,0,0)
	# Use the published camera; headless RenderingServer projection is dormant.
	var local: Vector3=viewer._session.frame.camera.transform.affine_inverse()*rigid.global_position
	var half_fov := tan(deg_to_rad(float(viewer._session.frame.camera.fov))*.5)
	var projected := Vector2(.5+.5*local.x/(-local.z*half_fov*render_aspect()),.5-.5*local.y/(-local.z*half_fov))
	await issue({"action":"select","button":1,"x":projected.x,"y":1-projected.y,"aspect":render_aspect()})
	check(viewer._session.frame.selected_name=="b"+str(rigid.get_rid().get_id()),"official picking selects an ordinary Godot rigid body")
	await issue({"action":"perturb_begin","mode":1})
	await issue({"action":"move","mouse":4,"dx":.12,"dy":0.,"perturb":true})
	await issue({"action":"pause"})
	await issue({"action":"perturb_begin","mode":1})
	for unused in 6: await physics_frame
	viewer._dragging=true # The begin above uses the API; simulate the routed mouse gesture.
	var release := InputEventMouseButton.new(); release.button_index=MOUSE_BUTTON_RIGHT; release.pressed=false
	viewer.global_input(release,extras.ui.controls)
	check(await wait_for(func():return viewer._session.frame.perturb_active==0),"mouse release routed from a floating viewport cancels perturbation")
	await issue({"action":"pause"})
	viewer.ui.watch_field="xfrc_applied"; viewer.ui.watch_index=int(viewer._session.frame.selected_body)*6; viewer._update_inspection()
	check(await wait_for(func():return abs(float(viewer._session.details.get("watch_value",0))-6)<1e-8),"ending perturbation preserves the existing external wrench")
	check(rigid.constant_force==Vector3(6,0,0),"business constant force remains owned by the caller")
	await issue({"action":"perturb_begin","mode":1})
	viewer.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(await wait_for(func():return viewer._session.frame.perturb_active==0),"focus loss cancels perturbation")
	await issue({"action":"perturb_begin","mode":1})
	for unused in 128: viewer._session.send({"action":"move","mouse":4,"dx":.001,"dy":0.})
	viewer._session.cancel_gesture()
	check(await wait_for(func():return viewer._session.frame.perturb_active==0 and viewer._session.pending.is_empty()),"saturated input queues cannot retain or restart perturbation")
	await issue({"action":"perturb_begin","mode":1})
	viewer._session._sequence+=1
	var expired: int=PhysicsServer3D.call("scene_viewer_request",world.space,int(viewer._session.frame.revision),-100,viewer._session._sequence,{"action":"move","mouse":4,"dx":.1,"dy":0.})
	var expired_result: Dictionary={}
	for unused in 120:
		expired_result=PhysicsServer3D.call("scene_viewer_result",expired)
		if not expired_result.is_empty(): break
		await physics_frame
	check(not expired_result.get("success",true) and str(expired_result.get("error","")).contains("Displayed frame expired"),"expired display-frame input is rejected")
	check(await wait_for(func():return viewer._session.frame.perturb_active==0),"expired display-frame input releases active perturbation")
	rigid.constant_force=Vector3.ZERO; viewer.ui.watch_field="qpos"; viewer.ui.watch_index=0
	await issue({"action":"reset_initial"})
	check(world.info().time==0,"initial reset returns time zero")
	await issue({"action":"step","count":5})
	check(abs(world.info().time-.01)<1e-8,"shared Simulation action supports exact N-step batches")
	await issue({"action":"reset_initial"})
	await issue({"action":"select","button":1,"x":.5,"y":.5,"aspect":render_aspect()})
	check(await wait_for(func():return str(viewer._session.frame.selected_name).ends_with("_ball")),"restore the imported body as perturbation target")
	await issue({"action":"pause"})
	await issue({"action":"perturb_begin","mode":1})
	await issue({"action":"move","mouse":4,"dx":.16,"dy":0.,"perturb":true})
	for unused in 6: await physics_frame
	check(absf(robot.state().joints.root.qvel[0])>.001,"running perturbation applies force to authoritative velocity")
	await key(KEY_F11)
	check(await wait_for(func():return viewer._session.frame.perturb_active==0),"opening F11 cancels active perturbation")
	check(not world.info().paused,"opening control window keeps simulation running")
	await key(KEY_F11)
	await issue({"action":"pause"})
	await issue({"action":"reset_initial"})
	await issue({"action":"control","id":0,"value":.5})
	await issue({"action":"joint","id":viewer._session.details.joints[0].id,"value":.2})
	check(abs(robot.state().joints.hinge.qpos[0]-.2)<1e-8,"joint control edits true state")
	await issue({"action":"equality","id":0,"value":true})
	await issue({"action":"equality","id":0,"value":false})
	await issue({"action":"capture_snapshot"})
	await issue({"action":"history_forward"})
	check(abs(world.info().time-.002)<1e-8,"right arrow command integrates exactly one step")
	await issue({"action":"restore_snapshot"})
	check(world.info().time==0 and abs(robot.state().controls.drive-.5)<1e-9,"snapshot restores time and control")
	await issue({"action":"history_forward"})
	await issue({"action":"history_forward"})
	var t: float=world.info().time
	await issue({"action":"history_back"})
	check(world.info().paused and world.info().time<t,"left arrow loads actual integration history")
	await issue({"action":"history_forward"})
	check(abs(world.info().time-t)<1e-8,"right arrow browses saved future before integrating")
	await issue({"action":"capture_snapshot"})
	await issue({"action":"reset_initial"})
	check(world.info().time==0 and robot.state().controls.drive==0,"capture does not redefine initial reset")
	await issue({"action":"restore_snapshot"})
	check(abs(world.info().time-t)<1e-8,"explicit snapshot survives initial reset")
	await issue({"action":"clear_control"})
	check(robot.state().controls.drive==0,"mj_resetCtrl applies to authoritative data")
	await original_controls(robot)
	await issue({"action":"speed","delta":30})
	check(await wait_for(func():return viewer._session.frame.speed_percent==.1),"official slowest speed tier")
	await issue({"action":"speed","delta":-30})
	await issue({"action":"camera","id":2})
	check(viewer._session.frame.camera.transform.is_finite(),"fixed camera conversion")
	extras.show_extras(false); viewer.show_native_panels(true,true); viewer.ui.sections.Watch.button.button_pressed=true; viewer.ui.fields.watch_edit.grab_focus()
	var joint_before_text: bool=viewer._session.frame.settings.vis[2]
	await key(KEY_J)
	check(viewer._session.frame.settings.vis[2]==joint_before_text,"focused text field does not trigger scene shortcuts")
	root.gui_release_focus()
	await key(KEY_J)
	check(await wait_for(func():return viewer._session.frame.settings.vis[2]!=joint_before_text),"leaving native Watch text restores scene shortcuts without F11")
	await issue({"action":"camera","id":0})
	await issue({"action":"visual","name":"global.orthographic","values":[1]})
	check(await wait_for(func():return viewer._session.frame.camera.orthographic),"orthographic camera shared by both backends")
	await issue({"action":"visual","name":"global.orthographic","values":[0]})
	var result:=await issue({"action":"copy_state","precise":true})
	check(str(result.get("text","")).begins_with("<key time="),"official key XML state copy")
	var folder: String=viewer.output_directory()
	await issue({"action":"print_model","path":folder+"/MJMODEL.TXT"})
	await issue({"action":"print_data","path":folder+"/MJDATA.TXT"})
	check(FileAccess.get_file_as_string(folder+"/MJMODEL.TXT").length()>50,"real model text output")
	await issue({"action":"logging","console":true,"file":false,"topics":1,"path":folder+"/MUJOCO_LOG.TXT"})
	viewer.execute("profiler"); viewer.execute("sensors"); extras.show_extras(false)
	check(world.step_simulation(10),"integrate for diagnostics")
	check(await wait_for(func():return world.command_request==0 and not viewer._session.details.get("sensors",[]).is_empty()),"real sensor values available")
	check(viewer._session.frame.stats.profiler.get("timing_available",false),"authoritative millisecond clock enabled")
	check(not extras.ui.controls.visible,"native inspection and analysis update while F11 is closed")
	var stale: int=PhysicsServer3D.call("scene_viewer_request",world.space,-123,int(viewer._session.frame.frame_id),viewer._session._sequence+1,{"action":"select"})
	var stale_result: Dictionary={}
	for unused in 120:
		stale_result=PhysicsServer3D.call("scene_viewer_result",stale)
		if not stale_result.is_empty(): break
		await physics_frame
	check(not stale_result.get("success",true) and str(stale_result.get("error","")).contains("Stale model"),"stale model commands safely rejected")
	await issue({"action":"align"})
	await issue({"action":"move","mouse":5,"dx":0.,"dy":.06,"perturb":false})
	var expected_drag: Transform3D=viewer._session.frame.camera.transform
	await issue({"action":"align"})
	var middle := InputEventMouseButton.new(); middle.button_index=MOUSE_BUTTON_MIDDLE; middle.pressed=true; viewer._scene_input(middle)
	var motion := InputEventMouseMotion.new(); motion.relative=Vector2(0,viewer.ui.render_region.size.y*.06); viewer._scene_input(motion)
	middle=middle.duplicate(); middle.pressed=false; viewer._scene_input(middle)
	check(await wait_for(func():return viewer._session.pending.is_empty() and viewer._session.frame.camera.transform.is_equal_approx(expected_drag)),"downward mouse drag matches official mjv dy and survives same-tick release")
	await issue({"action":"align"})
	await issue({"action":"move","mouse":5,"dx":0.,"dy":-.02,"perturb":false})
	var expected_wheel: Transform3D=viewer._session.frame.camera.transform
	await issue({"action":"align"})
	var wheel := InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; viewer._scene_input(wheel)
	check(await wait_for(func():return viewer._session.pending.is_empty() and viewer._session.frame.camera.transform.is_equal_approx(expected_wheel)),"wheel zoom matches the official simulate increment")
	await backend_roundtrip()
	if native:
		check(world.native_view.latest.get("authoritative_scene",false),"native bridge renders authoritative CPU scene")
		check(world.native_view.latest.get("bridge_step_calls",-1)==0,"native bridge never integrates")
		check(world.native_view.latest.get("gl_errors",-1)==0,"native GL stays valid")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("GMJ_VIEWER_OUT").path_join("native.png" if native else "godot.png"))
	if DisplayServer.get_name()!="headless": await benchmark()
	await issue({"action":"camera","id":2})
	check(await wait_for(func():return viewer._session.frame.camera.get("type",0)==2),"fixed camera ready before reload")
	var saved_external_bytes := update_saved_external_design(package.path)
	viewer.show_native_panels(false,true); viewer.show_info(true); extras.show_performance(false); extras.show_extras(false)
	var old_world_id: int=world.get_instance_id()
	var reload_result := await issue({"action":"reload"})
	check(reload_result.get("success",false) and is_instance_valid(viewer.bound_world) and viewer.bound_world.get_instance_id()!=old_world_id,"transactional reload from saved source")
	if not reload_result.get("success",false):finish();return
	world=viewer.bound_world
	check(world.info().time==0 and world.info().paused,"reload starts at saved initial state")
	check(is_equal_approx(float(world.get_node("Robot").state().bodies.ball.mass),3.25),"saved-scene reload consumes the updated external author Resource instead of its cached live copy")
	FileAccess.open(package.path,FileAccess.WRITE).store_buffer(saved_external_bytes)
	check(await wait_for(func():return viewer._session.frame.get("camera",{}).get("type",0)==2),"reload preserves a valid fixed camera by model name")
	check(not viewer.ui.left_panel.visible and viewer.ui.right_panel.visible and viewer.ui.info_enabled and not extras.ui.overlay_enabled and not extras.ui.controls.visible,"A11 reload preserves independent native and Godot UI states")
	viewer.show_native_panels(true,true); viewer.show_info(false); extras.show_performance(true)
	if native: check(await wait_for(func():return world.native_view_active,20),"native rebind after reload into SubViewport")
	var host: Control=viewer.environment_host
	host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	host.position=Vector2(80,50); host.size=root.get_visible_rect().size-Vector2(120,100)
	await process_frame; await process_frame
	check(viewer.ui.get_global_rect().is_equal_approx(host.get_global_rect()),"outer viewer surface follows a partial SubViewportContainer")
	check(host.get_global_rect().encloses(viewer.ui.render_region.get_global_rect()) and viewer.ui.render_region.size.x<host.size.x,"partial SubViewport retains a central render region between sidebars")
	check(viewer.ui.render_region.get_global_rect().has_point(extras.ui.hud.global_position),"Godot performance HUD follows the central render region")
	await ui.layout_picking("subviewport",world.get_node("Robot").state().bodies.ball.transform.origin)
	var reload_samples := []
	for unused in 3:
		world.set_paused(unused!=1)
		var was_paused: bool=world.info().paused
		var old_id: int=viewer.bound_world.get_instance_id()
		await issue({"action":"reload"})
		check(viewer.bound_world.get_instance_id()!=old_id,"repeated reload replaces the authoritative world")
		world=viewer.bound_world
		check(world.info().paused==was_paused,"environment reload preserves the live run/pause state")
		check(is_equal_approx(float(world.get_node("Robot").state().bodies.ball.mass),2.),"repeated reload refreshes the restored external author resource from disk")
		check(await wait_for(func():return not viewer._session.frame.is_empty() and (world.native_view_active if native else true),20),"repeated reload rebinds display and controls")
		reload_samples.append({"rss_kib":rss_kib(),"scene_slots":viewer._session.frame.stats.viewer_scene_slots,"history_bytes":viewer._session.frame.history_bytes})
		check(int(viewer._session.frame.stats.viewer_scene_slots)<=3 and viewer._session.frame.history_bytes<=100000000,"repeated reload retains bounded owned buffers")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("reload_resources.json"),FileAccess.WRITE).store_string(JSON.stringify(reload_samples,"  "))
	var valid_source: PackedScene=ResourceLoader.load("res://SavedWorld.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var invalid_root: Node3D=SceneBuilder.with_runtime_ui(World.new(),"InvalidSavedFixture"); var invalid_saved := PackedScene.new(); invalid_saved.pack(invalid_root); invalid_root.free(); ResourceSaver.save(invalid_saved,"res://SavedWorld.tscn")
	var kept_id: int=world.get_instance_id()
	await issue({"action":"reload"},false)
	check(viewer._pending_reload.is_empty(),"invalid saved design reload completes with feedback")
	check(viewer.bound_world.get_instance_id()==kept_id and viewer.ui.feedback.contains("Environment has no world_design"),"failed reload preserves the active world and explains the failure")
	ResourceSaver.save(valid_source,"res://SavedWorld.tscn")
	world.stop_native_view()
	if is_instance_valid(viewer.environment_host): viewer.environment_host.queue_free()
	game_root.queue_free()
	for unused in 5: await process_frame
	await inline_reload(resource)
	await keyframe_restriction(fixture_xml)
	await offaxis_projection(resource,ui)
	finish()
func analysis_capture() -> void:
	check(DisplayServer.get_name()!="headless","focused analysis evidence uses a real graphical renderer")
	check(not extras.ui.controls.visible,"F3 analysis is independent of Godot F11 extras")
	viewer.execute("profiler")
	check(await wait_for(func():return viewer.ui.windows.profiler.visible and viewer._session.pending.is_empty()),"F3 Profiler is enabled before integrating")
	# An actual weld constraint makes solver traces meaningful in this small
	# fixture; repeated batches also populate the bounded timing/size histories.
	await issue({"action":"equality","id":0,"value":true})
	for unused in 8:
		await issue({"action":"step","count":20})
		await create_timer(.23).timeout
	check(await wait_for(func():return viewer.ui.profiler_plots[2].history.size()>=5 and viewer.ui.profiler_plots[3].history.size()>=5),"live integration populates Profiler timing and dimension curves")
	var profiler: Dictionary=viewer._session.frame.stats.get("profiler",{})
	check(float(profiler.get("time",0))>0 and viewer._session.frame.stats.get("constraints",0)>0 and profiler.get("counts",[]).any(func(line):return line.size()>0),"Profiler contains actual integrated solver constraint traces")
	check(profiler.get("timing_available",false),"Profiler timing comes from the real millisecond clock")
	var ui := UiAcceptance.new(); ui.test=self; ui.viewer=viewer;ui.extras=extras
	await ui.capture("profiler")
	viewer.execute("sensors")
	check(await wait_for(func():return not viewer._session.details.get("sensors",[]).is_empty() and not viewer.ui.sensor_plot.series.is_empty()),"F4 shows actually produced sensor values alongside the Profiler")
	check(not viewer.ui.windows.profiler.get_global_rect().intersects(viewer.ui.windows.sensors.get_global_rect()),"live Profiler and Sensors retain independent figure regions")
	await ui.capture("profiler-sensors")
	var plots := []
	for plot in viewer.ui.profiler_plots:
		var points := []
		for line in plot.series: points.append(line.size())
		plots.append({"title":plot.title,"captions":plot.captions,"series_points":points,"history_samples":plot.history.size(),"rect":str(plot.get_global_rect())})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("analysis.json"),FileAccess.WRITE).store_string(JSON.stringify({"native":native,"display":DisplayServer.get_name(),"time":world.info().time,"physics":viewer._session.details.get("physics",{}),"profiler":profiler,"plots":plots,"sensors":viewer._session.details.get("sensors",[])},"  "))
	ui.write_evidence()
	world.stop_native_view(); game_root.queue_free()
	for unused in 5: await process_frame
func original_controls(robot: Node) -> void:
	check(viewer._session.catalog.get("nkey",-1)==0,"A10 current shared-world model contract has no keyframes")
	var keys: Array=viewer._session.catalog.get("keyframes",[])
	var baseline: Array=keys.filter(func(row):return str(row.name).ends_with("baseline"))
	check(baseline.is_empty(),"A10 native keyframe capability reports the existing source model restriction")
	check(not viewer.ui.fields.key.editable and viewer.ui.fields.key_load.disabled and viewer.ui.fields.key_save.disabled and str(viewer.ui.fields.key_load.tooltip_text).contains("composition"),"A10 original Key/Load/Save remain present with the actual model restriction explained")
	await issue({"action":"key_load","id":-1},false)
	await issue({"action":"key_load","id":0},false)
	await issue({"action":"key_save","id":0},false)
	await issue({"action":"threads","value":2})
	check(await wait_for(func():return viewer._session.frame.get("num_threads",0)==2),"A10 real MuJoCo worker count reported")
	await issue({"action":"reset_initial"})

	check(await wait_for(func():return viewer._session.frame.get("num_threads",0)==2),"A10 reset retains worker setting before paused updates and real integration")
	await issue({"action":"pause_update","enabled":true})
	var paused_time: float=world.info().time
	var paused_history: int=viewer._session.frame.history_count
	for unused in 4: await physics_frame
	check(world.info().time==paused_time and viewer._session.frame.history_count==paused_history,"A10 paused forward update does not integrate or append history")
	await issue({"action":"pause_update","enabled":false})
	await issue({"action":"ctrl_noise","std":.15,"rate":1.})
	await issue({"action":"step","count":8})
	var noisy: float=robot.state().controls.drive
	check(noisy>=-1 and noisy<=1 and abs(noisy)>.000001,"A10 original Control noise changes real bounded actuator input")
	await issue({"action":"ctrl_noise","std":0.,"rate":1.})
	await issue({"action":"threads","value":0})
	await issue({"action":"reset_initial"})
	await issue({"action":"history_forward"})
	await issue({"action":"history_forward"})
	await issue({"action":"history_seek","offset":-1})
	check(abs(world.info().time-.002)<1e-8 and viewer._session.frame.history_offset==-1,"A10 original History slider seeks integration states")
	await issue({"action":"history_seek","offset":0})
	check(abs(world.info().time-.004)<1e-8,"A10 History slider returns to latest recorded state")
	var terminal := {}
	var ids: Array[int]=[]
	var on_result := func(id: int, result: Dictionary):
		if id in ids: terminal[id]=result
	viewer._session.result_finished.connect(on_result)
	var history_time: float=world.info().time
	ids.append(viewer._session.send({"action":"history_forward"})); ids.append(viewer._session.send({"action":"history_forward"}))
	check(ids[0]>0 and ids[1]>0,"A14 queue two latest-position single steps in one batch")
	check(await wait_for(func():return terminal.size()==2 and not viewer._session.pending.has(ids[0]) and not viewer._session.pending.has(ids[1])),"A14 both same-batch step requests receive terminal results")
	viewer._session.result_finished.disconnect(on_result)
	var succeeded := 0
	for result in terminal.values():
		if result.get("success",false): succeeded+=1
	check(succeeded>=1 and abs(world.info().time-history_time-.002*succeeded)<1e-8,"A14 each successful queued step advances exactly once")
	# Compile another document before exporting: last-loaded process-global XML
	# must never cause File > Save xml to export the unrelated design.
	var unrelated_path := "res://unrelated.xml"
	FileAccess.open(unrelated_path,FileAccess.WRITE).store_string('<mujoco model="unrelated"><worldbody><geom name="unrelated_geom" type="sphere" size=".1"/></worldbody></mujoco>')
	var unrelated: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(unrelated.import_file(unrelated_path),"A10 compile unrelated design before original File export")
	var folder: String=viewer.output_directory()
	var xml_path := folder+"/runtime.xml"
	var mjb_path := folder+"/runtime.mjb"
	await issue({"action":"save_xml","path":xml_path})
	await issue({"action":"save_mjb","path":mjb_path})
	var xml := FileAccess.get_file_as_string(xml_path)
	check(xml.contains("ball_geom") and not xml.contains("unrelated_geom"),"A10 XML export belongs to active world after unrelated document compilation")
	var imported: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(imported.import_file(xml_path),"A10 exported XML compiles through the actual MuJoCo importer: "+str(imported.get_error()))
	var binary := FileAccess.get_file_as_bytes(mjb_path)
	check(binary.size()>500 and binary!=xml.to_utf8_buffer(),"A10 MJB export contains a complete binary model")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("exports.json"),FileAccess.WRITE).store_string(JSON.stringify({"xml":ProjectSettings.globalize_path(xml_path),"mjb":ProjectSettings.globalize_path(mjb_path),"binary_bytes":binary.size()},"  "))
	await issue({"action":"save_xml","path":"user://missing/parent/model.xml"},false)
	await issue({"action":"reset_initial"})

func backend_roundtrip() -> void:
	var before: Dictionary=viewer._session.frame.camera.duplicate(true)
	var simulation_time: float=world.info().time
	var available := ClassDB.class_exists("MjSharedNativeViewBridge") and OS.get_name()=="Linux" and DisplayServer.get_name()=="X11" and RenderingServer.get_current_rendering_method()=="gl_compatibility"
	var destination := not native
	extras.execute("renderer",{"native":destination})
	if destination and not available:
		check(await wait_for(func():return not world.native_view_error.is_empty() and not world.native_view_active),"A11 unavailable native backend provides an explicit Godot fallback")
	else:
		check(await wait_for(func():return world.native_view_active==destination and viewer._session.presented_frame_id>0 and viewer._session.presented_layout==viewer._session.layout_generation,30),"A08 backend switch presents a valid frame from the requested renderer")
	check(await wait_for(func():return not viewer._session.frame.is_empty() and viewer._session.frame.camera.transform.is_equal_approx(before.transform)),"A08 backend switch preserves the moved camera instead of reseeding")
	extras.execute("renderer",{"native":native})
	check(await wait_for(func():return world.native_view_active==native and viewer._session.presented_frame_id>0 and viewer._session.presented_layout==viewer._session.layout_generation,30),"A08 return to original rendering backend completes")
	check(viewer._session.frame.camera.transform.is_equal_approx(before.transform) and viewer._session.frame.camera.offset.is_equal_approx(before.offset),"A08 backend round trip preserves the current optical view")
	check(world.info().paused and world.info().time==simulation_time,"A08 backend round trip does not advance the simulation")

func keyframe_restriction(base_xml: String) -> void:
	var xml := base_xml+'<keyframe><key name="baseline" time=".4" qpos="0 0 2 1 0 0 0 .35" qvel="0 0 0 0 0 0 0" ctrl=".25"/></keyframe></mujoco>'
	FileAccess.open("res://keyed-source.xml",FileAccess.WRITE).store_string(xml)
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file("res://keyed-source.xml"),"A10 source editor preserves valid authored keyframes")
	var saved: Dictionary=await Builder.save_document(doc,"res://keyed-models","restricted")
	check(saved.error.is_empty(),"A10 keyframed source remains saveable in editor resources")
	if not saved.error.is_empty(): return
	var design: Resource=load(saved.path)
	world=World.new(); world.name="KeyframeRestriction"; world.world_design=design.fork(); world.start_paused=true
	var robot := Instance.new(); robot.name="Robot"; robot.design=design; world.add_child(robot)
	root.add_child(world)
	check(await wait_for(func():return world.info().get("compile_status","")=="failed",60),"A10 shared-world composition retains its explicit keyframe source restriction")
	check(str(world.info().get("last_error","")).contains("keyframes"),"A10 rejected keyframe source has explicit feedback")
	check(str(design.xml()).contains("keyframe"),"A10 rejected keyframes remain in the saved author source")
	world.queue_free()
	for unused in 5: await process_frame

func offaxis_projection(resource: Resource, ui: RefCounted) -> void:
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",1 if native else 0)
	var legacy := ConfigFile.new()
	legacy.set_value("ui","overlay",false); legacy.set_value("metrics","simulation",true); legacy.set_value("metrics","fps",true)
	var preference_path := "user://mujoco_viewer_%s.cfg" % ProjectSettings.globalize_path("res://").sha256_text().substr(0,12)
	legacy.save(preference_path)
	world=World.new(); world.name="OffAxisWorld"; world.world_design=resource.fork(); world.start_paused=true
	var robot := Instance.new(); robot.name="Robot"; robot.design=resource; world.add_child(robot)
	var camera := Camera3D.new(); camera.position=Vector3(0,2,5); camera.set_frustum(.12,Vector2(.009,.006),.06,100.); world.add_child(camera)
	game_root=SceneBuilder.with_runtime_ui(world,"OffAxisFixture")
	root.add_child(game_root);current_scene=game_root
	check(await wait_for(func():return world.author_started and world.command_request==0,120),"A09 off-axis world compiles")
	viewer=game_root.get_node("RuntimeViewer")
	extras=game_root.get_node("GodotExtras")
	check(await wait_for(func():return not viewer._session.frame.is_empty() and viewer._session.frame.camera.get("offset",Vector2.ZERO).length_squared()>0 and (world.native_view_active if native else true),30),"A09 authored asymmetric frustum reaches actual backend")
	ui.viewer=viewer;ui.extras=extras
	check(extras.ui.overlay_enabled and not viewer.ui.info_enabled,"old project preferences are ignored by the independent component")
	extras.show_performance(false); extras.save_view_preferences(true)
	var untouched := ConfigFile.new(); untouched.load(preference_path)
	var component_preferences := ConfigFile.new();component_preferences.load(extras._config_path)
	check(untouched.has_section_key("metrics","simulation") and untouched.has_section_key("ui","overlay") and not untouched.has_section("view"),"breaking migration never rewrites old project preferences")
	check(extras._config_path!=preference_path and not component_preferences.get_value("view","performance",true),"component writes independent personal preferences")
	await ui.layout_picking("offaxis",robot.state().bodies.ball.transform.origin)
	var before_invalid: Dictionary=viewer._session.frame.camera.duplicate(true)
	await issue({"action":"visual","name":"global.fovy","values":[0.]},false)
	await issue({"action":"visual","name":"not_a_visual_field","values":[1.]},false)
	await issue({"action":"camera","id":-9},false)
	check(viewer._session.frame.camera.transform.is_equal_approx(before_invalid.transform) and viewer._session.frame.camera.offset.is_equal_approx(before_invalid.offset) and is_equal_approx(viewer._session.frame.camera.size,before_invalid.size),"A09 rejected camera/display changes preserve authored off-axis optics")
	# No camera motion has cleared the one-shot authored frustum yet. Centering
	# must immediately replace that camera, not wait for a later drag to do so.
	var authored_camera: Transform3D=viewer._session.frame.camera.transform
	var arm_uv: Vector2=ui.project_normalized(robot.state().bodies.arm.transform.origin)
	await issue({"action":"select","button":2,"x":arm_uv.x,"y":1-arm_uv.y,"aspect":render_aspect()})
	check(await wait_for(func():return not viewer._session.frame.camera.transform.is_equal_approx(authored_camera)),"A09 right double-click centering replaces the authored camera immediately")
	var ball_uv: Vector2=ui.project_normalized(robot.state().bodies.ball.transform.origin)
	await issue({"action":"select","button":2,"x":ball_uv.x,"y":1-ball_uv.y,"aspect":render_aspect(),"control":true})
	check(await wait_for(func():return viewer._session.frame.camera.get("type",0)==1 and str(viewer._session.frame.camera.get("target","")).ends_with("_ball")),"A09 Ctrl+right double-click starts tracking from an authored view")
	await issue({"action":"visual","name":"global.orthographic","values":[1]})
	check(await wait_for(func():return viewer._session.frame.camera.orthographic),"A09 orthographic frame published before layout check")
	await ui.layout_picking("orthographic",robot.state().bodies.ball.transform.origin)
	await issue({"action":"visual","name":"global.orthographic","values":[0]})
	await issue({"action":"camera","id":2})
	await ui.layout_picking("fixed",robot.state().bodies.ball.transform.origin)
	ball_uv=ui.project_normalized(robot.state().bodies.ball.transform.origin)
	await issue({"action":"select","button":2,"x":ball_uv.x,"y":1-ball_uv.y,"aspect":render_aspect(),"control":true})
	await ui.layout_picking("tracking",robot.state().bodies.ball.transform.origin)
	world.stop_native_view(); game_root.queue_free()
	for unused in 5: await process_frame
func inline_reload(resource: Resource) -> void:
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",0)
	var game := Node3D.new(); game.name="Game"
	var environment := World.new(); environment.name="Environment"; environment.world_design=resource.fork(); environment.start_paused=true
	var robot := Instance.new(); robot.name="Robot"; robot.design=resource; environment.add_child(robot)
	game.add_child(environment); environment.owner=game; robot.owner=game
	var camera := Camera3D.new(); camera.name="ExternalCamera"; camera.position=Vector3(0,2,5); game.add_child(camera); camera.owner=game
	SceneBuilder.attach_viewer(game,environment)
	SceneBuilder.attach_extras(game,environment)
	var saved := PackedScene.new(); saved.pack(game); ResourceSaver.save(saved,"res://InlineWorld.tscn"); game.free()
	game=load("res://InlineWorld.tscn").instantiate();game_root=game; root.add_child(game); current_scene=game
	world=game.get_node("Environment")
	check(await wait_for(func():return world.author_started and world.command_request==0,120),"inline saved world starts")
	viewer=game_root.get_node("RuntimeViewer")
	extras=game_root.get_node("GodotExtras")
	check(viewer._session._reload_source_path=="res://InlineWorld.tscn" and str(viewer._session._reload_world_path)=="Environment","reload resolves inline world to saved game source")
	var original_id := world.get_instance_id()
	world.set_paused(false)
	await issue({"action":"reload"})
	check(viewer.bound_world.get_instance_id()!=original_id,"inline world reload commits transactionally")
	check(is_instance_valid(game) and game.is_inside_tree(),"inline reload preserves game/controller lifetime")
	check(not viewer.bound_world.info().paused,"direct saved-source reload retains running state even when the saved source starts paused")
	check(viewer.bound_world.has_node("ExternalCamera"),"inline reload includes saved external camera context")
	check(viewer.bound_world.get_meta("mj_saved_scene")=="res://InlineWorld.tscn" and viewer.bound_world.get_meta("mj_saved_world_path")=="Environment","reload preserves editor-to-runtime source identity")
	game.queue_free()
	for unused in 5: await process_frame
	check(not root.disable_3d,"scene teardown restores root 3D rendering")
func rss_kib() -> int:
	for line in extras._performance_source.read_text("/proc/self/status").split("\n"):
		if line.begins_with("VmRSS:"): return int(line.trim_prefix("VmRSS:").strip_edges().get_slice(" ",0))
	return -1
func benchmark() -> void:
	var results := []
	var baseline: Dictionary=extras.ui.metrics.duplicate()
	var original_cap := Engine.max_fps
	Engine.max_fps=120
	var was_paused: bool=world.info().paused
	world.set_paused(false)
	for mode in ["off","fps","all","analysis"]:
		extras.ui.overlay_enabled=mode!="off"
		for metric in extras.ui.metrics: extras.ui.metrics[metric]=mode in ["all","analysis"] or metric=="fps"
		extras.ui.controls.visible=mode=="analysis"; viewer.ui.windows.profiler.visible=mode=="analysis"; viewer.ui.windows.sensors.visible=mode=="analysis"
		for unused in 30: await process_frame
		var durations: Array[float]=[]
		var previous := Time.get_ticks_usec()
		for unused in 180:
			await process_frame
			var now := Time.get_ticks_usec(); durations.append((now-previous)/1000.); previous=now
		durations.sort()
		results.append({"mode":mode,"frame_ms_p50":durations[durations.size()/2],"frame_ms_p95":durations[int(durations.size()*.95)],"scene_slots":viewer._session.frame.stats.get("viewer_scene_slots",0),"history_bytes":viewer._session.frame.history_bytes,"system_metrics":extras.ui.system_metrics.duplicate(),"process_rss_kib":rss_kib()})
		check(int(viewer._session.frame.stats.get("viewer_scene_slots",0))<=3 and viewer._session.frame.history_bytes<=100000000,"bounded buffers in "+mode)
	extras.ui.metrics=baseline
	Engine.max_fps=original_cap
	world.set_paused(was_paused)
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"native":native,"vsync":false,"fps_cap":120,"samples":results},"  "))

func finish() -> void:
	var failed:=checks.filter(func(row):return not row.passed).size()
	var report:={"checks":checks,"passed":checks.size()-failed,"failed":failed,"native":native,"scope":"split-only" if split_only else "saved-scenes-only" if saved_scenes_only else "layout-diagnostic" if layout_diagnostic else "contract-only" if contract_only else "component-only" if component_only else "bindings-only" if bindings_only else "analysis-only" if analysis_only else "ui-only" if ui_only else "full","display":DisplayServer.get_name(),"godot":Engine.get_version_info().get("string",""),"mujoco_abi":mujoco_abi,"native_gl_build":ClassDB.class_exists("MjSharedNativeViewBridge"),"keyframes":"not-tested" if split_only or saved_scenes_only or component_only or contract_only or ui_only or analysis_only or bindings_only else "existing-model-restriction"}
	var path:=OS.get_environment("GMJ_VIEWER_OUT").path_join("report-native.json" if native else "report-godot.json")
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("VIEWER_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed,"native":native,"scope":"split-only" if split_only else "saved-scenes-only" if saved_scenes_only else "layout-diagnostic" if layout_diagnostic else "contract-only" if contract_only else "component-only" if component_only else "bindings-only" if bindings_only else "analysis-only" if analysis_only else "ui-only" if ui_only else "full"}))
	quit(0 if failed==0 else 1)
