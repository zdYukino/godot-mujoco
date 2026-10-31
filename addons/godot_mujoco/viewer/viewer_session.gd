class_name MjViewerSession
extends Node
## World-owned presentation and command lifetime. No menus or input handlers.
signal result_finished(request_id: int, result: Dictionary)
signal frame_changed(packet: Dictionary)
signal model_changing
signal target_replaced(world: Node3D, host: Node)
signal reload_finished(success: bool, error: String)
var runtime_world: Node3D
var source_viewport: Viewport
var camera: Camera3D
var frame: Dictionary={}
var catalog: Dictionary={}
var details: Dictionary={}
var inspection_options := {"inspect":false,"sensors":false,"profiler":false,"watch_field":"qpos","watch_index":0}
var known_revision := -1
var seeded_revision := -1
var presented_revision := -1
var presented_frame_id := 0
var presented_layout := -1
var layout_generation := 0
var applied_layout := -1
var frames_retiring := false
var frame_retire_request := 0
var attached := false
var last_error := ""
var last_result: Dictionary={}
var last_backend := ""
var renderer_fps := 0.0
var host_fps := 0.0
var fps_count := 0
var last_native_frame := -1
var pending: Dictionary={}
var consumer: Node
var extras_client: Node
var camera_control := false
var _sequence := 0
var _region := Rect2()
var _retire_target: Dictionary={}
var _results: Dictionary={}
var _result_order: Array[int]=[]
var _request_origins: Dictionary={}
var _next_inspect := 0
var _analysis_stop_pending := false
var _fps_at := 0
var _camera_flags: Dictionary={}
var _camera_sync_request := 0
var _camera_sync_revision := -1
var _latest_camera_payload: Dictionary={}
var _last_camera_payload: Dictionary={}
var _failed_camera_payload: Dictionary={}
var camera_sync_error := ""
var _initial_camera_required := true
var _camera_to_restore: Dictionary={}
var _mode_to_restore: Dictionary={}
var _last_view_state: Dictionary={}
var _geometry_targets: Dictionary={}
var _geometry_visibility: Dictionary={}
var _diagnostics: Node3D
var _godot_viewport: SubViewport
var _godot_camera: Camera3D
var _godot_layer: CanvasLayer
var _godot_texture: TextureRect
var _saved_disable_3d := false
var _owns_godot_disable := false
var _closed := false
var _rebuilding := false
var _reload_source_path := ""
var _reload_world_path := NodePath(".")
var _reload_host: Node

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	process_priority=-50
	name="MuJoCoPresentationSession"
	source_viewport=runtime_world.get_viewport()
	camera=source_viewport.get_camera_3d()
	_region=Rect2(Vector2.ZERO,source_viewport.get_visible_rect().size)
	attached=true
	_fps_at=Time.get_ticks_msec()
	_discover_reload_source()
	RenderingServer.frame_post_draw.connect(after_draw)

func _discover_reload_source() -> void:
	# Child _ready runs before SceneTree.current_scene is assigned during F5.
	# Saved ancestry is available already and also covers explicitly instanced scenes.
	_reload_source_path=str(runtime_world.get_meta("mj_saved_scene",""))
	if not _reload_source_path.is_empty():
		_reload_world_path=NodePath(runtime_world.get_meta("mj_saved_world_path","."))
		return
	var source: Node=runtime_world
	while is_instance_valid(source):
		if not source.scene_file_path.is_empty():
			_reload_source_path=source.scene_file_path
			_reload_world_path=source.get_path_to(runtime_world)
			return
		source=source.get_parent()

func attach_consumer(value: Node) -> String:
	if _closed or not attached: return "Presentation session is unavailable"
	if not is_instance_valid(value): return "Viewer component is unavailable"
	if is_instance_valid(consumer) and consumer!=value: return "This target viewport already has an interactive viewer"
	if source_viewport.has_meta("mj_viewer_consumer"):
		var existing: Object=source_viewport.get_meta("mj_viewer_consumer").get_ref()
		if is_instance_valid(existing) and existing!=value: return "This target viewport already has an interactive viewer"
	consumer=value
	source_viewport.set_meta("mj_viewer_consumer",weakref(value))
	_initial_camera_required=true
	_last_camera_payload={}
	_next_inspect=0
	return ""

