class_name MjNativeRuntimeView
extends Control
## Native display adapter. Input is optional; authoritative CPU scenes belong to the world presentation session.
@export var enabled := false
@export var request_direct_to_screen := false
var world: Node3D
var bridge: Node
var canvas := RID()
var canvas_material: ShaderMaterial
var latest: Dictionary = {}
var last_snapshot: Dictionary = {}
var last_cleanup: Dictionary = {}
var last_error := ""
var known_revision := -1
var active := false
var saved_disable_3d := false
var source_viewport: Viewport
var camera_action := -1
var camera_delta := Vector2.ZERO
var accepted_inputs := 0
var submitted := 0
var stopped := true
var waiting_for_world := false
var pending_status := ""
var request_layouts := {}
var canvas_layout := -1
var pending_presented := {}

func start_for(value: Node3D) -> bool:
	if not enabled or Engine.is_editor_hint(): return false
	if not stopped: return false
	if OS.get_name() != "Linux" or DisplayServer.get_name() != "X11" or RenderingServer.get_current_rendering_method() != "gl_compatibility":
		last_error = "Native view is limited to Linux/X11/OpenGL"; return false
	if DisplayServer.get_window_list().size() != 1 or get_window() != get_tree().root:
		last_error = "Native view requires one main runtime window"; return false
	if ProjectSettings.get_setting("physics/3d/run_on_separate_thread",false) or not PhysicsServer3D.has_method("scene_native_view_snapshot") or not ClassDB.class_exists("MjSharedNativeViewBridge"):
		last_error = "Native view requires the experimental backend and main-thread physics"; return false
	if not is_instance_valid(value) or not value.ready_for_models or value.get_viewport()!=get_viewport():
		last_error = "Shared runtime world is unavailable"; return false
	if value.info().get("compile_status", "") == "closed":
		last_error = "Shared world is closed"; return false
	if value.native_view_active or value.has_meta("native_view_owner"):
		last_error = "Shared world already has a native view owner"; return false
	world=value;world.set_meta("native_view_owner",weakref(self));source_viewport=value.get_viewport()
	world._view_session.retry_camera_sync()
	bridge=ClassDB.instantiate("MjSharedNativeViewBridge");add_child(bridge)
	if not bridge.acquire_transport():
		last_error="Another native view owns the process memory budget";bridge.queue_free();bridge=null;world.remove_meta("native_view_owner");world=null;return false
	bridge.configure_viewport(source_viewport.get_viewport_rid(),true)
	# Bind only for owned-window validation/capture; engine owns window swapping.
	var binding: Dictionary=bridge.configure_presentation(DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,get_window().get_window_id()))
	if not binding.get("ok",false):
		last_error=str(binding.get("error","Window context unavailable"));bridge.finish();bridge.queue_free();bridge=null;world.remove_meta("native_view_owner");world=null;return false
	canvas_material=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="shader_type canvas_item; render_mode unshaded, blend_disabled; void fragment(){COLOR=vec4(texture(TEXTURE,vec2(UV.x,1.0-UV.y)).rgb,1.0);}"
	canvas_material.shader=shader
	canvas=RenderingServer.canvas_item_create();RenderingServer.canvas_item_set_parent(canvas,get_canvas_item());RenderingServer.canvas_item_set_material(canvas,canvas_material.get_rid())
	if not RenderingServer.frame_post_draw.is_connected(after_draw): RenderingServer.frame_post_draw.connect(after_draw)
	stopped=false;waiting_for_world=true;pending_status="initializing";known_revision=-1;latest={};last_snapshot={};last_error="";active=false
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_process(true)
	return true

