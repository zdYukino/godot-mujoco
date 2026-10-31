extends RefCounted
## Four real component combinations share one authoritative World and one presentation.
var test
var viewer: Node
var extras: Node
var world: Node3D
var observations: Array=[]
var replacement_host: Node
var live_binding: Node
var live_provider: Node
func check(ok: bool, label: String) -> void:test.check(ok,label)
func ready() -> bool:
	return extras.status=="ACTIVE" and viewer.status=="ACTIVE" and viewer.read_state().get("presentation",{}).get("ready",false)
func finish_request(component: Node, id: int, seconds := 10.0) -> Dictionary:
	check(id>0,"split command accepted")
	if id==0:return {}
	check(await test.wait_for(func():return not component.action_result(id).is_empty(),seconds),"split command completes at real authority boundary")
	return component.action_result(id)
func run(tree) -> void:
	test=tree;viewer=tree.viewer;extras=tree.extras;world=tree.world
	check(await test.wait_for(ready,30),"both explicit components bind the same actual world")
	check(viewer._session==extras._session and world._view_session==viewer._session,"both roles reuse one world-owned session")
	check(not viewer.has_method("show_extras") and not viewer.has_method("show_performance") and not viewer.has_method("add_extension"),"original component exposes no combined Extras compatibility API")
	check(not extras.has_method("show_native_panels") and not extras.has_method("add_help"),"Extras exposes no original-panel compatibility API")
	check(viewer.execute("renderer",{"value":0})==0 and viewer.execute("capture_snapshot")==0,"original component rejects Extras-only operations")
	check(extras.execute("select",{"button":1,"x":.5,"y":.5})==0 and extras.execute("help")==0,"Extras rejects scene interaction and original overlays")
	var session: Node=world._view_session
	var time: float=world.info().time
	var source_camera: Camera3D=world.get_viewport().get_camera_3d()
	viewer.enabled=false
	for unused in 8:await test.process_frame
	check(extras.status=="ACTIVE" and extras._session==session and not is_instance_valid(session.consumer),"Extras-only retains its session without interactive consumer")
	check(world.get_viewport().get_camera_3d()==source_camera,"Extras-only preserves gameplay camera ownership")
	await test.key(KEY_F11)
	check(extras.ui.controls.visible,"Extras-only F11 opens its own window")
	await test.key(KEY_F11)
	check(not extras.ui.controls.visible,"Extras-only F11 closes its own window")
	var capture: Dictionary=await finish_request(extras,extras.execute("capture_snapshot"))
	check(capture.get("success",false),"Extras-only snapshot uses actual world state")
	var step: Dictionary=await finish_request(extras,extras.execute("step",{"count":3}))
	check(step.get("success",false) and absf(world.info().time-time-.006)<1e-8,"Extras-only exact step advances real physics without a displayed picking frame")
	var restore: Dictionary=await finish_request(extras,extras.execute("restore_snapshot"))
	check(restore.get("success",false) and is_equal_approx(world.info().time,time),"Extras-only snapshot restore changes real authority")
	await test.create_timer(1.2).timeout
	if DisplayServer.get_name()!="headless":check(extras.read_state().get("host_fps",0)>0 and extras.read_state().get("renderer_fps",0)>0,"Extras-only FPS advances with actual backend presentation")
	if test.native:check(world.native_view_active and world.native_view.latest.get("gl_errors",-1)==0,"Extras-only uses actual native rendering without GL errors")
	else:check(not world.get_viewport().disable_3d and not is_instance_valid(session._godot_viewport),"Extras-only Godot renders directly without a helper viewport")
	viewer.enabled=true
	check(await test.wait_for(ready,30),"original panel can join existing Extras without replacing world")
	# Opposite role teardown must not cancel a real queued operation.
	var step_id: int=extras.execute("step",{"count":2})
	viewer.enabled=false
	step=await finish_request(extras,step_id)
	check(step.get("success",false) and absf(world.info().time-time-.004)<1e-8,"original teardown preserves queued Extras exact steps")
	viewer.enabled=true
	check(await test.wait_for(ready,30),"original rejoins before independent Extras teardown")
	var control_id: int=viewer.execute("control",{"id":0,"value":.23})
	extras.enabled=false
	var control: Dictionary=await finish_request(viewer,control_id)
	check(control.get("success",false) and absf(world.get_node("Robot").state().controls.drive-.23)<1e-8,"Extras teardown preserves queued original control commands")
	check(viewer.status=="ACTIVE" and extras._performance_source==null,"original-only continues while Extras system sampling stops")
	await test.key(KEY_F1)
	check(viewer.ui.windows.help.visible,"original-only retains official F1 help")
	await test.key(KEY_F1)
	await test.key(KEY_F11)
	check(not is_instance_valid(extras.ui),"original-only F11 does not recreate disabled Extras")
	viewer.enabled=false
	for unused in 8:await test.process_frame
	check(not is_instance_valid(session.consumer) and extras._performance_source==null,"neither component leaves no input or optional metric consumer")
	check(is_instance_valid(world) and world.info().time>time,"neither component leaves authoritative world intact")
	if test.native:check(world.native_view_active,"neither component preserves actual native rendering")
	viewer.enabled=true;extras.enabled=true
	check(await test.wait_for(ready,30),"both roles independently re-enable on original authority")
	await renderer_completion_reentrancy()
	await provider_routes()
	await disabled_replacement_follow()
	await duplicate_and_removal()
	await hud_only_widget_lifetime()
	await viewport_fps_provenance()
	await keyboard_owner_scope()
	observations.append({"native_requested":test.native,"native_actual":world.native_view_active,"world":world.get_instance_id(),"space":world.space.get_id(),"time":world.info().time,"original":viewer.read_state().status,"extras":extras.read_state().status})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("split-evidence.json"),FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))
	world.stop_native_view()
	if is_instance_valid(replacement_host):replacement_host.queue_free()
	test.game_root.queue_free()
	for unused in 5:await test.process_frame