func detach_consumer(value: Node) -> void:
	if consumer!=value: return
	set_camera_control(false)
	if is_instance_valid(source_viewport) and source_viewport.has_meta("mj_viewer_consumer"):
		if source_viewport.get_meta("mj_viewer_consumer").get_ref()==value: source_viewport.remove_meta("mj_viewer_consumer")
	consumer=null
	_analysis_stop_pending=true
	inspection_options={"inspect":false,"sensors":false,"profiler":false,"watch_field":"qpos","watch_index":0}
	_stop_optional_analysis()
	cancel_gesture(true)
	_restore_geometry_visibility()
	if is_instance_valid(_diagnostics): _diagnostics.hide()
	set_region(Rect2(Vector2.ZERO,source_viewport.get_visible_rect().size))
	suspend_godot_presentation()

# Non-camera role: never changes render layout, optional native diagnostics or camera.
func attach_extras(value: Node) -> String:
	if _closed or not attached:return "Presentation session is unavailable"
	if not is_instance_valid(value):return "Extras component is unavailable"
	if is_instance_valid(extras_client) and extras_client!=value:return "This target viewport already has Godot Extras"
	if source_viewport.has_meta("mj_extras_consumer"):
		var existing: Object=source_viewport.get_meta("mj_extras_consumer").get_ref()
		if is_instance_valid(existing) and existing!=value:return "This target viewport already has Godot Extras"
	extras_client=value
	source_viewport.set_meta("mj_extras_consumer",weakref(value))
	return ""

func detach_extras(value: Node) -> void:
	if extras_client!=value:return
	if is_instance_valid(source_viewport) and source_viewport.has_meta("mj_extras_consumer"):
		if source_viewport.get_meta("mj_extras_consumer").get_ref()==value:source_viewport.remove_meta("mj_extras_consumer")
	extras_client=null

func occupied_overlay_rects() -> Array[Rect2]:
	# Value-only source-viewport coordinates. Extras may avoid the original
	# figures, but never receives ownership of their controls or render region.
	var occupied: Array[Rect2]=[]
	if not is_instance_valid(consumer) or not is_instance_valid(consumer.ui):return occupied
	var target: Rect2=consumer._target_rect
	if target.size.x<=0 or target.size.y<=0:return occupied
	var scale := source_viewport.get_visible_rect().size/target.size
	for key in ["info","profiler","sensors"]:
		var overlay: Control=consumer.ui.windows.get(key)
		if not is_instance_valid(overlay) or not overlay.is_visible_in_tree():continue
		var rect := overlay.get_global_rect()
		occupied.append(Rect2((rect.position-target.position)*scale,rect.size*scale))
	for label in [consumer.ui.run_label,consumer.ui.speed_label]:
		if not is_instance_valid(label) or not label.is_visible_in_tree() or label.text.is_empty():continue
		var rect: Rect2=label.get_global_rect()
		occupied.append(Rect2((rect.position-target.position)*scale,rect.size*scale))
	return occupied

func extras_has_focus() -> bool:
	return is_instance_valid(extras_client) and extras_client.has_ui_focus()

func send_state(command: Dictionary) -> int:
	if _closed or not attached or not is_instance_valid(runtime_world):return 0
	if str(command.get("action","")) not in ["step","capture_snapshot","restore_snapshot"]:return 0
	var state: Dictionary=runtime_world.info()
	if state.get("design_pending",true) or int(state.get("revision",-1))<0:return 0
	# State mutations require the committed model, not a pretend displayed frame.
	return _enqueue(command,int(state.revision),0)

func client_state() -> Dictionary:
	if not is_instance_valid(runtime_world):return {}
	var state: Dictionary=runtime_world.info()
	state.space=int(runtime_world.space.get_id())
	state.frame_id=0
	state.stats={}
	if (is_instance_valid(consumer) or runtime_world.native_view_active) and not frame.is_empty() and frame.get("revision",-1)==state.get("revision",-2):
		state.stats=frame.get("stats",{}).duplicate(true)
	return state

func set_camera_control(value: bool) -> void:
	value=value and is_instance_valid(consumer)
	if value==camera_control: return
	camera_control=value
	if value:
		_discover_camera()
		if is_instance_valid(camera):
			_take_camera_flags(camera)
		_initial_camera_required=true
	else:
		# Native rendering does not write the source Camera3D each frame. Hand
		# its visible view back before gameplay processing/input resumes.
		if is_instance_valid(camera) and not _last_view_state.is_empty():
			_apply_camera(camera,_last_view_state)
		_restore_camera_flags()
		_last_camera_payload={}
		_initial_camera_required=true

