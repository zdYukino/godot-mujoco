extends RefCounted
## Actual component lifecycle and no-UI rendering. No replacement physics/model data.
const Viewer = preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd")
const SystemMetrics = preload("res://addons/godot_mujoco/viewer/performance.gd")
const UiScene = preload("res://addons/godot_mujoco/viewer/viewer_ui.gd")
const UiAcceptance = preload("res://ui_acceptance.gd")
const GameCamera = preload("res://game_camera.gd")
var test
var viewer: Node
var extras: Node
var world: Node3D
var evidence := []
var performance := []
var created_hosts: Array[Node] = []
func check(ok: bool, message: String) -> void: test.check(ok,message)
func active() -> bool:
	return is_instance_valid(viewer._session) and viewer.read_state().get("presentation",{}).get("ready",false)
func draw_hash(label: String) -> int:
	if DisplayServer.get_name()=="headless": return 0
	await RenderingServer.frame_post_draw
	var image: Image=test.root.get_texture().get_image()
	var folder := OS.get_environment("GMJ_VIEWER_OUT").path_join("component-frames")
	DirAccess.make_dir_recursive_absolute(folder)
	check(not image.is_empty() and image.save_png(folder.path_join(label+".png"))==OK,"actual no-UI rendered picture captured "+label)
	return hash(image.get_data())
func profile(mode: String) -> void:
	var durations: Array[float]=[]
	for unused in 90:
		var before := Time.get_ticks_usec()
		await test.process_frame
		durations.append((Time.get_ticks_usec()-before)/1000.)
	durations.sort()
	var rss := -1
	for line in SystemMetrics.read_text("/proc/self/status").split("\n"):
		if line.begins_with("VmRSS:"):rss=int(line.trim_prefix("VmRSS:").strip_edges().get_slice(" ",0))
	var session: Node=world._view_session
	var state: Dictionary=session.frame
	var original_active: bool=is_instance_valid(session.consumer)
	var extras_active: bool=is_instance_valid(session.extras_client)
	var current_frame: bool=original_active or world.native_view_active
	var graphical := DisplayServer.get_name()!="headless"
	var fps_observed: bool=graphical and (current_frame or extras_active)
	performance.append({"mode":mode,"sample_count":90,"original_active":original_active,"extras_active":extras_active,"frame_context":"CPU snapshot only; headless has no displayed frames" if not graphical else "active presentation snapshot" if current_frame else "last cached snapshot, not a currently displayed frozen frame or live allocation count","renderer_fps_observed":fps_observed,"renderer_fps_context":"headless has no graphical backend frame observation" if not graphical else "actual backend updates" if fps_observed else "no Godot backend counter consumer; do not interpret as actual display rate","frame_ms_p50":durations[45],"frame_ms_p95":durations[85],"rss_kib":rss,"frame_slots":state.get("stats",{}).get("viewer_scene_slots",0),"history_bytes":state.get("history_bytes",0),"fps_cap":Engine.max_fps,"physics_paused":world.info().paused,"simulation_time":world.info().time,"measurement":"capped host frame interval milliseconds","renderer_fps":world._view_session.renderer_fps,"host_fps":world._view_session.host_fps,"metrics":extras.ui.metrics.duplicate() if is_instance_valid(extras) and is_instance_valid(extras.ui) else {},"system_samples":extras.ui.system_metrics.duplicate() if is_instance_valid(extras) and is_instance_valid(extras.ui) else {}})
	if DisplayServer.get_name()!="headless" and mode in ["default-fps","all-metrics","full-analysis","original-only","extras-only"]:check(world._view_session.renderer_fps>0,"mandatory FPS follows actual presented backend frames in "+mode)
	check(int(state.get("stats",{}).get("viewer_scene_slots",0))<=3 and int(state.get("history_bytes",0))<=100000000,("bounded actual presentation/history resources in " if current_frame else "bounded last observed presentation/history snapshot in ")+mode)