func provider_routes() -> void:
	var provider: Node=preload("res://split_provider.gd").new()
	provider.name="SplitProvider";world.add_child(provider);provider.owner=test.game_root
	var binding: Node=preload("res://addons/godot_mujoco/viewer/extension_binding.gd").new()
	binding.name="SplitBinding";binding.viewer=viewer;binding.provider_path=NodePath("SplitProvider")
	test.game_root.add_child(binding);binding.owner=test.game_root
	check(await test.wait_for(func():return viewer.ui.extension_help.has("split_provider")),"help-only Binding populates original F1 from explicit World provider")
	check(provider.help_reads==1 and provider.widget_builds==0 and not extras._extensions.has("split_provider"),"help-only Binding never allocates an unused tool widget")
	extras.enabled=false
	for unused in 3:await test.process_frame
	check(viewer.ui.extension_help.has("split_provider") and provider.widget_builds==0 and not is_instance_valid(extras.ui),"help-only provider works with no active Extras UI")
	extras.enabled=true
	check(await test.wait_for(ready,30),"Extras re-enables independently before tools-only route")
	binding.viewer=null;binding.extras=extras
	check(await test.wait_for(func():return extras._extensions.has("split_provider")),"tools-only Binding populates F11 without a help target")
	check(not viewer.ui.extension_help.has("split_provider") and provider.help_reads==1,"tools-only Binding removes help without reading it again")
	var widget: Button=extras._extensions.split_provider.widget
	check(widget.get_meta("provider_world")==world.get_instance_id(),"tool callback is bound to the actual committed World")
	viewer.enabled=false
	for unused in 3:await test.process_frame
	check(not is_instance_valid(viewer.ui) and extras._extensions.split_provider.widget==widget,"tools-only provider works with no active original panel")
	check(world.set_paused(false),"run authority before standalone provider callback")
	widget.pressed.emit()
	check(provider.presses==1 and await test.wait_for(func():return world.info().paused),"standalone tools callback reaches the actual World without original panel")
	viewer.enabled=true
	check(await test.wait_for(ready,30),"original re-enables independently before dual provider route")
	var widget_id := widget.get_instance_id()
	binding.viewer=viewer
	check(await test.wait_for(func():return viewer.ui.extension_help.has("split_provider")),"both explicit Binding destinations populate independently")
	check(extras._extensions.split_provider.widget.get_instance_id()==widget_id and is_instance_valid(widget) and not widget.is_blocking_signals(),"adding help destination preserves unrelated tools widget and callbacks")
	var help_reads: int=provider.help_reads
	binding.extras=null
	check(await test.wait_for(func():return not extras._extensions.has("split_provider")),"removing tools destination detaches its widget")
	check(viewer.ui.extension_help.has("split_provider") and provider.help_reads==help_reads,"removing tools destination preserves unrelated help route without rereading provider")
	binding.extras=extras
	check(await test.wait_for(func():return extras._extensions.has("split_provider")),"readding tools destination independently creates its widget")
	var packed := PackedScene.new()
	check(packed.pack(test.game_root)==OK and ResourceSaver.save(packed,"res://SavedWorld.tscn")==OK,"save the explicit provider and both independent UI routes for real reload")
	var old_world: int=world.get_instance_id()
	var old_provider := provider.get_instance_id()
	widget=extras._extensions.split_provider.widget;widget_id=widget.get_instance_id()
	var reload: Dictionary=await finish_request(viewer,viewer.execute("reload"),125.0)
	check(reload.get("success",false),"real saved reload commits with two independent Binding routes")
	check(await test.wait_for(func():return ready() and viewer.bound_world==extras.bound_world and viewer.bound_world.get_instance_id()!=old_world,30),"both roles follow the same committed replacement World")
	world=viewer.bound_world;test.world=world
	provider=world.get_node("SplitProvider")
	check(provider.get_instance_id()!=old_provider and provider.widget_builds==1 and provider.help_reads==1,"committed replacement reconstructs help and tools exactly once each")
	check(extras._extensions.has("split_provider") and extras._extensions.split_provider.widget.get_instance_id()!=widget_id,"saved reload retires the previous world's tool widget")
	check(viewer.ui.extension_help.split_provider.contains(str(world.get_instance_id())),"F1 help belongs to the replacement World")
	widget=extras._extensions.split_provider.widget
	check(widget.get_meta("provider_world")==world.get_instance_id(),"new tool stores replacement World identity")
	check(world.set_paused(false),"run replacement authority before tool callback")
	widget.pressed.emit()
	check(provider.presses==1 and await test.wait_for(func():return world.info().paused),"replacement tool callback changes actual replacement physics state")
	var stable_widget_id := widget.get_instance_id()
	var stable_world_id := world.get_instance_id()
	var host: Node=viewer.environment_host
	replacement_host=host
	var saved_scene: PackedScene=host.environment_scene
	var invalid := Node.new();var invalid_scene := PackedScene.new();invalid_scene.pack(invalid);invalid.free()
	host.environment_scene=invalid_scene
	reload=await finish_request(viewer,viewer.execute("reload"),125.0)
	check(not reload.get("success",true) and viewer.bound_world==world and extras.bound_world==world and world.get_instance_id()==stable_world_id,"failed real reload preserves both component bindings and old authority")
	check(extras._extensions.split_provider.widget.get_instance_id()==stable_widget_id and provider.widget_builds==1 and provider.help_reads==1,"failed reload retains existing help and tools without rebuilding callbacks")
	host.environment_scene=saved_scene
	binding.viewer=null;binding.extras=null
	check(await test.wait_for(func():return not viewer.ui.extension_help.has("split_provider") and not extras._extensions.has("split_provider")),"removing both Binding destinations retires only their owned content")
	binding.viewer=viewer;binding.extras=extras
	check(await test.wait_for(func():return viewer.ui.extension_help.has("split_provider") and extras._extensions.has("split_provider")),"restore both live routes before actual destination removal")
	live_binding=binding;live_provider=provider