func _take_camera_flags(value: Camera3D) -> void:
	_camera_flags={"camera":weakref(value),"process":value.is_processing(),"physics":value.is_physics_processing(),"input":value.is_processing_input(),"unhandled":value.is_processing_unhandled_input(),"unhandled_key":value.is_processing_unhandled_key_input()}
	value.set_process(false)
	value.set_physics_process(false)
	value.set_process_input(false)
	value.set_process_unhandled_input(false)
	value.set_process_unhandled_key_input(false)

func _restore_camera_flags() -> void:
	if _camera_flags.is_empty(): return
	var previous: Object=_camera_flags.camera.get_ref()
	if is_instance_valid(previous):
		previous.set_process(_camera_flags.process)
		previous.set_physics_process(_camera_flags.physics)
		previous.set_process_input(_camera_flags.input)
		previous.set_process_unhandled_input(_camera_flags.unhandled)
		previous.set_process_unhandled_key_input(_camera_flags.unhandled_key)
	_camera_flags.clear()

func set_region(value: Rect2) -> String:
	if not is_instance_valid(source_viewport): return "Source viewport is unavailable"
	var full := Rect2(Vector2.ZERO,source_viewport.get_visible_rect().size)
	if not value.position.is_finite() or not value.size.is_finite() or value.size.x<=0 or value.size.y<=0: return "Render region must be a positive finite rectangle"
	if not full.encloses(value): return "Render region is outside its target viewport"
	# Framebuffer pixels and mouse mapping use one quantized rectangle.
	var region := Rect2(Vector2(floor(value.position.x),floor(value.position.y)),Vector2(maxf(1,ceil(value.size.x)),maxf(1,ceil(value.size.y)))).intersection(full)
	if region==_region: return ""
	cancel_gesture(true)
	_region=region
	layout_generation+=1
	presented_layout=-1
	presented_frame_id=0
	if is_instance_valid(_godot_texture):
		_godot_texture.position=region.position
		_godot_texture.size=region.size
	if is_instance_valid(_godot_viewport): _godot_viewport.size=Vector2i(region.size)
	return ""

func render_rect_in_source() -> Rect2:
	return _region

func update_viewport_rect() -> void:
	if not is_instance_valid(source_viewport): return
	if not is_instance_valid(consumer):
		var full := Rect2(Vector2.ZERO,source_viewport.get_visible_rect().size)
		if full!=_region: set_region(full)

func frame_options(backend := "godot") -> Dictionary:
	var options: Dictionary=inspection_options.duplicate()
	options.backend=backend
	var now := Time.get_ticks_msec()
	var inspect_requested: bool=bool(options.get("inspect",false)) or bool(options.get("profiler",false)) or bool(options.get("sensors",false))
	options.inspect=is_instance_valid(consumer) and inspect_requested and now>=_next_inspect
	if not is_instance_valid(consumer): options.sensors=false;options.profiler=false
	return options

func send(command: Dictionary) -> int:
	if _closed or not attached or not is_instance_valid(runtime_world) or frame.is_empty(): return 0
	var revision: int=frame.revision
	var frame_id: int=frame.frame_id
	if str(command.get("action","")) in ["select","move","perturb_begin"]:
		if frames_retiring or presented_frame_id==0 or presented_revision!=revision or presented_layout!=layout_generation: return 0
		frame_id=presented_frame_id
	return _enqueue(command,revision,frame_id)

func _enqueue(command: Dictionary,revision: int,frame_id: int) -> int:
	_sequence+=1
	var id: int=PhysicsServer3D.call("scene_viewer_request",runtime_world.space,revision,frame_id,_sequence,command)
	if id>0:
		pending[id]=str(command.get("action",""))
		_request_origins[id]={"space":int(runtime_world.space.get_id()),"revision":revision,"frame_id":frame_id,"sequence":_sequence,"command":str(command.get("action",""))}
	else: last_error="Presentation command queue is full or unavailable"
	return id

func action_result(id: int) -> Dictionary:
	return _results.get(id,{}).duplicate(true)