func profiler_stop_checks() -> void:
	var observations := []
	for off_before_disable in [false,true]:
		var suffix := " after same-frame F3 off" if off_before_disable else ""
		viewer.execute("profiler",{"value":true})
		check(await test.wait_for(func():return active() and viewer._session.frame_options().get("profiler",false)),"F3 has a real analysis consumer before teardown"+suffix)
		await test.issue({"action":"equality","id":0,"value":true})
		await test.issue({"action":"history_forward"})
		check(await test.wait_for(func():return viewer.read_state().frame.get("stats",{}).get("profiler",{}).get("counts",[]).size()>0),"active F3 captures real constrained solver series"+suffix)
		var before: float=world.info().time
		if off_before_disable:viewer.execute("profiler",{"value":false})
		viewer.enabled=false
		check(world.step_simulation(2),"ordinary physics steps without the last Profiler consumer"+suffix)
		check(await test.wait_for(func():return world.command_request==0 and world.info().time>before),"real constrained integration completes without the component consumer"+suffix)
		# Read AFTER the real step: getter options affect future collection; the
		# returned batch stats reveal whether teardown stopped the earlier step.
		var packet: Dictionary=PhysicsServer3D.call("scene_viewer_frame",world.space,-1,{"backend":"native" if test.native else "godot","profiler":false,"inspect":false})
		for unused in 12:
			if packet.has("stats"):break
			await test.process_frame
			packet=PhysicsServer3D.call("scene_viewer_frame",world.space,-1,{"backend":"native" if test.native else "godot","profiler":false,"inspect":false})
		var stopped: Dictionary=packet.get("stats",{}).get("profiler",{})
		observations.append({"off_before_disable_same_frame":off_before_disable,"before_time":before,"actual_after_time":world.info().time,"profiler_after_disabled_step":stopped,"backend_native":world.native_view_active})
		check(float(stopped.get("time",0))>before and stopped.get("counts",[1]).is_empty() and stopped.get("costs",[1]).is_empty(),"disabled F3 stops optional C++ series in the following actual integration batch"+suffix)
		viewer.enabled=true
		check(await test.wait_for(active,30),"viewer rebinds after releasing the actual Profiler consumer"+suffix)
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("profiler-consumer-stop.json"),FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))

func committed_reload_disable_checks() -> void:
	var observations := []
	for direct in [true,false]:
		var previous_space: RID=world.space
		var origin_session: Node=viewer._session
		var request: int=viewer.execute("reload")
		var host: Node=origin_session._reload_host if direct else viewer.environment_host
		check(request>0 and is_instance_valid(host),"public reload creates a real candidate before commit-disable "+str(direct))
		if request==0 or not is_instance_valid(host):return
		if direct:created_hosts.append(host)
		var committed := {"seen":false}
		host.world_committed.connect(func(_target: Node3D):committed.seen=true;viewer.enabled=false,CONNECT_ONE_SHOT)
		check(await test.wait_for(func():return not viewer.action_result(request).is_empty(),125),"commit-disable reload reaches a terminal public result "+str(direct))
		var result: Dictionary=viewer.action_result(request)
		check(committed.seen and result.get("success",false) and not result.get("cancelled",false) and host.world.space!=previous_space,"disabling from world_committed preserves truthful successful reload completion "+str(direct))
		viewer.enabled=true
		check(await test.wait_for(active,30) and viewer.bound_world==host.world and viewer.environment_host==host,"re-enable follows the actually committed authority and Host "+str(direct))
		world=viewer.bound_world;test.world=world
		observations.append({"direct_world_request":direct,"previous_space":previous_space.get_id(),"committed_space":world.space.get_id(),"result":result,"same_component":viewer.get_instance_id()})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("committed-reload-lifecycle.json"),FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))