func duplicate_and_removal() -> void:
	var session: Node=world._view_session
	var duplicate: Node=preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new()
	duplicate.world=world;duplicate.restore_preferences=false;test.game_root.add_child(duplicate)
	check(await test.wait_for(func():return duplicate.status=="CONFIGURATION_ERROR"),"duplicate Extras reaches explicit configuration rejection")
	check(duplicate.last_error=="This target viewport already has Godot Extras" and session.extras_client==extras and session.consumer==viewer,"duplicate Extras reports failure without hijacking either active role")
	duplicate.queue_free();await test.process_frame
	var time: float=world.info().time
	var original_id := viewer.get_instance_id()
	var help_reads: int=live_provider.help_reads
	extras.queue_free()
	for unused in 3:await test.process_frame
	check(not is_instance_valid(session.extras_client) and viewer.status=="ACTIVE" and viewer.get_instance_id()==original_id,"removing Extras leaves original UI and ownership intact")
	check(viewer.ui.extension_help.has("split_provider") and live_provider.help_reads==help_reads,"freeing live Binding Extras destination preserves original help without rebuilding")
	var control: Dictionary=await finish_request(viewer,viewer.execute("control",{"id":0,"value":.17}))
	check(control.get("success",false) and absf(world.get_node("Robot").state().controls.drive-.17)<1e-8,"original controls still change real state after Extras removal")
	extras=preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new()
	extras.name="ReplacementExtras";extras.world=world;extras.restore_preferences=false;test.game_root.add_child(extras);test.extras=extras
	check(await test.wait_for(ready,30),"independently added replacement Extras binds without recreating original")
	live_binding.extras=extras
	check(await test.wait_for(func():return extras._extensions.has("split_provider")),"Binding replaces its freed Extras destination without stale-reference errors")
	check(viewer.ui.extension_help.has("split_provider") and live_provider.help_reads==help_reads,"rebinding tools after removal leaves existing help untouched")
	var widget_id: int=extras._extensions.split_provider.widget.get_instance_id()
	viewer.queue_free()
	for unused in 3:await test.process_frame
	check(not is_instance_valid(session.consumer) and extras.status=="ACTIVE","removing original leaves standalone Extras UI and ownership intact")
	check(extras._extensions.split_provider.widget.get_instance_id()==widget_id,"freeing live Binding original destination preserves existing tool callbacks")
	var step: Dictionary=await finish_request(extras,extras.execute("step",{"count":2}))
	check(step.get("success",false) and absf(world.info().time-time-.004)<1e-8,"Extras steps actual authority after original removal")
	viewer=preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd").new()
	viewer.name="ReplacementViewer";viewer.world=world;viewer.restore_preferences=false;test.game_root.add_child(viewer);test.viewer=viewer
	check(await test.wait_for(ready,30),"independently added original restores presentation alongside existing Extras")
	live_binding.viewer=viewer
	check(await test.wait_for(func():return viewer.ui.extension_help.has("split_provider")),"Binding replaces its freed original destination without stale-reference errors")
	check(extras._extensions.split_provider.widget.get_instance_id()==widget_id,"rebinding help after removal leaves existing tools untouched")