func cancel_requests(ids: Array, reason := "Component target changed or disabled") -> void:
	# Query and cancellation run on the physics main thread. A command cannot
	# cross its execution boundary between these two calls. Preserve a completed
	# command's real result rather than describing its applied effects as cancelled.
	for value in ids:
		var id: int=value
		var result: Dictionary=_results.get(id,{}).duplicate(true)
		if pending.has(id) and _request_origins.has(id):
			result=PhysicsServer3D.call("scene_viewer_result",id)
			if result.is_empty():
				PhysicsServer3D.call("scene_cancel_world_command",id)
				result=_request_origins[id].duplicate(true)
				result.merge({"request":id,"success":false,"error":reason,"cancelled":true},true)
			else:result.merge(_request_origins[id],false)
			pending.erase(id)
			_request_origins.erase(id)
			_remember_result(id,result)
		if not result.is_empty():result_finished.emit(id,result.duplicate(true))

func _remember_result(id: int, result: Dictionary) -> void:
	_results[id]=result.duplicate(true)
	_result_order.append(id)
	while _result_order.size()>128: _results.erase(_result_order.pop_front())

func _process(_delta: float) -> void:
	if _closed or not attached or not is_instance_valid(runtime_world): return
	if is_instance_valid(consumer) and consumer.is_queued_for_deletion(): detach_consumer(consumer)
	if is_instance_valid(extras_client) and extras_client.is_queued_for_deletion():detach_extras(extras_client)
	update_viewport_rect()
	_poll_results()
	_stop_optional_analysis()
	if frames_retiring and frame_retire_request==0: _submit_frame_retirement()
	var native_running: bool=is_instance_valid(runtime_world.native_view) and not runtime_world.native_view.stopped
	if not native_running and not is_instance_valid(consumer):
		suspend_godot_presentation()
		_update_fps()
		return
	prepare_frame()
	if not native_running and not frames_retiring and ready_for_capture():
		var packet: Dictionary=PhysicsServer3D.call("scene_viewer_frame",runtime_world.space,known_revision,frame_options())
		if packet.has("error"): last_error=str(packet.error)
		elif not packet.get("pending",false): accept_frame(packet)
	_update_fps()

func _update_fps() -> void:
	var now := Time.get_ticks_msec()
	if now-_fps_at>=500:
		renderer_fps=fps_count*1000.0/maxi(1,now-_fps_at)
		if not renderer_fps_status().available:renderer_fps=0.0
		host_fps=Engine.get_frames_per_second()
		fps_count=0
		_fps_at=now

func renderer_fps_status() -> Dictionary:
	if not is_instance_valid(runtime_world) or not is_instance_valid(source_viewport):return {"available":false,"reason":"Target viewport is unavailable"}
	if runtime_world.native_view_active or is_instance_valid(consumer):return {"available":true,"reason":""}
	if source_viewport is SubViewport and source_viewport.render_target_update_mode not in [SubViewport.UPDATE_ALWAYS,SubViewport.UPDATE_DISABLED]:
		return {"available":false,"reason":"Conditional SubViewport updates have no per-target frame counter; showing Godot host FPS"}
	return {"available":true,"reason":""}

func _direct_godot_draw_observed() -> bool:
	if not is_instance_valid(source_viewport):return false
	if source_viewport is Window:return source_viewport.visible
	return source_viewport is SubViewport and source_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS

func _stop_optional_analysis() -> void:
	if not _analysis_stop_pending or not attached or not is_instance_valid(runtime_world): return
	# Frame options update the solver-series gate before scene-slot admission.
	# Retry outside a physics callback if detach happened while it was flushing.
	var backend := "native" if is_instance_valid(runtime_world.native_view) and not runtime_world.native_view.stopped else "godot"
	var packet: Dictionary=PhysicsServer3D.call("scene_viewer_frame",runtime_world.space,known_revision,{"backend":backend,"profiler":false})
	if packet.get("error","")=="Viewer requires main-thread physics outside callbacks": return
	_analysis_stop_pending=false
	# A blocked/absent model cannot integrate; a successful model commit starts
	# with a fresh viewer state. Do not poll an inactive failed compile forever.
	if packet.has("error") or packet.get("pending",false) and not packet.has("status"): return
	begin_frame_retirement()

