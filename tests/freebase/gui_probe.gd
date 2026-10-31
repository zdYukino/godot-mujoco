extends SceneTree
## Test observation/reveal only. All simulation actions come from actual widget input.
var scene: Node
var host: Node
var viewer: Node
var extras: Node
var folder := ""
var contact_seen := false
var barrier_seen := false
var deepest := 0.0
var serial := 0
var menu: HBoxContainer
var old_world := 0
var start_x := 0.0
var start_pelvis_x := 0.0
var sole_friction_min := INF
var sole_friction_max := -INF
var trajectory := []
var sampled_time := -1.0
var native_requested := false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-dir="): folder=arg.trim_prefix("--probe-dir=")
	native_requested="--native" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("rendering/mujoco_native_view/renderer",1 if native_requested else 0)
	if native_requested:ProjectSettings.set_setting("rendering/mujoco_native_view/max_model_mib",192)
	scene=load("res://FreebasePlayground.tscn").instantiate();root.add_child(scene)
	host=scene.get_node("EnvironmentHost");viewer=scene.get_node("RuntimeViewer");extras=scene.get_node("GodotExtras")
	var overlay := CanvasLayer.new();overlay.layer=200;scene.add_child(overlay)
	menu=HBoxContainer.new();menu.position=Vector2(10,10);overlay.add_child(menu)
	for mode in ["low","high","barrier","invalid","original"]:
		var button := Button.new();button.text="Fixture "+mode;menu.add_child(button)
		button.pressed.connect(func():
			if mode=="invalid":
				var bad:=Node.new();var packed:=PackedScene.new();packed.pack(bad);bad.free();host.environment_scene=packed
			else: host.environment_scene=load("res://FreebaseEnvironment.tscn" if mode=="original" else "res://Contact_"+mode+".tscn"))
	process_frame.connect(tick)
func rect(control: Control) -> Array:
	var point := control.get_screen_transform().origin+Vector2(DisplayServer.window_get_position(root.get_window_id()))
	return [point.x,point.y,control.size.x,control.size.y]
func action_controls() -> Dictionary:
	var values := {}
	if not is_instance_valid(viewer.ui) or not is_instance_valid(extras.ui): return values
	for id in ["step","capture_snapshot","restore_snapshot","reload"]:
		var presenter: Control=viewer.ui if id=="reload" else extras.ui
		var control: Control=presenter.fields.step_button if id=="step" else presenter.get_action_control(id)
		if is_instance_valid(control): values[id]={"rect":rect(control),"extras":extras.ui.controls.is_ancestor_of(control),"visible":control.is_visible_in_tree()}
	for button in viewer.ui.fields.run.get_children():
		if button is Button: values["pause" if button.text=="Pause" else "resume"]={"rect":rect(button),"extras":false,"visible":button.is_visible_in_tree()}
	return values
func center_of_mass(state: Dictionary) -> Vector3:
	var total := 0.;var weighted := Vector3.ZERO
	for body in state.bodies.values():total+=body.mass;weighted+=body.center_of_mass*body.mass
	return weighted/total