func disabled_replacement_follow() -> void:
	var previous_host: Node=replacement_host
	viewer.environment_host=null;viewer.world=world
	extras.enabled=false;extras.environment_host=null;extras.world=world
	var dormant: Node=preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new()
	dormant.name="InitiallyDisabledExtras";dormant.enabled=false;dormant.world=world;dormant.restore_preferences=false;test.game_root.add_child(dormant)
	check(await test.wait_for(func():return viewer.status=="ACTIVE" and viewer.bound_world==world,30),"original binds the explicit direct World before disabled-counterpart reload")
	check(not is_instance_valid(dormant._session) and not is_instance_valid(dormant.ui) and dormant._performance_source==null,"initially disabled counterpart observes target without session UI or sampler")
	var old_id := world.get_instance_id()
	var reload: Dictionary=await finish_request(viewer,viewer.execute("reload"),125.0)
	check(reload.get("success",false),"direct saved replacement commits while both Extras components are disabled")
	check(await test.wait_for(func():return viewer.status=="ACTIVE" and is_instance_valid(viewer.bound_world) and viewer.bound_world.get_instance_id()!=old_id,30),"original follows successful direct replacement")
	world=viewer.bound_world;test.world=world;replacement_host=viewer.environment_host
	check(extras.environment_host==replacement_host and dormant.environment_host==replacement_host and extras.world==null and dormant.world==null,"previously active and initially disabled counterparts follow only their committed authored target")
	check(not is_instance_valid(extras.ui) and not is_instance_valid(dormant.ui) and not is_instance_valid(dormant._session),"passive replacement notification never activates disabled counterparts")
	dormant.queue_free();await test.process_frame
	extras.enabled=true
	check(await test.wait_for(ready,30) and extras.bound_world==world,"disabled Extras re-enables on the committed replacement without manual retargeting")
	if is_instance_valid(previous_host):previous_host.queue_free()
	viewer.enabled=false
	var host: Node=replacement_host
	old_id=world.get_instance_id()
	check(host.request_rebuild_environment(true),"external Host rebuild starts with original disabled and Extras active")
	check(await test.wait_for(func():return is_instance_valid(extras.bound_world) and extras.bound_world.get_instance_id()!=old_id and extras.status=="ACTIVE",125),"active Extras follows an external Host commit independently")
	check(not is_instance_valid(viewer.ui) and not is_instance_valid(viewer._session),"external Host commit keeps disabled original presentation inactive")
	viewer.enabled=true
	check(await test.wait_for(ready,30) and viewer.bound_world==extras.bound_world,"disabled original re-enables on latest external Host commit")
	world=viewer.bound_world;test.world=world;live_provider=world.get_node("SplitProvider")