func _poll_results() -> void:
	for id in pending.keys():
		var result: Dictionary=PhysicsServer3D.call("scene_viewer_result",id)
		if result.is_empty(): continue
		# Deferred step/reset completions come from the World command path.
		# Fill their missing submission identity before retiring our ownership.
		if _request_origins.has(id):result.merge(_request_origins[id],false)
		pending.erase(id)
		_request_origins.erase(id)
		if id==frame_retire_request:
			frame_retire_request=0
			frames_retiring=false
			_retire_target.clear()
		if id==_camera_sync_request:
			_camera_sync_request=0
			if result.get("success",false):
				seeded_revision=_camera_sync_revision
				_initial_camera_required=false
				camera_sync_error=""
				_failed_camera_payload={}
			else:
				var why: String=str(result.get("error",""))
				if why.begins_with("Invalid source camera") or why.begins_with("Invalid authored") or why.begins_with("Source camera") or why=="No committed viewer model":
					camera_sync_error=why
					_failed_camera_payload=_last_camera_payload.duplicate(true)
				_last_camera_payload={}
		last_result=result
		if not result.get("success",false): last_error=str(result.get("error","Presentation command failed"))
		_remember_result(id,result)
		result_finished.emit(id,result)

func _discover_camera() -> void:
	if not is_instance_valid(source_viewport): return
	var current: Camera3D=source_viewport.get_camera_3d()
	if is_instance_valid(current) and current!=camera:
		if camera_control: _restore_camera_flags()
		camera=current
		_last_camera_payload={}
		_initial_camera_required=true
		if camera_control:
			_take_camera_flags(camera)

func capture_camera_seed() -> Dictionary:
	if not is_instance_valid(camera): return {}
	var orthographic := camera.projection==Camera3D.PROJECTION_ORTHOGONAL
	var viewport_size := _region.size
	var aspect := maxf(viewport_size.x,1)/maxf(viewport_size.y,1)
	var fov := camera.fov
	var extent := camera.size
	if camera.keep_aspect==Camera3D.KEEP_WIDTH:
		fov=rad_to_deg(2*atan(tan(deg_to_rad(fov)/2)/aspect));extent/=aspect
	var command := {"action":"sync_external_camera","transform":camera.get_camera_transform(),"orthographic":orthographic,"fovy":extent if orthographic else fov,"near":camera.near,"far":camera.far}
	if camera.projection==Camera3D.PROJECTION_FRUSTUM: command.frustum_size=extent;command.offset=camera.frustum_offset
	return command

func seed_from_state(state: Dictionary) -> Dictionary:
	var command := {"action":"sync_external_camera","transform":state.transform,"orthographic":state.orthographic,"fovy":state.size if state.orthographic else state.fov,"near":state.near,"far":state.far}
	if state.offset.length_squared()>.00000001: command.frustum_size=state.size;command.offset=state.offset
	return command

func prepare_frame() -> void:
	_discover_camera()
	var state: Dictionary=runtime_world.info()
	var revision: int=int(state.get("revision",-1))
	if not frame.is_empty() and revision>=0 and int(frame.revision)!=revision:
		_restore_geometry_visibility()
		model_changing.emit()
		if camera_control and frame.has("camera"):
			_camera_to_restore=frame.camera.duplicate(true)
			_mode_to_restore=_camera_to_restore.duplicate(true)
		frame={};catalog={};details={};known_revision=-1
		presented_revision=-1;presented_frame_id=0;presented_layout=-1
		_initial_camera_required=true;seeded_revision=-1;_last_camera_payload={}
	if (not camera_control or _initial_camera_required) and is_instance_valid(camera):
		var payload: Dictionary=seed_from_state(_camera_to_restore) if not _camera_to_restore.is_empty() else capture_camera_seed()
		if payload!=_last_camera_payload and (camera_sync_error.is_empty() or payload!=_failed_camera_payload): _latest_camera_payload=payload
	if _camera_sync_request==0 and not _latest_camera_payload.is_empty() and revision>=0 and not state.get("design_pending",true):
		# Camera synchronization does not require an earlier visualization frame.
		# Finish the initial command before freezing/submitting the first image.
		_sequence+=1
		_camera_sync_revision=revision
		_camera_sync_request=PhysicsServer3D.call("scene_viewer_request",runtime_world.space,revision,0,_sequence,_latest_camera_payload)
		if _camera_sync_request>0:
			pending[_camera_sync_request]="sync_external_camera"
			_last_camera_payload=_latest_camera_payload
			_latest_camera_payload={}
			_camera_to_restore={}

func retry_camera_sync() -> void:
	camera_sync_error=""
	_failed_camera_payload={}
	_last_camera_payload={}
	_initial_camera_required=true

func ready_for_capture() -> bool:
	return not _initial_camera_required or not is_instance_valid(camera)