func _process(_delta: float) -> void:
	if stopped: return
	if not is_instance_valid(world) or not world.ready_for_models:
		stop("Shared world closed"); return
	if DisplayServer.get_window_list().size()!=1:
		stop("Multiple runtime windows require Godot rendering"); return
	latest=bridge.snapshot()
	if latest.has("error"):
		stop(str(latest.error)); return
	var viewer: Node=world._view_session
	if is_instance_valid(viewer): viewer.update_viewport_rect()
	if latest.has("texture"):
		var layout: Dictionary=request_layouts.get(int(latest.frame),{})
		var valid_layout: bool=is_instance_valid(viewer) and not viewer.frames_retiring and layout.get("generation",-1)==viewer.layout_generation and layout.get("rect",Rect2())==viewer.render_rect_in_source()
		RenderingServer.canvas_item_clear(canvas)
		if valid_layout:
			RenderingServer.canvas_item_add_texture_rect(canvas,layout.rect,latest.texture)
			canvas_layout=int(layout.generation)
			pending_presented={"number":int(latest.frame),"revision":int(latest.get("viewer_revision",-1)),"frame_id":int(latest.get("viewer_frame_id",0)),"layout":canvas_layout}
		else: canvas_layout=-1;pending_presented.clear()
		# Acknowledge retired textures even during layout transitions. A texture
		# from the old aspect is never stretched into a different camera frame.
		bridge.acknowledge(int(latest.generation))
		for ticket in request_layouts.keys():
			if ticket<int(latest.frame): request_layouts.erase(ticket)
		if valid_layout and not active:
			# Keep the clipped Godot fallback until a valid native texture exists.
			viewer.suspend_godot_presentation()
			saved_disable_3d=source_viewport.disable_3d
			source_viewport.disable_3d=true;world.native_view_active=true;active=true
			if request_direct_to_screen:
				RenderingServer.force_sync()
				RenderingServer.viewport_set_render_direct_to_screen(source_viewport.get_viewport_rid(),true)
	if not bridge.ready_for_request() or is_instance_valid(viewer) and viewer.frames_retiring: return
	if is_instance_valid(viewer): viewer.prepare_frame()
	if is_instance_valid(viewer) and not viewer.camera_sync_error.is_empty():
		stop("Source camera synchronization failed: "+viewer.camera_sync_error); return
	if is_instance_valid(viewer) and not viewer.ready_for_capture():
		waiting_for_world=true;pending_status="Synchronizing source camera";return
	var options: Dictionary=viewer.frame_options("native") if is_instance_valid(viewer) else {}
	var packet: Dictionary=PhysicsServer3D.call("scene_native_view_snapshot",world.space,known_revision,true,options)
	if packet.get("pending",false):
		waiting_for_world=true;pending_status=str(packet.get("status","pending"));return
	waiting_for_world=false;pending_status=""
	if packet.has("error"):
		stop(str(packet.error)); return
	if is_instance_valid(world._view_session): world._view_session.accept_frame(packet)
	if is_instance_valid(viewer) and viewer.frames_retiring: return
	var central: Rect2=viewer.render_rect_in_source() if is_instance_valid(viewer) else Rect2(Vector2.ZERO,size)
	var ticket: int=bridge.request_shared(packet,maxi(16,int(central.size.x)),maxi(16,int(central.size.y)),camera_delta.x,camera_delta.y,camera_action)
	if ticket>0:
		request_layouts[ticket]={"rect":central,"generation":viewer.layout_generation if is_instance_valid(viewer) else -1}
		known_revision=int(packet.revision);last_snapshot=packet;last_snapshot.erase("model");last_snapshot.erase("objects");submitted+=1;camera_action=-1;camera_delta=Vector2.ZERO

func after_draw() -> void:
	if stopped or pending_presented.is_empty() or not is_instance_valid(world) or not is_instance_valid(world._view_session): return
	var shown: Dictionary=pending_presented
	pending_presented={}
	world._view_session.native_presented(shown.number,shown.revision,shown.frame_id,shown.layout)

func stop(reason := "") -> Dictionary:
	if stopped: return last_cleanup
	if is_instance_valid(world) and is_instance_valid(world._view_session): world._view_session.release_display_frames()
	stopped=true;waiting_for_world=false;pending_status="";last_error=reason;set_process(false)
	if is_instance_valid(source_viewport): RenderingServer.viewport_set_render_direct_to_screen(source_viewport.get_viewport_rid(),false)
	if canvas.is_valid():
		RenderingServer.canvas_item_clear(canvas);RenderingServer.free_rid(canvas);canvas=RID()
	latest.erase("texture");last_snapshot.clear();canvas_material=null;request_layouts.clear();canvas_layout=-1;pending_presented.clear()
	# Consume all prior canvas references before releasing imported GPU resources.
	RenderingServer.force_sync()
	if is_instance_valid(bridge): last_cleanup=bridge.finish();bridge.queue_free();bridge=null
	if active and is_instance_valid(source_viewport):
		source_viewport.disable_3d=saved_disable_3d
	if is_instance_valid(world):
		world.native_view_error=reason
		if active:
			world.sync_native_view_fallback()
		world.native_view_active=false
		if is_instance_valid(world._view_session): world._view_session.resume_godot_presentation()
		if world.has_meta("native_view_owner"): world.remove_meta("native_view_owner")
	active=false;world=null;mouse_filter=Control.MOUSE_FILTER_IGNORE
	return last_cleanup

func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(after_draw): RenderingServer.frame_post_draw.disconnect(after_draw)
	stop("Native view removed")
