extends RefCounted
## Saved custom UI, policies and independent personal preferences on real worlds.
const Extras = preload("res://addons/godot_mujoco/viewer/godot_extras.gd")
const Viewer = preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd")
const Configuration = preload("res://addons/godot_mujoco/viewer/configuration.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const UiAcceptance = preload("res://ui_acceptance.gd")
var test
var viewer: Node
var extras: Node
var world: Node3D
var observations := []
var gameplay_mesh: MeshInstance3D
var gameplay_label: Label
var untouched_viewport: SubViewport
func check(ok: bool, label: String) -> void:test.check(ok,label)
func active() -> bool:
	return is_instance_valid(viewer._session) and viewer.read_state().get("presentation",{}).get("ready",false)
func frame() -> Dictionary:return viewer.read_state().frame
func capture(label: String) -> Image:
	if DisplayServer.get_name()=="headless":return Image.new()
	await RenderingServer.frame_post_draw
	var image: Image=test.root.get_texture().get_image()
	check(image.save_png(OS.get_environment("GMJ_VIEWER_OUT").path_join(label+".png"))==OK,"custom component screenshot saved "+label)
	return image
func mouse_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=point;event.global_position=point
	Input.parse_input_event(event);await test.process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await test.process_frame
func policy_checks() -> void:
	var cfg: Resource=viewer.configuration
	await test.issue({"action":"camera","id":2})
	var info: Dictionary=world.info()
	var current_camera: Transform3D=frame().camera.transform
	for internal_action in ["sync_external_camera","seed_camera","restore_camera","end_gesture"]:
		check(viewer.execute(internal_action,{})==0 and not viewer.last_error.is_empty(),"public component rejects internal session action "+internal_action)
	cfg.disabled_groups=PackedStringArray(["simulation","selection","perturbation","output"])
	cfg.disabled_actions=PackedStringArray(["camera:0"]);cfg.emit_changed()
	for unused in 4:await test.process_frame
	check(await test.wait_for(active),"configured feature policy presents a current frame before input checks")
	for button in [0,3]:
		check(viewer.execute("select",{"button":button,"x":.5,"y":.5,"aspect":test.render_aspect()})==0 and viewer.last_error.contains("selection"),"alternate body-select button remains governed by the selection group "+str(button))
	for action in ["history_forward","reset_initial","select","perturb_begin","save_xml"]:
		check(viewer.execute(action,{"count":1,"button":1,"x":.5,"y":.5,"aspect":test.render_aspect(),"mode":1})==0 and not viewer.last_error.is_empty(),"configured group rejects component action "+action)
	check(viewer.execute("camera",{"id":0})==0,"specific camera action is rejected by the public command API")
	check(viewer.execute("camera")==0,"omitted camera id normalizes before the specific camera policy")
	await test.key(KEY_ESCAPE)
	var camera_choice: OptionButton=viewer.ui.fields.camera_choice
	check(not camera_choice.disabled and camera_choice.is_item_disabled(0) and not camera_choice.is_item_disabled(2),"disabling free camera keeps allowed fixed camera dropdown items usable")
	camera_choice.item_selected.emit(0)
	for unused in 5:await test.process_frame
	check(frame().camera.type==2 and frame().camera.transform.is_equal_approx(current_camera),"disabled free camera agrees across Esc and Rendering dropdown")
	var center_request: int=viewer.execute("select",{"button":2,"x":.5,"y":.5,"aspect":test.render_aspect()})
	check(center_request>0 and await test.wait_for(func():return not viewer.action_result(center_request).is_empty()) and viewer.action_result(center_request).get("success",false),"right-button camera centering remains allowed when only body selection is disabled")
	await test.key(KEY_SPACE);await test.key(KEY_BACKSPACE)
	viewer.ui.sections.Simulation.button.button_pressed=true
	var reset: BaseButton=viewer.ui.get_action_control("reset_initial")
	viewer.ui.left_panel.ensure_control_visible(reset)
	for unused in 3:await test.process_frame
	await mouse_click(reset.get_global_rect().get_center())
	check(reset.is_visible_in_tree() and reset.disabled and world.info().time==info.time and world.info().paused==info.paused,"disabled simulation button and real keys preserve authoritative time and pause")
	check(not viewer.ui.fields.help_actions.text.contains("初始重置") and not viewer.ui.fields.help_actions.text.contains("自由相机"),"help omits configured unavailable simulation and camera actions")
	var request: int=world.step_simulation(2)
	check(request>0 and await test.wait_for(func():return world.command_request==0),"gameplay World API remains available under component feature limits")
	check(absf(world.info().time-info.time-.004)<1e-8,"ordinary gameplay step advances real physics while component simulation is disabled")
	cfg.disabled_groups=PackedStringArray(["camera"]);cfg.emit_changed()
	check(viewer.execute("move",{"mouse":4,"dx":.1,"dy":0.})==0,"omitted perturb flag normalizes to camera motion before group policy")
	cfg.disabled_groups=PackedStringArray();cfg.disabled_actions=PackedStringArray();cfg.emit_changed()
	await test.issue({"action":"reset_initial"})
	await test.issue({"action":"camera","id":0})
	check(await test.wait_for(active),"current camera frame is ready before default public motion")
	var before_move: Transform3D=frame().camera.transform
	var before_pose: Dictionary=world.get_node("Robot").state().duplicate(true)
	await test.issue({"action":"move","mouse":1,"dx":.03,"dy":0.})
	check(await test.wait_for(func():return not frame().camera.transform.is_equal_approx(before_move)) and world.get_node("Robot").state()==before_pose,"public move without perturb flag moves the camera and leaves paused bodies unchanged")
	await test.issue({"action":"align"})
	viewer.show_native_panels(false,false)
	check(viewer.execute("frame",{"value":1})>0,"hiding allowed controls does not disable their component actions")
	check(await test.wait_for(func():return frame().settings.frame==1),"allowed hidden action reaches the actual display frame")
	await test.issue({"action":"frame","value":0})
func preferences_checks(resource: Resource) -> void:
	viewer.show_info(true);extras.show_performance(false);viewer.save_view_preferences(true);extras.save_view_preferences(true)
	check(viewer.execute("performance")==0 and extras.execute("info")==0,"each public API rejects the other role presentation actions")
	var main_path: String=viewer._config_path
	var main_extras_path: String=extras._config_path
	var selected_renderer=ProjectSettings.get_setting("rendering/mujoco_native_view/renderer",0)
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",0)
	var container := SubViewportContainer.new();container.name="IndependentViewport";container.position=Vector2(10,10);container.size=Vector2(900,650);container.stretch=true;test.game_root.add_child(container)
	var viewport := SubViewport.new();viewport.name="WorldViewport";viewport.own_world_3d=true;viewport.size=Vector2i(900,650);container.add_child(viewport)
	var other_world := World.new();other_world.name="OtherWorld";other_world.world_design=resource.fork();other_world.start_paused=true;other_world.native_view_experimental=false
	var robot := Instance.new();robot.name="Robot";robot.design=resource;other_world.add_child(robot)
	var camera := Camera3D.new();camera.position=Vector3(0,2,5);other_world.add_child(camera);viewport.add_child(other_world)
	var other := Viewer.new();other.name="IndependentViewer";other.world=other_world;other.preferences_id="independent-personal-view";other.restore_preferences=false;viewport.add_child(other)
	var other_extras := Extras.new();other_extras.name="IndependentExtras";other_extras.world=other_world;other_extras.preferences_id=other.preferences_id;other_extras.restore_preferences=false;viewport.add_child(other_extras)
	check(await test.wait_for(func():return other_extras.status=="ACTIVE"),"independent Extras binds the secondary World directly")
	check(await test.wait_for(func():return other.status=="ACTIVE" and not other.read_state().frame.is_empty(),120),"second explicit component binds a separate real viewport and world")
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",selected_renderer)
	if other.status!="ACTIVE" or other_extras.status!="ACTIVE":container.queue_free();return
	check(other._config_path!=main_path and not other.ui.info_enabled and other_extras.ui.overlay_enabled,"separate supported viewports have independent default personal state")
	check(await test.wait_for(func():return other.read_state().get("presentation",{}).get("ready",false)),"source-local secondary viewport presents a current frozen frame")
	check(other.get_viewport()==other_world.get_viewport() and other.ui.render_region.get_global_rect().is_equal_approx(other._session.render_rect_in_source()),"a component inside its target SubViewport shares the exact local render and input rectangle")
	other.show_info(false);other_extras.show_performance(true);other.save_view_preferences(true);other_extras.save_view_preferences(true)
	var other_path: String=other._config_path
	var other_extras_path: String=other_extras._config_path
	check(main_path!=main_extras_path and other_path!=other_extras_path and main_extras_path!=other_extras_path,"same preference ID is isolated by native and Extras roles and viewport components")
	var primary := ConfigFile.new();primary.load(main_path)
	var secondary := ConfigFile.new();secondary.load(other_path)
	var primary_extras := ConfigFile.new();primary_extras.load(main_extras_path)
	var secondary_extras := ConfigFile.new();secondary_extras.load(other_extras_path)
	check(primary.get_value("view","info",false) and not primary_extras.get_value("view","performance",true) and not secondary.get_value("view","info",true) and secondary_extras.get_value("view","performance",false),"two viewports save independent native Info and Extras performance preferences")
	check(not primary.has_section_key("view","performance") and not secondary.has_section("metrics") and not primary_extras.has_section_key("view","info"),"each role serializes only its own native or Extras preference categories")
	secondary.set_value("view","info",true);secondary.save(other_path)
	secondary_extras.set_value("view","performance",false);secondary_extras.save(other_extras_path)
	other_extras.enabled=false
	other.enabled=false
	for unused in 3:await test.process_frame
	other.enabled=true;other_extras.enabled=true
	check(await test.wait_for(func():return other.status=="ACTIVE" and other_extras.status=="ACTIVE"),"restore-opt-out component re-enables on the same real world")
	check(not other.ui.info_enabled and other_extras.ui.overlay_enabled,"restore_preferences false ignores a saved conflicting personal state")
	other_extras.configuration.allowed_preferences=PackedStringArray(["metrics"]);other_extras.configuration.allowed_metrics=PackedStringArray(["fps"]);other_extras.configuration.emit_changed()
	check(other_extras.execute("metric",{"name":"cpu","value":true})==0 and not other_extras.last_error.is_empty(),"authored metric restriction cannot be widened by preferences or API")
	var serialized := FileAccess.get_file_as_string(main_path)+FileAccess.get_file_as_string(other_path)+FileAccess.get_file_as_string(main_extras_path)+FileAccess.get_file_as_string(other_extras_path)
	check(not serialized.contains("qpos") and not serialized.contains("qvel") and not serialized.contains("world=") and not serialized.contains("enabled=") and not serialized.contains("snapshot="),"personal view files contain no simulation state, component target or Enabled setting")
	var old_state: Dictionary=other_world.get_node("Robot").state().duplicate(true)
	var old_time: float=other_world.info().time
	var retarget_control: int=other.execute("control",{"id":0,"value":.8})
	var retarget_step: int=other.execute("history_forward")
	other.world=null
	for unused in 5:await test.process_frame
	check(retarget_control>0 and retarget_step>0 and other.action_result(retarget_control).get("cancelled",false) and other.action_result(retarget_step).get("cancelled",false),"same-frame explicit retarget cancels queued component commands")
	check(other_world.info().time==old_time and other_world.get_node("Robot").state()==old_state,"retargeted component commands never alter the old live world control or time")
	other.world=other_world
	check(await test.wait_for(func():return other.status=="ACTIVE"),"explicit component rebinds its surviving world after cancelled retarget work")
	var exit_control: int=other.execute("control",{"id":0,"value":.6})
	var exit_step: int=other.execute("history_forward")
	other_world.queue_free()
	for unused in 4:await test.process_frame
	check(not is_instance_valid(other.bound_world) and not is_instance_valid(other.ui) and other.execute("history_forward")==0,"independent World destruction immediately releases its scene-owned component UI and input")
	check(not is_instance_valid(other_extras.bound_world) and not is_instance_valid(other_extras.ui) and other_extras.execute("step",{"count":1})==0,"World destruction independently releases Extras UI and command binding")
	check(not other.action_result(exit_control).is_empty() and not other.action_result(exit_step).is_empty(),"World exit resolves pending component commands without orphaned completions")
	observations.append({"primary_preferences":main_path,"secondary_preferences":other_path,"primary_space":world.space.get_id(),"secondary_component_status":other.status})
	container.queue_free()
	for unused in 5:await test.process_frame
func run(tree) -> void:
	test=tree;world=test.world;extras=test.extras
	untouched_viewport=SubViewport.new();untouched_viewport.name="UnrelatedViewport";untouched_viewport.own_world_3d=true;untouched_viewport.disable_3d=false;test.game_root.add_child(untouched_viewport)
	gameplay_mesh=MeshInstance3D.new();gameplay_mesh.name="GameplayMeshOutsideRuntime";gameplay_mesh.mesh=BoxMesh.new();gameplay_mesh.mesh.size=Vector3(.5,.5,.5);gameplay_mesh.position=Vector3(-.8,2,0)
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color(.95,.05,.85);gameplay_mesh.material_override=material;test.game_root.add_child(gameplay_mesh)
	var light := DirectionalLight3D.new();light.name="GameplayLighting";light.rotation_degrees=Vector3(-50,-30,0);test.game_root.add_child(light)
	gameplay_label=Label.new();gameplay_label.name="Gameplay2D";gameplay_label.text="Gameplay UI unaffected";gameplay_label.position=Vector2(12,12);gameplay_label.modulate=Color(.2,1,.2);test.game_root.add_child(gameplay_label)
	var old: Node=test.viewer;old.queue_free()
	for unused in 4:await test.process_frame
	var resource: Resource=world.get_node("Robot").design
	var theme := Theme.new();theme.set_color("font_color","Label",Color(.1,.9,.8));theme.set_font_size("font_size","Button",19)
	check(ResourceSaver.save(theme,"res://custom_theme.tres")==OK,"custom Theme resource saves")
	var cfg := Configuration.new()
	check(ResourceSaver.save(cfg,"res://custom_features.tres")==OK,"custom feature Resource saves")
	viewer=Viewer.new();viewer.name="AuthoredCustomViewer";viewer.world=world;viewer.ui_scene=load("res://custom_ui.tscn");viewer.ui_theme=load("res://custom_theme.tres");viewer.configuration=load("res://custom_features.tres");viewer.preferences_id="custom-contract";test.game_root.add_child(viewer);test.viewer=viewer
	check(await test.wait_for(active,30),"saved inherited UI binds the real shared renderer")
	if not active():test.game_root.queue_free();return
	var title: Label=viewer.ui.get_node("MainLayout/MuJoCoLeftPanel/@MarginContainer@6/@VBoxContainer@7/OptionSection/@Label@9")
	check(title.text=="Custom options" and viewer.ui.theme==viewer.ui_theme and title.get_theme_color("font_color")==Color(.1,.9,.8),"saved inherited widget text and authored Theme survive presenter updates")
	check(viewer.ui.get_node("MainLayout").get_global_rect().position.is_equal_approx(Vector2(90,70)),"authored UI keeps horizontal and vertical layout margins")
	check(viewer.execute("ui_color",{"value":1})==0 and not viewer.last_error.is_empty(),"authored Theme cannot be replaced by a runtime palette command")
	var before_snapshot: Dictionary=viewer.read_state()
	var before_mode: int=before_snapshot.frame.camera.type
	var camera_count: int=before_snapshot.catalog.cameras.size()
	before_snapshot.frame.camera.type=99;before_snapshot.catalog.cameras.clear()
	viewer.ui.frame.camera.type=98;viewer.ui.catalog.cameras.clear()
	check(viewer.read_state().frame.camera.type==before_mode and viewer.read_state().catalog.cameras.size()==camera_count,"public and UI value snapshots cannot mutate the authoritative presentation session")
	var content: Control=viewer.ui.get_node("MainLayout/MuJoCoLeftPanel/@MarginContainer@6/@VBoxContainer@7/RenderingContents")
	var section_note: Node=content.get_node("AuthoredSectionNote");var catalog_note: Node=content.get_node("Catalog/AuthoredCatalogNote")
	var section_id: int=section_note.get_instance_id();var catalog_id: int=catalog_note.get_instance_id()
	viewer.ui.build_catalog();viewer.ui.build_catalog()
	for unused in 4:await test.process_frame
	check(is_instance_valid(section_note) and is_instance_valid(catalog_note) and content.get_node("AuthoredSectionNote").get_instance_id()==section_id and content.get_node("Catalog/AuthoredCatalogNote").get_instance_id()==catalog_id,"catalog refresh preserves saved authored children in sections and Catalog slots")
	await policy_checks()
	var layout := UiAcceptance.new();layout.test=test;layout.viewer=viewer
	await layout.layout_picking("custom-reserved",world.get_node("Robot").state().bodies.ball.transform.origin)
	viewer.show_native_panels(false,false)
	check(await test.wait_for(active),"reduced-height custom region presents a current frame")
	var before: Image=await capture("component-custom-reserved")
	check(gameplay_label.is_visible_in_tree() and not untouched_viewport.disable_3d,"target reserved rendering preserves independent viewport flags and gameplay 2D UI")
	if not test.native and not before.is_empty():
		var uv: Vector2=layout.project_normalized(gameplay_mesh.global_position)
		var pixel: Vector2=viewer.ui.render_region.get_global_rect().position+uv*viewer.ui.render_region.size
		var color: Color=before.get_pixelv(Vector2i(pixel))
		check(color.r>.65 and color.b>.55 and color.g<.35,"actual Godot reserved pixels retain a gameplay MeshInstance3D outside the bound Runtime subtree")
	await test.issue({"action":"move","mouse":1,"dx":.06,"dy":.02,"perturb":false})
	var after: Image=await capture("component-custom-reserved-moved")
	if not before.is_empty() and not after.is_empty():
		var changes := 0
		for x in range(10,before.get_width()-10,11):
			for y in [12,24,36,before.get_height()-24]:
				if before.get_pixel(x,y)!=after.get_pixel(x,y):changes+=1
		check(changes==0,"actual reserved rendering does not leak moving 3D pixels into transparent top and bottom margins")
	await test.issue({"action":"align"})
	viewer.layout_mode=Viewer.LayoutMode.OVERLAY
	check(await test.wait_for(func():return active() and viewer._session.render_rect_in_source().size.is_equal_approx(test.root.get_visible_rect().size)),"overlay mode renders the full actual viewport behind custom UI")
	await capture("component-custom-overlay")
	# Clear the earlier reserved-layout selection before exercising real overlay input.
	await test.issue({"action":"select","button":1,"x":.98,"y":.02,"aspect":test.render_aspect()})
	check(frame().selected_body==0,"overlay pixel-pick regression starts with no selected body")
	var normalized: Vector2=layout.project_normalized(world.get_node("Robot").state().bodies.ball.transform.origin)
	var point: Vector2=test.root.get_visible_rect().position+normalized*test.root.get_visible_rect().size
	await layout.click_pixel(point)
	check(await test.wait_for(func():return str(frame().selected_name).ends_with("_ball")),"actual overlay rendered-pixel double click selects the same visible body")
	# Move the still-visible body into the transparent margin outside custom UI's
	# declared reserved rectangle. Overlay input must cover the full 3D viewport.
	var uv_before: Vector2=layout.project_normalized(world.get_node("Robot").state().bodies.ball.transform.origin)
	await test.issue({"action":"move","mouse":4,"dx":.04,"dy":0.,"perturb":false})
	var uv_after: Vector2=layout.project_normalized(world.get_node("Robot").state().bodies.ball.transform.origin)
	var delta_x: float=uv_after.x-uv_before.x
	check(absf(delta_x)>.00001,"official horizontal pan changes the actual overlay projection")
	if absf(delta_x)>.00001:
		await test.issue({"action":"move","mouse":4,"dx":.04*(.05-uv_after.x)/delta_x,"dy":0.,"perturb":false})
		normalized=layout.project_normalized(world.get_node("Robot").state().bodies.ball.transform.origin)
		point=test.root.get_visible_rect().position+normalized*test.root.get_visible_rect().size
		check(Rect2(Vector2.ZERO,Vector2.ONE).has_point(normalized) and not viewer.ui.render_region.get_global_rect().has_point(point),"actual overlay target is visible outside the custom reserved input rectangle")
		await test.issue({"action":"select","button":1,"x":.98,"y":.02,"aspect":test.render_aspect()})
		check(frame().selected_body==0,"clear selection before the transparent overlay margin click")
		await layout.click_pixel(point)
		check(await test.wait_for(func():return str(frame().selected_name).ends_with("_ball")),"unconsumed transparent-margin mouse input selects the actual full-overlay pixels")
	await test.issue({"action":"align"})
	viewer.layout_mode=Viewer.LayoutMode.RESERVED
	extras.enabled=false
	for unused in 3:await test.process_frame
	extras.preferences_id=viewer.preferences_id;extras.restore_preferences=false;extras.enabled=true
	check(await test.wait_for(func():return extras.status=="ACTIVE"),"Extras with same authored preference ID binds independently of original viewer")
	await preferences_checks(resource)
	viewer.show_native_panels(true,true);viewer.show_info(false);extras.show_performance(true)
	viewer.ui.feedback=""
	for section_title in viewer.ui.sections:
		viewer.ui.sections[section_title].button.button_pressed=section_title in ["Option","Rendering","Joint","Control","Equality"]
	viewer.ui.left_panel.scroll_vertical=0;viewer.ui.right_panel.scroll_vertical=0
	await test.issue({"action":"camera","id":2})
	check(await test.wait_for(active),"authored custom panels present their saved fixed camera for documentation")
	await test.create_timer(.25).timeout
	await capture("component-custom-panels")
	observations.append({"native_requested":test.native,"actual_native_active":world.native_view_active,"render_rect":str(viewer._session.render_rect_in_source()),"frame_slots":frame().stats.get("viewer_scene_slots",-1)})
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("component-contract-evidence.json"),FileAccess.WRITE).store_string(JSON.stringify(observations,"  "))
	await partial_module_checks()
	world.stop_native_view();test.game_root.queue_free()
	for unused in 5:await test.process_frame

