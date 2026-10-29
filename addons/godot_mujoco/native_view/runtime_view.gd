class_name MjNativeRuntimeView
extends Control
## Experimental runtime process only. No selection, perturbation, mixed Godot 3D,
## custom materials, or exact contact-force overlays are promised by this transport.
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
var saved_visible := true
var saved_disable_3d := false
var saved_picking := false
var saved_camera: Camera3D
var source_viewport: Viewport
var camera_action := -1
var camera_delta := Vector2.ZERO
var accepted_inputs := 0
var submitted := 0
var stopped := true
var waiting_for_world := false
var pending_status := ""

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
	world=value;world.set_meta("native_view_owner",weakref(self));source_viewport=get_viewport()
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
	stopped=false;waiting_for_world=true;pending_status="initializing";known_revision=-1;latest={};last_snapshot={};last_error="";active=false
	mouse_filter=Control.MOUSE_FILTER_STOP
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
	if latest.has("texture"):
		RenderingServer.canvas_item_clear(canvas)
		RenderingServer.canvas_item_add_texture_rect(canvas,Rect2(Vector2.ZERO,size),latest.texture)
		bridge.acknowledge(int(latest.generation))
		if not active:
			saved_visible=world.visible;saved_disable_3d=source_viewport.disable_3d;saved_picking=source_viewport.physics_object_picking;saved_camera=source_viewport.get_camera_3d()
			if is_instance_valid(saved_camera): saved_camera.clear_current(false)
			source_viewport.disable_3d=true;source_viewport.physics_object_picking=false;world.visible=false;world.native_view_active=true;active=true
			if request_direct_to_screen:
				RenderingServer.force_sync()
				RenderingServer.viewport_set_render_direct_to_screen(source_viewport.get_viewport_rid(),true)
	if not bridge.ready_for_request(): return
	var packet: Dictionary=PhysicsServer3D.call("scene_native_view_snapshot",world.space,known_revision)
	if packet.get("pending",false):
		waiting_for_world=true;pending_status=str(packet.get("status","pending"));return
	waiting_for_world=false;pending_status=""
	if packet.has("error"):
		stop(str(packet.error)); return
	var ticket: int=bridge.request_shared(packet,maxi(16,int(size.x)),maxi(16,int(size.y)),camera_delta.x,camera_delta.y,camera_action)
	if ticket>0:
		known_revision=int(packet.revision);last_snapshot=packet;last_snapshot.erase("model");last_snapshot.erase("objects");submitted+=1;camera_action=-1;camera_delta=Vector2.ZERO

func _gui_input(event: InputEvent) -> void:
	if stopped: return
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		camera_action=1;camera_delta+=event.relative/maxf(size.y,1.0);accepted_inputs+=1;accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		camera_action=5;camera_delta.y+=-0.05 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.05;accepted_inputs+=1;accept_event()

func stop(reason := "") -> Dictionary:
	if stopped: return last_cleanup
	stopped=true;waiting_for_world=false;pending_status="";last_error=reason;set_process(false)
	if is_instance_valid(source_viewport): RenderingServer.viewport_set_render_direct_to_screen(source_viewport.get_viewport_rid(),false)
	if canvas.is_valid():
		RenderingServer.canvas_item_clear(canvas);RenderingServer.free_rid(canvas);canvas=RID()
	latest.erase("texture");last_snapshot.clear();canvas_material=null
	# Consume all prior canvas references before releasing imported GPU resources.
	RenderingServer.force_sync()
	if is_instance_valid(bridge): last_cleanup=bridge.finish();bridge.queue_free();bridge=null
	if active and is_instance_valid(source_viewport):
		source_viewport.disable_3d=saved_disable_3d;source_viewport.physics_object_picking=saved_picking
		if is_instance_valid(saved_camera): saved_camera.make_current()
	if is_instance_valid(world):
		if active:
			world.sync_native_view_fallback()
			world.visible=saved_visible
		world.native_view_active=false
		if world.has_meta("native_view_owner"): world.remove_meta("native_view_owner")
	active=false;world=null;mouse_filter=Control.MOUSE_FILTER_IGNORE
	return last_cleanup

func _exit_tree() -> void:
	stop("Native view removed")
