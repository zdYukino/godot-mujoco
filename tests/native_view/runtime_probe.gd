extends Node
@export var run_id := ""
@export var output := ""
var finishing := false
var captured := false
var sequence := 0
var ready_at := -1
func _process(_delta: float) -> void:
	if finishing: return
	var world: Node = get_parent()
	var command_path := output.path_join("command.json")
	if FileAccess.file_exists(command_path):
		var command = JSON.parse_string(FileAccess.get_file_as_string(command_path))
		DirAccess.remove_absolute(command_path)
		if command is Dictionary and command.get("run_id")==run_id:
			if command.op=="quit":
				finishing=true;set_process(false)
				var tree := get_tree()
				world.remove_child(self);tree.root.add_child(self)
				world.queue_free()
				for frame in 5: await tree.process_frame
				tree.quit();return
			if command.op=="step": world.step_simulation(5)
	var info: Dictionary = world.info()
	var view: Node = world.native_view
	var native: Dictionary = view.latest if is_instance_valid(view) else {}
	var controls: Node = world.runtime_viewer
	var ready: bool = world.author_started and world.command_request==0 and info.get("compile_status")=="ready" and not info.get("design_pending",true)
	if ready and ready_at<0: ready_at=Time.get_ticks_msec()
	sequence+=1
	var state := {"run_id":run_id,"sequence":sequence,"pid":OS.get_process_id(),"ready":ready,"time":info.get("time",0),"native":world.native_view_active,"status":world.rendering_status(),"error":world.native_view_error,"world_visible":world.visible,"disable_3d":get_viewport().disable_3d,"picking":get_viewport().physics_object_picking,"native_frame":native.get("frame",0),"native_geoms":native.get("ngeom",0),"native_time":native.get("time",-1),"native_step_calls":native.get("bridge_step_calls",-1),"gl_errors":native.get("gl_errors",-1),"texture":native.has("texture") and native.texture.is_valid(),"shared_controls":is_instance_valid(controls),"control_window_closed":not controls.controls.visible,"native_scene":native.get("authoritative_scene",false),"ui_status":controls.status.text}
	state["left_panel"]=controls.left_panel.visible
	state["right_panel"]=controls.right_panel.visible
	state["native_info"]=controls.info_enabled
	state["native_groups"]=controls.sections.keys()
	state["render_rect"]=str(controls.render_rect)
	state["extras_groups"]=controls.extras_sections.keys()
	if ready and not captured and Time.get_ticks_msec()-ready_at>=600 and int(controls.frame.get("frame_id",0))>=5 and (world.native_view_active and int(native.get("frame",0))>=5 or not world.native_view_experimental):
		captured=true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		state["screenshot_error"]=image.save_png(output.path_join(run_id+".png"))
	var file := FileAccess.open(output.path_join("state.tmp"),FileAccess.WRITE)
	file.store_string(JSON.stringify(state));file.close()
	DirAccess.rename_absolute(output.path_join("state.tmp"),output.path_join("state.json"))