func tick() -> void:
	var capture_path := folder.path_join("capture.json")
	if FileAccess.file_exists(capture_path):
		var capture_name: String=str(JSON.parse_string(FileAccess.get_file_as_string(capture_path)).name)
		DirAccess.remove_absolute(capture_path)
		_capture_frame(capture_name)
	menu.position=Vector2(maxf(10,(root.size.x-menu.size.x)*.5),10)
	if FileAccess.file_exists(folder.path_join("quit")):
		process_frame.disconnect(tick);scene.queue_free();await process_frame;print("FREEBASE_GUI_PROBE_FINISHED");quit(0);return
	if not is_instance_valid(host.world) or not host.world.ready_for_models or not is_instance_valid(viewer.ui) or not is_instance_valid(extras.ui): return
	var world: Node=host.world;var robot: Node=world.get_node("Model");var state: Dictionary=robot.state();var info: Dictionary=world.info()
	if not state.has("joints"): return
	var q=state.joints.floating_base.qpos
	if world.get_instance_id()!=old_world:
		old_world=world.get_instance_id();start_x=center_of_mass(state).x;start_pelvis_x=q[0];contact_seen=false;barrier_seen=false;deepest=0.;sole_friction_min=INF;sole_friction_max=-INF;trajectory=[];sampled_time=-1.
	for index in info.contact_details.size():
		var contact: Dictionary=info.contact_details[index]
		deepest=minf(deepest,contact.distance)
		var pair: Array=info.contacts[index]
		if world.has_node("Ground") and pair.has(world.get_node("Ground").get_rid()) and pair.has(robot.model_rid):
			for body in contact.bodies:
				if body.contains("ankle_roll"):
					contact_seen=true;sole_friction_min=minf(sole_friction_min,contact.friction);sole_friction_max=maxf(sole_friction_max,contact.friction)
	if info.time!=sampled_time:
		sampled_time=info.time
		var center := center_of_mass(state)
		trajectory.append({"time":info.time,"center_of_mass":[center.x,center.y,center.z],"pelvis_x":q[0]})
		if trajectory.size()>1024:trajectory.pop_front()
	if world.has_node("Barrier"):
		for pair in info.contacts:
			if pair.has(world.get_node("Barrier").get_rid()) and pair.has(robot.model_rid): barrier_seen=true
	var request_path := folder.path_join("reveal.json")
	if FileAccess.file_exists(request_path):
		var request=JSON.parse_string(FileAccess.get_file_as_string(request_path));DirAccess.remove_absolute(request_path)
		var presenter: Control=viewer.ui if request.action in ["reload","resume","pause"] else extras.ui
		var control: Control=presenter.fields.step_count if request.action=="count" else presenter.fields.step_button if request.action=="step" else presenter.fields.run if request.action in ["resume","pause"] else presenter.get_action_control(request.action)
		if is_instance_valid(control):
			var parent: Node=control.get_parent()
			while parent:
				if parent is ScrollContainer: parent.ensure_control_visible(control)
				parent=parent.get_parent()
	var buttons := []
	for button in menu.get_children(): buttons.append({"text":button.text,"rect":rect(button)})
	var finite := true
	for joint in state.joints.values():
		for value in joint.qpos: finite=finite and is_finite(value)
		for value in joint.qvel: finite=finite and is_finite(value)
	var result={"pid":OS.get_process_id(),"ready":viewer.read_state().get("presentation",{}).get("ready",false),"native_requested":native_requested,"native_active":world.native_view_active,"native_error":world.native_view_error,"native_gl_errors":world.native_view.latest.get("gl_errors",-1) if is_instance_valid(world.native_view) else -1,"seq":serial,"time":info.time,"paused":info.paused,"game_elapsed":Time.get_ticks_msec()/1000.,"world_id":old_world,"qpos":q,"travel":center_of_mass(state).x-start_x,"pelvis_travel":q[0]-start_pelvis_x,"sole_friction_min":sole_friction_min if is_finite(sole_friction_min) else null,"sole_friction_max":sole_friction_max if is_finite(sole_friction_max) else null,"trajectory":trajectory,"contact_seen":contact_seen,"barrier_seen":barrier_seen,"deepest":deepest,"finite":finite,"warnings":info.warning_count,"status":viewer.ui.feedback+"\n"+extras.ui.feedback,"host_error":host.last_error,"fixture_path":host.environment_scene.resource_path if host.environment_scene else "","controls":buttons,"actions":action_controls(),"extras":extras.ui.controls.visible,"count":rect(extras.ui.fields.step_count.get_line_edit()),"count_value":extras.ui.fields.step_count.value,"count_text":extras.ui.fields.step_count.get_line_edit().text,"count_has_focus":extras.ui.fields.step_count.get_line_edit().has_focus(),"extras_window_position":str(extras.ui.controls.position),"extras_window_size":str(extras.ui.controls.size),"root_window_size":str(root.size),"extras_focus":str(extras.ui.controls.gui_get_focus_owner())}
	serial+=1
	var file:=FileAccess.open(folder.path_join("state.tmp"),FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close();DirAccess.rename_absolute(folder.path_join("state.tmp"),folder.path_join("state.json"))

func _capture_frame(name_: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name_+".png"))