func restore_view(state: Dictionary) -> void:
	if state.is_empty(): return
	_camera_to_restore=state.duplicate(true)
	_mode_to_restore=state.duplicate(true)
	_discover_camera()
	if is_instance_valid(camera): _apply_camera(camera,state)
	_initial_camera_required=true

func accept_frame(packet: Dictionary) -> void:
	if _closed or not packet.has("revision") or not packet.has("frame_id"): return
	var revision: int=packet.revision
	var changed: bool=not frame.is_empty() and int(frame.revision)!=revision
	if changed:
		_restore_geometry_visibility()
		model_changing.emit()
		if camera_control and frame.has("camera"): _camera_to_restore=frame.camera.duplicate(true)
		details={}
		_initial_camera_required=true
		_last_camera_payload={}
		seeded_revision=-1
	# Render transport assets stay with the adapter, not optional UI snapshots.
	var display_packet: Dictionary=packet.duplicate(true)
	display_packet.erase("model")
	display_packet.erase("objects")
	frame=display_packet
	if packet.has("camera"): _last_view_state=packet.camera.duplicate(true)
	known_revision=revision
	if packet.has("catalog"):
		catalog=frame.catalog
		cache_geometry()
		_restore_camera_mode()
	if packet.has("inspect"):
		details=frame.inspect
		_next_inspect=Time.get_ticks_msec()+200
	if seeded_revision!=revision: _initial_camera_required=true
	prepare_frame()
	# Initial/revision camera synchronization is a terminal invalidation, not
	# an ACK of a scene that has never actually been shown.
	if _initial_camera_required and _camera_sync_request>0: begin_frame_retirement()
	last_backend="native" if is_instance_valid(runtime_world.native_view) and not runtime_world.native_view.stopped else "godot"
	if last_backend=="godot" and not frames_retiring:
		if is_instance_valid(consumer):
			_ensure_godot_presentation()
			_sync_render_properties()
			if packet.has("camera"):
				_apply_camera(_godot_camera,packet.camera)
				if camera_control: _apply_camera(camera,packet.camera)
			applied_layout=layout_generation
			apply_visibility()
			if is_instance_valid(_diagnostics): _diagnostics.apply(packet,runtime_world)
		if DisplayServer.get_name()=="headless": acknowledge_presented(revision,int(packet.frame_id),layout_generation)
	frame_changed.emit(frame.duplicate(true))

func _unprefixed(value: String) -> String:
	if value.begins_with("import_"):
		var split := value.find("_",7)
		if split>=0: return value.substr(split+1)
	return value

func _restore_camera_mode() -> void:
	if _mode_to_restore.is_empty() or not camera_control: return
	var mode: int=int(_mode_to_restore.get("type",0))
	var target: String=_unprefixed(str(_mode_to_restore.get("target","")))
	if mode==2:
		var matches: Array=[]
		for i in range(2,catalog.get("cameras",[]).size()):
			if _unprefixed(catalog.cameras[i])==target: matches.append(i)
		if matches.size()==1: send({"action":"camera","id":matches[0]})
	elif mode==1:
		var matches: Array=catalog.get("bodies",[]).filter(func(body):return _unprefixed(body.name)==target)
		if matches.size()==1: send({"action":"track_body","name":matches[0].name})
	_mode_to_restore={}

func _apply_camera(target: Camera3D, state: Dictionary) -> void:
	if not is_instance_valid(target): return
	target.global_transform=state.transform
	target.keep_aspect=Camera3D.KEEP_HEIGHT
	target.h_offset=0;target.v_offset=0
	if state.orthographic:
		target.set_orthogonal(state.size,state.near,state.far)
		target.h_offset=state.offset.x;target.v_offset=state.offset.y
	elif state.offset.length_squared()>.00000001: target.set_frustum(state.size,state.offset,state.near,state.far)
	else: target.set_perspective(state.fov,state.near,state.far)