func partial_module_checks() -> void:
	var original_scene: PackedScene=viewer.ui_scene
	var restore_preferences: bool=viewer.restore_preferences
	var cases := [
		{"name":"without-analysis","omitted":["profiler","sensors"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"without-help-info","omitted":["help","info"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"without-overlays","omitted":["help","info","profiler","sensors"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"partial-figures-numeric","omitted":[],"indices":[2],"numeric":true,"images":false},
		{"name":"partial-figures-images","omitted":[],"indices":[2],"numeric":false,"images":true},
		{"name":"without-file-option-watch","omitted":[],"sections":["File","Option","Watch"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"simulation-only","omitted":[],"sections":["File","Option","Watch","Physics","Rendering","Visualization","Group enable","Logging","Joint","Control","Equality"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"without-simulation","omitted":[],"sections":["Simulation"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"rendering-analysis-only","omitted":[],"sections":["File","Option","Simulation","Watch","Physics","Visualization","Group enable","Logging","Joint","Control","Equality"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"without-left-panel","omitted":[],"panels":["left_panel"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"without-right-panel","omitted":[],"panels":["right_panel"],"indices":[0,1,2,3],"numeric":true,"images":true},
		{"name":"overlays-only","omitted":[],"panels":["left_panel","right_panel"],"indices":[0,1,2,3],"numeric":true,"images":true},
	]
	for variant in cases:
		var removed_sections: Array=variant.get("sections",[]).duplicate()
		if "left_panel" in variant.get("panels",[]):removed_sections.append_array(["File","Option","Simulation","Watch","Physics","Rendering","Visualization","Group enable","Logging"])
		if "right_panel" in variant.get("panels",[]):removed_sections.append_array(["Joint","Control","Equality"])
		var omitted_panels := PackedStringArray()
		for key in variant.get("panels",[]):omitted_panels.append('"'+str(key)+'"')
		var omitted := PackedStringArray()
		for key in variant.omitted:omitted.append('"'+str(key)+'"')
		var omitted_sections := PackedStringArray()
		for key in removed_sections:omitted_sections.append('"'+str(key)+'"')
		var section_count: int=12-omitted_sections.size()
		var indices := PackedStringArray()
		for index in variant.indices:indices.append(str(index))
		var path: String="res://partial-"+variant.name+".tscn"
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string('[gd_scene format=3]\n[ext_resource type="PackedScene" path="res://addons/godot_mujoco/viewer/default_ui.tscn" id="1"]\n[ext_resource type="Script" path="res://partial_modules_ui.gd" id="2"]\n[node name="ViewerUI" instance=ExtResource("1")]\nscript = ExtResource("2")\nomitted_modules = PackedStringArray('+", ".join(omitted)+')\nomitted_sections = PackedStringArray('+", ".join(omitted_sections)+')\nomitted_panels = PackedStringArray('+", ".join(omitted_panels)+')\nprofiler_indices = PackedInt32Array('+", ".join(indices)+')\nomit_numeric_sensor = '+str(not variant.numeric).to_lower()+'\nomit_sensor_images = '+str(not variant.images).to_lower()+'\n')
		file.close()
		var scene: PackedScene=load(path)
		check(scene!=null,"partial modules: saved inherited scene loads "+variant.name)
		if not scene:continue
		# Exercise the pure preview path too: no session/controller is supplied.
		var preview: Control=scene.instantiate()
		preview.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);preview.size=Vector2(1100,760)
		test.game_root.add_child(preview);preview.hide()
		var time: float=world.info().time
		preview.configure(null,null,true)
		check(preview.validate_scene().is_empty() and preview.use_default_presenters and preview.sections.size()==section_count and world.info().time==time,"partial modules: sample preview retains default presenters without touching simulation "+variant.name)
		preview.queue_free();await test.process_frame
		viewer.enabled=false;viewer.ui_scene=scene;viewer.restore_preferences=false;viewer.enabled=true
		check(await test.wait_for(active,30),"partial modules: actual authoritative frame binds "+variant.name)
		await test.create_timer(.25).timeout
		check(viewer.ui.use_default_presenters and viewer.ui.sections.size()==section_count,"partial modules: original sidebars and default presenters survive "+variant.name)
		for section in removed_sections:
			check(not viewer.ui.sections.has(section) and not viewer.ui.get_native_ui_catalog().any(func(item):return item.section==section),"partial modules: removed section is not rebuilt "+section+" "+variant.name)
		for role in variant.get("panels",[]):check(not is_instance_valid(viewer.ui.get(role)),"partial modules: removed whole sidebar stays absent "+role+" "+variant.name)
		if viewer.ui.sections.has("Simulation"):
			viewer.ui.fields.run.item_selected.emit(1)
			check(await test.wait_for(func():return not world.info().paused),"partial modules: retained Run widget starts actual simulation "+variant.name)
			viewer.ui.fields.run.item_selected.emit(0)
			check(await test.wait_for(func():return world.info().paused),"partial modules: retained Pause widget stops actual simulation "+variant.name)
		else:check(not viewer.ui.fields.has("run") and not viewer.ui.fields.has("key"),"partial modules: deleted Simulation fields remain absent "+variant.name)
		if viewer.ui.sections.has("Rendering"):
			check(viewer.ui.fields.has("camera_choice") and viewer.ui.fields.camera_choice.item_count==viewer.ui.catalog.cameras.size(),"partial modules: retained Rendering catalogue populates independently of Simulation "+variant.name)
			viewer.ui.fields.camera_choice.item_selected.emit(2)
			check(await test.wait_for(func():return frame().camera.type==2 and frame().camera.fixed_id==0),"partial modules: retained Camera widget changes actual shared camera "+variant.name)
			await test.issue({"action":"camera","id":0})
		for key in ["help","info","profiler","sensors"]:
			if key in variant.omitted:
				check(not viewer.ui.provides_action(key) and viewer.execute(key)==0 and viewer.last_error.contains("presentation module") and viewer.ui.fields["option:"+key].disabled,"partial modules: absent "+key+" reports unavailable and disables its checkbox "+variant.name)
			else:
				check(viewer.execute(key,{"value":true})>0 and viewer.ui.windows[key].visible,"partial modules: retained "+key+" opens independently "+variant.name)
		if variant.name=="without-analysis":
			check(is_equal_approx(viewer.ui.windows.help.size.x,viewer.ui.render_rect.size.x-16),"partial modules: missing figures reserve no phantom width from Help")
		if "profiler" in variant.omitted or "sensors" in variant.omitted:
			var requested: Dictionary=viewer.ui.inspection_request()
			check((not requested.profiler if "profiler" in variant.omitted else true) and (not requested.sensors if "sensors" in variant.omitted else true),"partial modules: omitted analysis producers are not requested "+variant.name)
		viewer.ui.feedback="Partial module feedback"
		await test.issue({"action":"control","id":0,"value":.18})
		check(absf(world.get_node("Robot").state().controls.drive-.18)<1e-8,"partial modules: retained controls mutate actual physics "+variant.name)
		for unused in 2:await test.process_frame
		await test.issue({"action":"step","count":2})
		if not "profiler" in variant.omitted:
			check(await test.wait_for(func():return viewer.ui.last_profiler_time>=0),"partial modules: remaining plots consume real integration diagnostics "+variant.name)
			if variant.indices.size()==1:
				check(viewer.ui.profiler_plots.size()==3 and viewer.ui.profiler_plots[0]==null and viewer.ui.profiler_plots[1]==null and is_instance_valid(viewer.ui.profiler_plots[2]),"partial modules: missing plots stay absent with their official indices "+variant.name)
		if not "sensors" in variant.omitted:
			if variant.numeric:
				check(await test.wait_for(func():return is_instance_valid(viewer.ui.sensor_plot) and not viewer.ui.sensor_plot.series.is_empty() and not viewer.ui.sensor_plot.series[0].is_empty()),"partial modules: numeric Sensors consumes real model data "+variant.name)
			else:
				check(not is_instance_valid(viewer.ui.sensor_plot) and await test.wait_for(func():return viewer.ui.fields.has("sensor_note") and viewer.ui.fields.sensor_note.text.contains("无图像传感器数据")),"partial modules: image-only Sensors reports absent production data without numeric plot")
			check(viewer.ui.provides_action("image_sensor")==variant.images,"partial modules: image selector capability follows the authored image slot "+variant.name)
			if not variant.images:check(viewer.execute("image_sensor",{"id":-1})==0,"partial modules: absent image slot explicitly rejects image selection")
			else:check(viewer.execute("image_sensor",{"id":-1})>0,"partial modules: retained image slot supports its action without requiring a numeric plot "+variant.name)
		for key in ["help","info","profiler","sensors"]:
			if not key in variant.omitted:viewer.execute(key,{"value":false})
	viewer.enabled=false;viewer.ui_scene=original_scene;viewer.restore_preferences=restore_preferences;viewer.enabled=true
	check(await test.wait_for(active,30),"partial modules: original authored scene rebinds after all optional variants")