func invalid_configuration_checks() -> void:
	var unbound := Viewer.new();unbound.name="MissingTargetViewer";test.game_root.add_child(unbound)
	for unused in 3:await test.process_frame
	check(unbound.status=="UNBOUND" and not unbound.last_error.is_empty() and unbound.execute("step",{"count":1})==0 and not is_instance_valid(unbound.ui),"missing explicit target remains unavailable without guessing a World")
	unbound.queue_free()
	var wrong_target := Node3D.new();wrong_target.name="WrongTarget";test.game_root.add_child(wrong_target)
	var wrong := Viewer.new();wrong.name="WrongTargetViewer";wrong.world=wrong_target;test.game_root.add_child(wrong)
	for unused in 4:await test.process_frame
	check(wrong.status=="CONFIGURATION_ERROR" and wrong.last_error=="Target is not an MjRuntimeWorld." and viewer.bound_world==world and active(),"wrong explicit target reports a reason without hijacking the active component")
	wrong.queue_free();wrong_target.queue_free()
	viewer.enabled=false
	for unused in 4:await test.process_frame
	for outside in [false,true]:
		var design := UiScene.new();design.use_default_presenters=false;design.automatic_overlay_layout=false
		if outside:
			var region := Control.new();region.name="OutOfBoundsRegion";region.position=Vector2(-20,40);region.size=Vector2(100,100);design.add_child(region);region.owner=design;design.render_region=region
		var saved := PackedScene.new();saved.pack(design);design.free()
		var bad := Viewer.new();bad.name="InvalidRegionViewer";bad.world=world;bad.ui_scene=saved;test.game_root.add_child(bad)
		check(await test.wait_for(func():return bad.status=="CONFIGURATION_ERROR"),"invalid custom UI reaches an explicit configuration error "+str(outside))
		var expected := "UI render_region must be a positive rectangle inside the target viewport." if outside else "UI scene must declare a valid render_region Control."
		check(bad.last_error==expected and bad.execute("step",{"count":1})==0 and not is_instance_valid(bad._session),"out-of-bounds custom region is rejected without silent default UI" if outside else "missing custom render region is rejected without silent default UI")
		if test.native:check(world.native_view_active,"invalid custom UI retains the actual selected native renderer "+str(outside))
		bad.queue_free()
		for unused in 4:await test.process_frame
	var minimal_design := UiScene.new();minimal_design.use_default_presenters=false;minimal_design.automatic_overlay_layout=false
	var minimal_region := Control.new();minimal_region.name="ViewportInput";minimal_design.add_child(minimal_region);minimal_region.owner=minimal_design;minimal_region.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);minimal_design.render_region=minimal_region
	var authored_theme := Theme.new();authored_theme.set_color("font_color","Label",Color(.2,.8,1.));minimal_design.theme=authored_theme
	var authored_label := Label.new();authored_label.name="AuthoredLabel";authored_label.text="Minimal authored UI";authored_label.position=Vector2(10,10);authored_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;minimal_design.add_child(authored_label);authored_label.owner=minimal_design
	var minimal_scene := PackedScene.new();minimal_scene.pack(minimal_design);minimal_design.free()
	var minimal := Viewer.new();minimal.name="MinimalAuthoredViewer";minimal.world=world;minimal.ui_scene=minimal_scene;test.game_root.add_child(minimal)
	check(await test.wait_for(func():return minimal.status=="ACTIVE" and minimal.read_state().get("presentation",{}).get("ready",false),30),"valid minimal custom UI binds without rebuilding the default panels")
	check(not is_instance_valid(minimal.ui.get_node_or_null("GodotExtras")) and minimal.ui.sections.is_empty() and minimal.ui.get_node("AuthoredLabel").text=="Minimal authored UI","custom UI retains its authored contents with optional panel modules absent")
	check(minimal.execute("image_sensor",{"id":0})==0 and not minimal.last_error.is_empty() and not minimal._session.inspection_options.get("sensors",false),"missing optional Sensors module rejects image selection without producing sensor data")
	check(minimal.ui_theme==null and minimal.ui.theme==authored_theme and minimal.execute("ui_color",{"value":2})==0,"Theme authored inside the UI scene is protected without a component ui_theme override")
	var minimal_time: float=world.info().time
	var minimal_step: int=minimal.execute("history_forward")
	check(minimal_step>0 and await test.wait_for(func():return not minimal.action_result(minimal_step).is_empty()) and minimal.action_result(minimal_step).get("success",false) and absf(world.info().time-minimal_time-.002)<1e-8,"minimal UI keeps allowed authoritative simulation actions available without default panel modules")
	minimal.save_view_preferences(true)
	var personal := ConfigFile.new();personal.load(minimal._config_path);personal.set_value("style","ui_color",2);personal.set_value("style","ui_font",3);personal.save(minimal._config_path)
	minimal.enabled=false
	for unused in 3:await test.process_frame
	minimal.enabled=true
	check(await test.wait_for(func():return minimal.status=="ACTIVE",30),"minimal authored component re-enables with saved personal settings")
	check(minimal.ui.theme==authored_theme and minimal.ui.get_node("AuthoredLabel").get_theme_color("font_color")==Color(.2,.8,1.),"personal palette settings cannot replace a Theme saved in the custom UI scene")
	minimal.queue_free()
	for unused in 4:await test.process_frame
	viewer.enabled=true
	check(await test.wait_for(active,30),"valid explicit component rebinds after invalid UI without replacing the world")