func hud_only_widget_lifetime() -> void:
	viewer.enabled=false;extras.enabled=false
	for unused in 3:await test.process_frame
	var session: Node=world._view_session
	var space: RID=world.space
	check(not is_instance_valid(session.consumer) and not is_instance_valid(session.extras_client),"HUD-only custom probe begins without either active default UI role")
	# Author a minimal PackedScene in memory: only the public Extras presenter
	# and a metric Label. No Examples slot, Window, camera region or hidden panel.
	var root_ui: Control=preload("res://addons/godot_mujoco/viewer/extras_ui.gd").new()
	root_ui.name="AuthoredHudOnly";root_ui.use_default_presenters=false
	var hud := Label.new();hud.name="AuthoredFps";hud.text="FPS";hud.set_meta("viewer_role","hud")
	root_ui.add_child(hud);hud.owner=root_ui
	var packed := PackedScene.new()
	check(packed.pack(root_ui)==OK,"author a valid HUD-only Extras PackedScene without Examples slot")
	root_ui.free()
	var custom: Node=preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new()
	custom.name="HudOnlyExtras";custom.world=world;custom.ui_scene=packed;custom.restore_preferences=false
	var before_attach := Button.new();before_attach.text="Explicit pre-attach tool"
	custom.add_extension("held","Held tool",before_attach)
	test.game_root.add_child(custom)
	check(await test.wait_for(func():return custom.status=="ACTIVE" and is_instance_valid(custom.ui)),"HUD-only Extras binds directly without an original panel")
	check(not is_instance_valid(session.consumer) and session.extras_client==custom and not is_instance_valid(custom.ui.controls) and custom.ui.extras_sections.is_empty(),"custom HUD-only scene installs no original panel or implicit F11 Window")
	check(before_attach.get_parent()==custom._extension_holder and custom.is_ancestor_of(before_attach) and not before_attach.is_visible_in_tree() and not before_attach.can_process(),"pre-attach extension stays in an owned inactive holder when authored UI has no Examples slot")
	custom.add_extension("held","Same held tool",before_attach)
	await test.process_frame
	check(is_instance_valid(before_attach) and not before_attach.is_queued_for_deletion() and before_attach.get_parent()==custom._extension_holder,"same-key same-widget registration preserves the owned widget")
	custom.remove_extension("held")
	await test.process_frame
	check(not is_instance_valid(before_attach) and not custom._extensions.has("held"),"explicit removal frees a held widget absent from the custom presenter")
	var while_active := Button.new();while_active.text="Explicit active tool"
	custom.add_extension("active","Active tool",while_active)
	check(while_active.get_parent()==custom._extension_holder and custom.is_ancestor_of(while_active),"active registration also owns widgets omitted by the authored scene")
	custom.enabled=false
	for unused in 3:await test.process_frame
	check(is_instance_valid(while_active) and while_active.get_parent()==custom._extension_holder and not while_active.can_process() and not is_instance_valid(custom.ui),"disabling custom HUD preserves owned inactive widgets without orphaning them")
	custom.enabled=true
	check(await test.wait_for(func():return custom.status=="ACTIVE" and is_instance_valid(custom.ui)),"custom HUD can re-enable with retained extension ownership")
	check(is_instance_valid(while_active) and while_active.get_parent()==custom._extension_holder and not is_instance_valid(session.consumer),"reenabling HUD-only Extras does not create a hidden original counterpart")
	check(custom.execute("controls")==0 and custom.last_error.contains("presentation module"),"omitted F11 module is explicitly unavailable in a HUD-only scene")
	custom.queue_free()
	for unused in 3:await test.process_frame
	check(not is_instance_valid(while_active) and not is_instance_valid(session.extras_client),"removing custom component frees held widgets and releases only its Extras role")
	check(is_instance_valid(world) and world.space==space,"custom widget lifetime leaves the authoritative World and space unchanged")
	viewer.enabled=true;extras.enabled=true
	check(await test.wait_for(ready,30),"default original and Extras components re-enable after HUD-only lifetime probe")