func _ensure_godot_presentation() -> void:
	if is_instance_valid(_godot_viewport): return
	_saved_disable_3d=source_viewport.disable_3d
	_owns_godot_disable=true
	_godot_viewport=SubViewport.new()
	_godot_viewport.name="MuJoCoGodotRenderRegion"
	_godot_viewport.own_world_3d=false
	_godot_viewport.world_3d=runtime_world.get_world_3d()
	_godot_viewport.size=Vector2i(_region.size)
	_godot_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	_godot_viewport.msaa_3d=source_viewport.msaa_3d
	add_child(_godot_viewport,false,Node.INTERNAL_MODE_BACK)
	_godot_camera=Camera3D.new()
	_godot_camera.name="PresentationCamera"
	if is_instance_valid(camera):
		_godot_camera.cull_mask=camera.cull_mask
		_godot_camera.environment=camera.environment
		_godot_camera.attributes=camera.attributes
	_godot_viewport.add_child(_godot_camera)
	_godot_camera.make_current()
	_godot_layer=CanvasLayer.new()
	_godot_layer.layer=-100
	source_viewport.add_child(_godot_layer,false,Node.INTERNAL_MODE_BACK)
	_godot_texture=TextureRect.new()
	_godot_texture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_godot_texture.texture=_godot_viewport.get_texture()
	_godot_texture.position=_region.position
	_godot_texture.size=_region.size
	_godot_texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_godot_layer.add_child(_godot_texture)
	source_viewport.disable_3d=true
	if not is_instance_valid(_diagnostics):
		_diagnostics=preload("godot_scene.gd").new()
		runtime_world.add_child(_diagnostics,false,Node.INTERNAL_MODE_BACK)

func _sync_render_properties() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(_godot_camera): return
	for property in ["cull_mask","environment","attributes","compositor"]:
		var value: Variant=camera.get(property)
		if _godot_camera.get(property)!=value: _godot_camera.set(property,value)

func resume_godot_presentation() -> void:
	if _closed or not attached or not is_instance_valid(consumer): return
	_ensure_godot_presentation()
	_sync_render_properties()
	if not _last_view_state.is_empty(): _apply_camera(_godot_camera,_last_view_state)

func suspend_godot_presentation() -> void:
	if is_instance_valid(_godot_texture): _godot_texture.texture=null
	if is_instance_valid(_godot_layer): _godot_layer.queue_free()
	if is_instance_valid(_godot_viewport): _godot_viewport.queue_free()
	_godot_texture=null;_godot_layer=null;_godot_viewport=null;_godot_camera=null
	if _owns_godot_disable and is_instance_valid(source_viewport): source_viewport.disable_3d=_saved_disable_3d
	_owns_godot_disable=false

func apply_visibility() -> void:
	if not is_instance_valid(consumer): return
	var allowed: Dictionary={}
	for id in frame.get("visible_geoms",PackedInt32Array()): allowed[id]=true
	for id in _geometry_targets:
		for mesh in _geometry_targets[id]:
			if is_instance_valid(mesh):
				if not _geometry_visibility.has(mesh.get_instance_id()): _geometry_visibility[mesh.get_instance_id()]=mesh.visible
				mesh.visible=allowed.has(id)

func cache_geometry() -> void:
	_geometry_targets.clear()
	var named: Dictionary={}
	for node in runtime_world.find_children("*","Node3D",true,false):
		if "visuals" in node and "model_rid" in node:
			var prefix := "import_%d_" % node.model_rid.get_id()
			for key in node.visuals: named[prefix+str(key)]=node.visuals[key]
	for geom in catalog.get("geoms",[]):
		if named.has(geom.name): _geometry_targets[geom.id]=[named[geom.name]]
		elif geom.get("object_id",0)>0:
			var owner_node: Object=instance_from_id(geom.object_id)
			if not is_instance_valid(owner_node) or not owner_node is Node: continue
			if "native_rids" in owner_node and "native_collisions" in owner_node:
				var index: int=owner_node.native_rids.find(geom.get("owner_rid",RID()))
				var visual: Node=owner_node.get_node_or_null("Visual")
				if index>=0 and index<owner_node.native_collisions.size() and visual:
					var path: String=owner_node.native_collisions[index].get("source_node","")
					var mesh: Node=visual.get_node_or_null(path)
					if mesh is MeshInstance3D: _geometry_targets[geom.id]=[mesh]
			else: _geometry_targets[geom.id]=owner_node.find_children("*","MeshInstance3D",true,false)

func _restore_geometry_visibility() -> void:
	for id in _geometry_visibility:
		var node: Object=instance_from_id(id)
		if is_instance_valid(node): node.visible=_geometry_visibility[id]
	_geometry_visibility.clear()

func acknowledge_presented(revision: int, id: int, layout: int) -> bool:
	if frames_retiring or layout!=layout_generation or not attached or not is_instance_valid(runtime_world): return false
	if not PhysicsServer3D.call("scene_viewer_ack",runtime_world.space,revision,id):
		presented_layout=-1;presented_frame_id=0
		return false
	presented_revision=revision;presented_frame_id=id;presented_layout=layout
	return true