func run(tree) -> void:
	test=tree; viewer=test.viewer; extras=test.extras; world=test.world
	await profile("default-fps")
	extras.show_performance(false)
	var no_overlay_sample: int=extras._performance_source.last_sample
	await profile("overlay-off")
	check(extras._performance_source.last_sample==no_overlay_sample,"hidden performance overlay has no optional system sampler consumer")
	extras.show_performance(true)
	var availability := {}
	for name in extras.ui.metrics:
		var reason: String=extras._performance_source.availability(name)
		availability[name]=reason
		if reason.is_empty():extras.execute("metric",{"name":name,"value":true})
		else:check(extras.ui.metric_checks[name].disabled and not extras.ui.metric_checks[name].tooltip_text.is_empty(),"unavailable system metric stays disabled with its real driver reason: "+name)
	# CPU utilization needs two real 1 Hz samples before the recorded interval.
	await test.create_timer(2.2).timeout
	if availability.get("cpu","").is_empty():check(await test.wait_for(func():return extras.ui.system_metrics.has("cpu") and extras.ui.system_metrics.cpu>=0 and extras.ui.system_metrics.cpu<=100,4),"real whole-system CPU sample is bounded percent after two 1 Hz reads")
	check(extras.ui.system_metrics.get("ram",0)>0 and extras.ui.system_metrics.get("ram_total",0)>=extras.ui.system_metrics.get("ram",0),"real system memory sample uses total minus available bytes")
	await profile("all-metrics")
	viewer.show_info(true);viewer.execute("profiler",{"value":true});viewer.execute("sensors",{"value":true})
	await profile("full-analysis")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("metric-availability.json"),FileAccess.WRITE).store_string(JSON.stringify(availability,"  "))
	viewer.show_info(false);viewer.execute("profiler",{"value":false});viewer.execute("sensors",{"value":false})
	for name in extras.ui.metrics:extras.execute("metric",{"name":name,"value":name=="fps"})
	# Compare independently optional roles using the same paused world, camera,
	# FPS cap and 90-host-frame sampling interval as the existing modes.
	extras.enabled=false
	for unused in 6:await test.process_frame
	check(active() and extras._performance_source==null,"original-only benchmark stops Extras system sampling while retaining presentation")
	await profile("original-only")
	extras.enabled=true
	check(await test.wait_for(func():return extras.status=="ACTIVE",30),"Extras re-enables independently before Extras-only benchmark")
	viewer.enabled=false
	for unused in 6:await test.process_frame
	check(not is_instance_valid(world._view_session.consumer) and extras.status=="ACTIVE" and not world._view_session.frame_options().get("profiler",true),"Extras-only benchmark stops original interaction and optional analysis")
	# Cross the FPS counter interval after releasing original ownership; the
	# graphical assertion must observe new direct/native updates, not old FPS.
	await test.create_timer(.6).timeout
	await profile("extras-only")
	if not test.native:check(not is_instance_valid(world._view_session._godot_viewport) and not world.get_viewport().disable_3d,"Extras-only benchmark keeps direct Godot rendering without helper presentation")
	viewer.enabled=true
	check(await test.wait_for(active,30),"original presentation independently returns after Extras-only benchmark")
	var component_id: int=viewer.get_instance_id()
	var robot: Node=world.get_node("Robot")
	var initial: Dictionary=robot.state().duplicate(true)
	var time: float=world.info().time
	var original: Camera3D=world.get_viewport().get_camera_3d()
	check(is_instance_valid(original),"active authored camera exists before viewer detaches")
	var submission: Dictionary=viewer.read_state().frame
	var queued_control: int=viewer.execute("control",{"id":0,"value":.7})
	var queued_step: int=viewer.execute("history_forward")
	check(queued_control>0 and queued_step>0,"real control and step commands queue in the same frame before disable")
	viewer.enabled=false
	extras.enabled=false
	for unused in 6: await test.process_frame
	var control_result: Dictionary=viewer.action_result(queued_control)
	var step_result: Dictionary=viewer.action_result(queued_step)
	check(not control_result.get("success",true) and control_result.get("cancelled",false) and not step_result.get("success",true) and step_result.get("cancelled",false),"same-frame component disable cancels queued authoritative control and step commands")
	check(control_result.get("space",-1)==submission.space and control_result.get("revision",-1)==submission.revision and control_result.get("frame_id",-1)==submission.frame_id,"cancelled component completion retains its submission space revision and frozen frame")
	check(not viewer.enabled and (not is_instance_valid(viewer.ui) or not viewer.ui.visible),"disabled explicit component has no visible runtime UI")
	await profile("disabled")
	check(extras._performance_source==null and not world._view_session.frame_options().get("inspect",false),"disabled component stops optional telemetry and inspection consumers")
	check(world.info().time==time and robot.state()==initial,"disabling the component does not reset paused simulation")
	var game_camera: Camera3D=GameCamera.new(); game_camera.name="GameplayCamera"; game_camera.position=Vector3(0,2,5); world.add_child(game_camera);game_camera.make_current()
	check(await test.wait_for(func():return game_camera.ticks>3),"real gameplay camera process continues with viewer disabled")
	if test.native:
		check(await test.wait_for(func():return world.native_view_active and world.native_view.latest.get("frame",0)>3,30),"native presentation remains active with disabled component")
		check(world.native_view.latest.get("gl_errors",-1)==0,"disabled-component native drawing has no GL errors")
	else: check(not world.native_view_active and not world.get_viewport().disable_3d,"disabled component preserves the Godot renderer")
	check(world.get_viewport().get_camera_3d()==game_camera and game_camera.is_current(),"rendering preserves the gameplay camera's current ownership")
	var start_ticks: int=game_camera.ticks
	var first_hash: int=await draw_hash("disabled-1")
	var before_transform: Transform3D=game_camera.global_transform
	for unused in 50: await test.process_frame
	var second_hash: int=await draw_hash("disabled-2")
	check(game_camera.ticks>start_ticks and not game_camera.global_transform.is_equal_approx(before_transform),"actual gameplay camera animation advances while physics stays paused")
	if DisplayServer.get_name()!="headless": check(first_hash!=second_hash,"actual rendered pixels follow the continuously animated external camera")
	game_camera.set_process(false)
	if test.native:
		check(await test.wait_for(func():return world._view_session.frame.get("camera",{}).get("transform",Transform3D.IDENTITY).is_equal_approx(game_camera.global_transform)),"native frozen frame follows the latest external camera pose")
	var keys: int=game_camera.keypresses
	await test.key(KEY_F1)
	check(game_camera.keypresses>keys,"disabled component leaves MuJoCo keys available to gameplay input")
	var request: int=viewer.execute("step",{"count":1})
	check(request==0 and not viewer.last_error.is_empty(),"disabled component command API rejects explicitly without stepping")
	check(world.info().time==time and robot.state()==initial,"camera/input changes do not alter actual paused physics")
	# A second real camera exercises current-camera switch and changing optics.
	var second: Camera3D=GameCamera.new();second.name="SecondGameplayCamera";second.position=Vector3(1,2,5);second.projection=Camera3D.PROJECTION_ORTHOGONAL;second.size=5.;second.near=.08;second.far=80.;world.add_child(second);second.make_current()
	check(await test.wait_for(func():return second.ticks>3),"switching to another real current gameplay camera preserves processing")
	second.set_process(false)
	if test.native:
		check(await test.wait_for(func():return world._view_session.frame.get("camera",{}).get("orthographic",false) and is_equal_approx(float(world._view_session.frame.camera.size),second.size)),"native presentation follows external camera switch to orthographic projection")
	check(world.get_viewport().get_camera_3d()==second,"native and Godot leave the second gameplay camera current")
	# Remove the component itself: presentation belongs to World, not the UI node.
	viewer.queue_free()
	for unused in 5: await test.process_frame
	check(not is_instance_valid(viewer),"explicit viewer node can be removed independently")
	check(is_instance_valid(world._view_session),"world presentation session survives component removal")
	await profile("absent")
	check(not world._view_session.frame_options().get("inspect",false) and not world._view_session.frame_options().get("sensors",true) and not world._view_session.frame_options().get("profiler",true),"absent component stops inspection, sensor and profiler consumers")
	if test.native: check(world.native_view_active,"real native renderer survives absent component")
	second.set_process(true)
	start_ticks=second.ticks
	for unused in 15: await test.process_frame
	check(second.ticks>start_ticks and second.is_current(),"absent component leaves the gameplay camera alive and current")
	check(world.info().time==time and robot.state()==initial,"component removal preserves the real paused world")
	second.set_process(false) # Freeze gameplay animation only for the following camera-handoff assertion.
	var gameplay_view_before_bind: Transform3D=second.get_camera_transform()
	var gameplay_size_before_bind: float=second.size
	# A newly authored component can bind the same live world without resetting it.
	viewer=Viewer.new();viewer.name="ReplacementViewer";viewer.enabled=false;viewer.world=world;test.game_root.add_child(viewer);test.viewer=viewer
	for unused in 5:await test.process_frame
	check(viewer.status=="DISABLED" and not is_instance_valid(viewer.ui) and not is_instance_valid(viewer.bound_world),"initially disabled scene component never installs runtime UI or input ownership")
	viewer.enabled=true
	check(await test.wait_for(active,30),"new explicit component binds a still-running presentation session")
	check(viewer.get_instance_id()!=component_id and viewer.bound_world==world,"new component has its own scene lifetime and explicit target")
	check(viewer.read_state().frame.camera.orthographic and is_equal_approx(viewer.read_state().frame.camera.size,gameplay_size_before_bind) and viewer.read_state().frame.camera.transform.is_equal_approx(gameplay_view_before_bind),"new component captures the current gameplay camera view and projection instead of restoring a stale UI camera")
	check(world.info().time==time and robot.state()==initial,"reattaching UI preserves simulation state")
	await test.issue({"action":"move","mouse":1,"dx":.08,"dy":.06,"perturb":false})
	var layout := UiAcceptance.new();layout.test=test;layout.viewer=viewer
	var point: Vector2=layout.project_normalized(robot.state().bodies.ball.transform.origin)
	await test.issue({"action":"select","button":1,"x":point.x,"y":1-point.y,"aspect":test.render_aspect()})
	await test.issue({"action":"perturb_begin","mode":1})
	await test.issue({"action":"move","mouse":4,"dx":.04,"dy":0.,"perturb":true})
	var edited_view: Dictionary=viewer.read_state().frame.camera.duplicate(true)
	check(edited_view.orthographic,"official orbit preserves the current gameplay orthographic projection")
	var edited: Dictionary=robot.state().duplicate(true)
	check(edited.joints.root.qpos!=initial.joints.root.qpos,"actual paused perturbation edits the live free joint before disabling the component")
	var business_body: RigidBody3D=world.get_node("ExternalForceBody");business_body.constant_force=Vector3(6,0,0)
	viewer.enabled=false
	for unused in 6:await test.process_frame
	var actual: Dictionary=PhysicsServer3D.call("scene_viewer_frame",world.space,-1,{"backend":"native" if test.native else "godot"})
	check(actual.get("perturb_active",-1)==0,"disabling during actual perturbation releases its authoritative gesture")
	var handed_optics: bool=second.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(second.size,edited_view.size) if edited_view.orthographic else second.projection!=Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(second.fov,edited_view.fov)
	var handoff_ok: bool=second.global_transform.is_equal_approx(edited_view.transform) and handed_optics and is_equal_approx(second.near,edited_view.near) and is_equal_approx(second.far,edited_view.far)
	var handoff_diagnostic := {"passed":handoff_ok,"expected_view":edited_view,"actual_frozen_camera":actual.get("camera",{}),"source_global_transform":str(second.global_transform),"source_optical_transform":str(second.get_camera_transform()),"source_projection":second.projection,"source_fov":second.fov,"source_size":second.size,"source_near":second.near,"source_far":second.far,"source_frustum_offset":str(second.frustum_offset),"source_h_offset":second.h_offset,"source_v_offset":second.v_offset,"source_current":second.is_current(),"source_processing":second.is_processing(),"viewport_current_camera":str(world.get_viewport().get_camera_3d())}
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("camera-handoff.json"),FileAccess.WRITE).store_string(JSON.stringify(handoff_diagnostic,"  "))
	if not handoff_ok:print("CAMERA_HANDOFF ",JSON.stringify(handoff_diagnostic))
	check(handoff_ok,"disabling hands the last orbit pose and optics back to the actual gameplay camera")
	if test.native:check(actual.get("camera",{}).get("transform",Transform3D.IDENTITY).is_equal_approx(edited_view.transform) and actual.camera.orthographic==edited_view.orthographic and is_equal_approx(actual.camera.size,edited_view.size),"actual native displayed view keeps its orbit pose and projection during gameplay handoff")
	check(robot.state()==edited and world.info().time==time and world.info().paused and business_body.constant_force==Vector3(6,0,0),"disable preserves the paused edited state, time and independent gameplay force")
	viewer.enabled=true
	check(await test.wait_for(active,30),"re-enable after perturbation presents the existing edited state")
	check(robot.state()==edited and business_body.constant_force==Vector3(6,0,0),"re-enable does not reset the edited world or business force")
	# A command executed by the physics boundary keeps its successful terminal
	# result even if its component stops before the next UI-result poll.
	var retained_session: Node=viewer._session;retained_session.set_process(false)
	var executed_request: int=viewer.execute("control",{"id":0,"value":.35})
	for unused in 3:await test.physics_frame
	check(executed_request>0 and absf(robot.state().controls.drive-.35)<1e-8,"actual control executes while component result polling is held")
	viewer.enabled=false
	var executed_result: Dictionary=viewer.action_result(executed_request)
	check(executed_result.get("success",false) and not executed_result.get("cancelled",false),"disable preserves the truthful success of an already executed command")
	retained_session.set_process(true);viewer.enabled=true
	check(await test.wait_for(active,30),"component re-enables after an already executed result handoff")
	await test.issue({"action":"control","id":0,"value":0.})
	# Cancel a queued transaction before the deferred candidate can commit.
	var old_space: RID=world.space
	var reload_request: int=viewer.execute("reload")
	check(reload_request>0,"real saved-world reload queues before component disable")
	viewer.enabled=false
	for unused in 12:await test.process_frame
	var cancelled_reload: Dictionary=viewer.action_result(reload_request)
	check(cancelled_reload.get("cancelled",false) and is_instance_valid(world) and world.space==old_space and world.info().time==time and world.info().paused,"disabled pending reload never commits a candidate or replaces the live authority")
	viewer.enabled=true
	check(await test.wait_for(active,30) and viewer.bound_world==world,"cancelled reload re-enables on the original actual world")
	var duplicate := Viewer.new();duplicate.name="DuplicateViewer";duplicate.world=world;test.game_root.add_child(duplicate)
	for unused in 8: await test.process_frame
	check(not duplicate.last_error.is_empty() and viewer.bound_world==world and active(),"duplicate target reports failure without hijacking the active component")
	duplicate.queue_free()
	for unused in 3: await test.process_frame
	await invalid_configuration_checks()
	await profiler_stop_checks()
	await committed_reload_disable_checks()
	evidence.append({"native_requested":test.native,"display":DisplayServer.get_name(),"no_ui_camera_ticks":start_ticks,"component_replaced":true,"physics_time":world.info().time,"actual_native_active":world.native_view_active,"frame_slots":world._view_session.frame.get("stats",{}).get("viewer_scene_slots",-1)})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("component-evidence.json"),FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("component-performance.json"),FileAccess.WRITE).store_string(JSON.stringify({"native":test.native,"display":DisplayServer.get_name(),"samples":performance},"  "))
	world.stop_native_view()
	for host in created_hosts:
		if is_instance_valid(host):host.queue_free()
	test.game_root.queue_free()
	for unused in 5: await test.process_frame