func renderer_completion_reentrancy() -> void:
	var initial_native: bool=world.native_view_active
	var first: int=extras.execute("renderer",{"native":false})
	check(first>0,"real renderer request queues before same-frame completion callback")
	var callbacks := {"seen":false}
	var disable_on_result := func(id: int,_result: Dictionary):
		if id==first:callbacks.seen=true;extras.enabled=false
	extras.action_finished.connect(disable_on_result)
	var second: int=extras.execute("renderer",{"native":false})
	extras.action_finished.disconnect(disable_on_result)
	check(callbacks.seen and not extras.enabled and second==0,"renderer supersession rejects after its real completion callback disables Extras")
	check(extras.action_result(first).get("success",false) and not extras.action_result(first).get("cancelled",false),"already reached Godot backend reports actual completion before supersession")
	check(not world.native_view_active and extras._operations.is_empty() and viewer.status=="ACTIVE","callback disable leaves no new renderer work and preserves original component")
	extras.enabled=true
	check(await test.wait_for(ready,30),"Extras independently re-enables after renderer completion callback")
	first=extras.execute("renderer",{"native":false})
	var replacement := {"request":0}
	var replace_on_result := func(id: int,_result: Dictionary):
		if id==first:replacement.request=extras.execute("renderer",{"native":false})
	extras.action_finished.connect(replace_on_result)
	second=extras.execute("renderer",{"native":false})
	extras.action_finished.disconnect(replace_on_result)
	check(second==0 and replacement.request>0,"newer renderer request from completion callback supersedes outer dispatch safely")
	var latest: Dictionary=await finish_request(extras,replacement.request)
	check(latest.get("success",false) and extras._operations.is_empty(),"recursive real renderer request reaches one truthful terminal completion")
	if initial_native:
		var restored: Dictionary=await finish_request(extras,extras.execute("renderer",{"native":true}),30)
		check(restored.get("success",false) and world.native_view_active,"native backend restores after real renderer callback regression")