func after_draw() -> void:
	if _closed or not attached or not is_instance_valid(runtime_world): return
	if not runtime_world.native_view_active and not is_instance_valid(consumer):
		if is_instance_valid(extras_client) and _direct_godot_draw_observed():fps_count+=1
		return
	if frame.is_empty():return
	update_viewport_rect()
	if not runtime_world.native_view_active and last_backend=="godot" and applied_layout==layout_generation and is_instance_valid(_godot_viewport):
		if acknowledge_presented(int(frame.revision),int(frame.frame_id),applied_layout): fps_count+=1

func native_presented(number: int, revision: int, id: int, layout: int=-1) -> void:
	update_viewport_rect()
	if frames_retiring or layout!=layout_generation: return
	if number!=last_native_frame: last_native_frame=number;fps_count+=1
	acknowledge_presented(revision,id,layout)

func begin_frame_retirement() -> void:
	if frames_retiring or not attached or not is_instance_valid(runtime_world) or frame.is_empty(): return
	_retire_target={"space":runtime_world.space,"revision":int(frame.revision),"frame":int(frame.frame_id)}
	frames_retiring=true;presented_layout=-1;presented_frame_id=0
	_submit_frame_retirement()

func _submit_frame_retirement() -> void:
	if not frames_retiring or frame_retire_request!=0 or _retire_target.is_empty(): return
	_sequence+=1
	frame_retire_request=PhysicsServer3D.call("scene_viewer_request",_retire_target.space,_retire_target.revision,_retire_target.frame,_sequence,{"action":"cancel","release_frames":true})
	if frame_retire_request>0: pending[frame_retire_request]="cancel"

func cancel_gesture(release_frames := false) -> void:
	if release_frames: begin_frame_retirement()
	elif attached and not frame.is_empty(): send({"action":"cancel"})

func release_display_frames() -> void:
	cancel_gesture(true)
	frame={};known_revision=-1;presented_revision=-1;presented_frame_id=0;presented_layout=-1

func reload_saved() -> bool:
	if _rebuilding: last_error="Saved-world reload is already running"; return false
	if _reload_source_path.is_empty(): _discover_reload_source()
	if _reload_source_path.is_empty(): last_error="This world has no saved scene source"; return false
	var saved: PackedScene=preload("../model/saved_scene_loader.gd").load_scene(_reload_source_path)
	if not saved: last_error="Cannot load saved scene: "+_reload_source_path; return false
	_rebuilding=true
	cancel_gesture()
	var host: Node=preload("../model/environment_host.gd").new()
	_reload_host=host
	host.name="ReloadedMuJoCoEnvironment"
	host.environment_scene=saved
	host.environment_world_path=_reload_world_path
	# Host owns the transactional handoff, including renderer transport and pause.
	host.world=runtime_world
	host.rebuild_finished.connect(func(success: bool,error: String):
		_rebuilding=false
		_reload_host=null
		if not success:
			last_error=error
			reload_finished.emit(false,error)
			host.queue_free()
			return
		var old: Node3D=runtime_world
		old.emit_signal("runtime_replaced",host.world,host)
		target_replaced.emit(host.world,host)
		reload_finished.emit(true,"")
		if get_tree().current_scene==old: get_tree().current_scene=host
		old.queue_free(),CONNECT_ONE_SHOT)
	get_tree().root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return true

func cancel_reload() -> bool:
	if not _rebuilding or not is_instance_valid(_reload_host):return false
	return _reload_host.cancel_rebuild_environment()

func shutdown() -> void:
	if _closed: return
	cancel_reload()
	model_changing.emit()
	cancel_requests(_request_origins.keys(),"Presentation session closed")
	cancel_gesture(true)
	set_camera_control(false)
	if is_instance_valid(consumer): detach_consumer(consumer)
	if is_instance_valid(extras_client):detach_extras(extras_client)
	suspend_godot_presentation()
	if is_instance_valid(_diagnostics): _diagnostics.queue_free()
	_diagnostics=null
	for id in pending: PhysicsServer3D.call("scene_cancel_world_command",id)
	pending.clear()
	_request_origins.clear()
	attached=false;_closed=true

func _exit_tree() -> void:
	shutdown()
	if RenderingServer.frame_post_draw.is_connected(after_draw): RenderingServer.frame_post_draw.disconnect(after_draw)