func viewport_fps_provenance() -> void:
	var viewport: Viewport=world.get_viewport()
	check(viewport is SubViewport,"committed replacement exposes the actual authored SubViewport")
	if not viewport is SubViewport:return
	var initial_native: bool=world.native_view_active
	var backend: Dictionary=await finish_request(extras,extras.execute("renderer",{"native":false}),30.0)
	check(backend.get("success",false),"FPS provenance uses actual Godot target rendering")
	viewer.enabled=false
	var mode: int=viewport.render_target_update_mode
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	await test.create_timer(1.2).timeout
	var disabled: Dictionary=extras.read_state()
	check(disabled.renderer_fps_available and disabled.renderer_fps==0.0 and not is_instance_valid(world._view_session.consumer),"disabled target does not count host draws as target FPS")
	if DisplayServer.get_name()!="headless":check(disabled.host_fps>0,"host continues rendering while the target SubViewport is disabled")
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	await test.create_timer(.7).timeout
	var conditional: Dictionary=extras.read_state()
	check(not conditional.renderer_fps_available and not conditional.renderer_fps_reason.is_empty() and conditional.renderer_fps==0.0,"conditional SubViewport update rate is explicitly unavailable rather than inferred from host")
	check(extras.ui.hud.text.contains("Godot host FPS") and extras.ui.hud.text.contains("target FPS unavailable") and not extras.ui.hud.tooltip_text.is_empty(),"conditional target HUD labels host FPS and explains target rate limitation")
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	await test.create_timer(1.2).timeout
	check(extras.read_state().renderer_fps_available,"always-updated target restores direct-renderer FPS availability")
	if DisplayServer.get_name()!="headless":check(extras.read_state().renderer_fps>0,"always-updated SubViewport produces live actual backend FPS without an original viewer")
	viewport.render_target_update_mode=mode
	viewer.enabled=true
	check(await test.wait_for(ready,30),"original presentation rejoins after independent FPS provenance probe")
	if initial_native:
		backend=await finish_request(extras,extras.execute("renderer",{"native":true}),30.0)
		check(backend.get("success",false) and world.native_view_active,"FPS probe restores actual native backend")

func keyboard_owner_scope() -> void:
	var window: Window=extras.get_window()
	var saved_rect: Rect2=extras._target_rect
	# Force pointer outside the accepted region without depending on desktop position.
	extras._target_rect=Rect2(-10000,-10000,1,1)
	window.set_meta("mj_viewer_keyboard_owner",viewer)
	var key := InputEventKey.new();key.keycode=KEY_F11;key.pressed=true
	check(extras.key_input(key) and extras.ui.controls.visible,"original panel keyboard owner opens same-world F11 outside pointer region")
	extras.show_extras(false)
	viewer.enabled=false
	extras._target_rect=saved_rect
	var press := InputEventMouseButton.new();press.pressed=true;press.button_index=MOUSE_BUTTON_LEFT;press.position=saved_rect.get_center()
	extras.global_input(press,extras.get_viewport())
	check(window.get_meta("mj_viewer_keyboard_owner")==extras,"Extras-only target click owns keyboard without an original component")
	extras._target_rect=Rect2(-10000,-10000,1,1)
	key=InputEventKey.new();key.keycode=KEY_F11;key.pressed=true
	check(extras.key_input(key) and extras.ui.controls.visible,"Extras-only keyboard owner retains F11 outside pointer region")
	extras.show_extras(false)
	var other := MjGodotExtras.new()
	# Isolated ownership predicate: this live client is not either session role.
	other.status="ACTIVE"
	window.set_meta("mj_viewer_keyboard_owner",other)
	key=InputEventKey.new();key.keycode=KEY_F11;key.pressed=true
	check(not extras.key_input(key) and not extras.ui.controls.visible,"unrelated component keyboard owner cannot open this viewport F11")
	other.enabled=false
	extras._target_rect=Rect2(-100000,-100000,200000,200000)
	check(extras._owns_keyboard_scope(),"disabled keyboard owner falls back to the target pointer scope")
	other.free()
	check(extras._owns_keyboard_scope(),"freed keyboard owner falls back without stale-object access")
	window.remove_meta("mj_viewer_keyboard_owner")
	extras._target_rect=saved_rect
	viewer.enabled=true
	check(await test.wait_for(ready,30),"both components restore after keyboard ownership lifecycle")
	window.set_meta("mj_viewer_keyboard_owner",extras)
	check(viewer._keyboard_scope(),"original shortcuts accept the same-world Extras keyboard owner")
