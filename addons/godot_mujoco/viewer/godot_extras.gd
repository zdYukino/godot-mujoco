@tool
@icon("res://addons/godot_mujoco/icons/mj_extras.svg")
class_name MjGodotExtras
extends MjRuntimeUiClient
## Optional F11 tools and metrics. Never owns a camera or 3D render region.
const DefaultUI = preload("extras_ui.tscn")
const SystemPerformance = preload("performance.gd")
const ACTIONS := ["controls","performance","metric","renderer","step","capture_snapshot","restore_snapshot","ui_color","ui_font","ui_spacing"]
var _performance_source: RefCounted
var _next_system := 0
var _renderer_dispatch_generation := 0
var _extensions := {}
var _extension_holder: Control
func _init() -> void:layer=81;ui_scene=DefaultUI
func _attach_session() -> String:return _session.attach_extras(self)
func _detach_session() -> void:_session.detach_extras(self)
func _prepare_component() -> void:
	_performance_source=SystemPerformance.new();configure_metrics()
	if not action_allowed("performance"):ui.set_overlay(false)
func _activate_component() -> void:_update_layout()
func _reset_component() -> void:_performance_source=null;_renderer_dispatch_generation+=1
func _create_ui(preview: bool) -> bool:
	if is_instance_valid(ui):return true
	if not ui_scene:return _fail("Assign an Extras UI PackedScene.")
	var candidate: Node=ui_scene.instantiate()
	if not candidate is MjExtrasUI:
		candidate.free();return _fail("Extras UI scene root must extend MjExtrasUI.")
	ui=candidate
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	if preview:ui.size=Vector2(1024,704)
	add_child(ui,false,Node.INTERNAL_MODE_BACK)
	ui.configure(self,ui_theme,preview)
	var error: String=ui.validate_scene()
	if not error.is_empty():ui.queue_free();ui=null;return _fail(error)
	if preview:return true
	ui.action_requested.connect(_on_ui_action)
	ui.layout_changed.connect(_update_layout)
	ui.runtime_world=bound_world;ui.visible=true
	for key in _extensions:
		var data: Dictionary=_extensions[key]
		if is_instance_valid(data.widget) and ui.extras_sections.has("Examples"):ui.add_extension(key,data.title,data.widget)
	_register_existing_windows(ui)
	return true
func _detach_ui(preserve: bool) -> void:
	ui.runtime_world=null;ui.frame={};ui.system_metrics={}
	if preserve:return
	# Hiding a removed Extras component does not cancel another role's gesture.
	if is_instance_valid(ui.controls):ui.controls.hide()
	for key in _extensions:
		var widget: Control=_extensions[key].widget
		if is_instance_valid(widget) and widget.get_parent():
			widget.get_parent().remove_child(widget);_get_extension_holder().add_child(widget)
	ui.hide();ui.queue_free();ui=null
func _process_active() -> void:
	_update_layout();_poll_operations()
	if status!="ACTIVE" or not is_instance_valid(ui):return
	var now := Time.get_ticks_msec()
	if now>=_next_info:
		_next_info=now+200;ui.apply_snapshot(_snapshot());_apply_policy()
	if now>=_next_system:
		_next_system=now+1000
		if ui.overlay_enabled and is_instance_valid(ui.hud) and ui.hud.is_visible_in_tree() and action_allowed("performance") and _performance_source:
			var wanted: Dictionary=ui.metrics.duplicate()
			for metric in wanted:wanted[metric]=wanted[metric] and action_allowed("metric",{"name":metric})
			if wanted.get("cpu",false) or wanted.get("ram",false) or wanted.get("gpu",false) or wanted.get("vram",false):ui.system_metrics=_performance_source.sample(wanted)
func _snapshot() -> Dictionary:
	var fps_status: Dictionary=_session.renderer_fps_status() if is_instance_valid(_session) else {"available":false,"reason":"Target is unbound"}
	return {"renderer_fps_available":fps_status.available,"renderer_fps_reason":fps_status.reason,"status":status,"reason":last_error,"enabled":enabled,"frame":_session.client_state() if is_instance_valid(_session) else {},"backend":bound_world.rendering_status() if is_instance_valid(bound_world) else "","renderer_fps":_session.renderer_fps if is_instance_valid(_session) else 0.,"host_fps":_session.host_fps if is_instance_valid(_session) else 0.}
func _frame_changed(_packet: Dictionary) -> void:pass
func _model_changing() -> void:
	if is_instance_valid(ui):ui.frame={}
func _on_result(_action: String,result: Dictionary) -> void:
	if not result.get("success",false):
		last_error=str(result.get("error",""))
		if is_instance_valid(ui):ui.feedback=last_error
func action_allowed(action_id: StringName,arguments: Dictionary = {}) -> bool:return _action_rejection(action_id,arguments).is_empty()
func _action_rejection(action_id: StringName,arguments: Dictionary) -> String:
	if str(action_id) not in ACTIONS:return "This action does not belong to MjGodotExtras."
	var reason: String=configuration.rejection_reason(action_id,arguments)
	if not reason.is_empty():return reason
	if _has_authored_theme() and action_id in [&"ui_color",&"ui_font",&"ui_spacing"]:return "Preset styling is controlled by the authored Theme resource."
	if is_instance_valid(ui) and not ui.provides_action(action_id):return "Current Extras UI scene does not provide this presentation module: "+str(action_id)
	return ""
func execute(action_id: StringName,arguments: Dictionary = {}) -> int:
	if status!="ACTIVE" or not enabled or not is_instance_valid(_session) or not is_instance_valid(bound_world) or not is_instance_valid(ui):last_error="UNAVAILABLE: component is disabled or unbound";return 0
	if _requests.size()+_operations.size()>=64:last_error="Extras request capacity reached; wait for pending results.";return 0
	last_error=_action_rejection(action_id,arguments)
	if not last_error.is_empty():ui.feedback=last_error;return 0
	var args := arguments.duplicate(true)
	match str(action_id):
		"controls":ui.set_controls_visible(args.get("value",not ui.controls.visible))
		"performance":ui.set_overlay(args.get("value",not ui.overlay_enabled))
		"metric":
			var metric := str(args.get("name",""))
			if not ui.metrics.has(metric):last_error="Unknown metric";return 0
			if _performance_source and not _performance_source.availability(metric).is_empty():last_error=_performance_source.availability(metric);return 0
			ui.metrics[metric]=args.get("value",not ui.metrics[metric])
			if ui.metric_checks.has(metric):ui.metric_checks[metric].set_pressed_no_signal(ui.metrics[metric])
			ui.refresh_hud();save_view_preferences()
		"ui_color","ui_font","ui_spacing":ui.set(str(action_id),int(args.get("value",0)));ui.apply_ui_theme();save_view_preferences()
		"renderer":
			_renderer_dispatch_generation+=1
			var generation := _renderer_dispatch_generation
			var target: Node3D=bound_world
			var session: Node=_session
			# Completion callbacks may disable, retarget or submit a newer request.
			# Settle an already reached backend truthfully before superseding work.
			_poll_operations()
			if not _renderer_dispatch_valid(target,session,generation):return 0
			cancel_interaction()
			for pending_id in _operations.keys():
				if _operations.has(pending_id) and _operations[pending_id].action=="renderer":_finish_operation(pending_id,{"success":false,"error":"Renderer request superseded","cancelled":true})
				if not _renderer_dispatch_valid(target,session,generation):return 0
			var desired: bool=args.get("native",false);bound_world.native_view_experimental=desired
			if desired:
				if not bound_world.start_native_view():last_error=bound_world.native_view_error;ui.feedback=last_error;return 0
			else:bound_world.stop_native_view()
			var id := _next_local;_next_local+=1
			_operations[id]={"action":"renderer","native":desired,"deadline":Time.get_ticks_msec()+30000}
			return id
		_:
			args.action=str(action_id)
			var request: int=_session.send_state(args)
			if request>0:_requests[request]=str(action_id)
			else:last_error="UNAVAILABLE: no committed model or command queue is full"
			return request
	var id := _next_local;_next_local+=1
	_remember_result(id,{"success":true,"action":str(action_id),"error":""})
	return id
func show_performance(value: bool) -> bool:return execute("performance",{"value":value})>0
func show_extras(value: bool) -> bool:return execute("controls",{"value":value})>0
func _configuration_changed() -> void:
	if Engine.is_editor_hint() or _detaching:return
	if is_instance_valid(ui):
		configure_metrics();_apply_policy()
		if not action_allowed("performance"):ui.set_overlay(false)
func _update_layout() -> void:
	if not is_instance_valid(ui) or not is_instance_valid(_session):return
	var viewport: Viewport=bound_world.get_viewport()
	_target_rect=get_viewport().get_visible_rect()
	if viewport!=get_viewport() and viewport is SubViewport and viewport.get_parent() is SubViewportContainer:_target_rect=viewport.get_parent().get_global_rect()
	ui.position=_target_rect.position;ui.size=_target_rect.size
	var scale := _target_rect.size/viewport.get_visible_rect().size
	var region: Rect2=_session.render_rect_in_source()
	ui.outer_rect=Rect2(Vector2.ZERO,_target_rect.size)
	ui.render_rect=Rect2(region.position*scale,region.size*scale)
	var occupied: Array[Rect2]=[]
	for rect in _session.occupied_overlay_rects():occupied.append(Rect2(rect.position*scale,rect.size*scale))
	ui.overlay_exclusions=occupied
	ui.position_hud()
func _input(event: InputEvent) -> void:global_input(event,get_viewport())
func _handle_global_input(event: InputEvent,viewport: Viewport) -> void:
	if status!="ACTIVE" or not enabled:return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F11:
		if event.get_instance_id()==_last_global_event:return
		_last_global_event=event.get_instance_id()
		if key_input(event):viewport.set_input_as_handled()
func key_input(event: InputEvent) -> bool:
	if event.get_instance_id()==_last_key_event:return true
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_F11:return false
	if not has_ui_focus() and not _owns_keyboard_scope():return false
	var handled := show_extras(not ui.controls.visible) if is_instance_valid(ui) and is_instance_valid(ui.controls) else false
	if handled:_last_key_event=event.get_instance_id()
	return handled
func has_ui_focus() -> bool:
	if status!="ACTIVE" or not is_instance_valid(ui):return false
	for window in managed_popups:
		if is_instance_valid(window) and window.visible and window.has_focus():return true
	return false
func cancel_interaction() -> void:
	# Only an explicit opening/backend action asks the interactive role to release.
	if is_instance_valid(_session):
		if is_instance_valid(_session.consumer):_session.consumer.cancel_interaction()
		else:_session.cancel_gesture()
func _get_extension_holder() -> Control:
	if not is_instance_valid(_extension_holder):_extension_holder=Control.new();_extension_holder.process_mode=Node.PROCESS_MODE_DISABLED;_extension_holder.hide();add_child(_extension_holder,false,Node.INTERNAL_MODE_BACK)
	return _extension_holder
func add_extension(key: String,title: String,widget: Control) -> void:
	if not is_instance_valid(widget):last_error="Extension widget must be a valid Control.";return
	if _extensions.has(key):
		if _extensions[key].widget==widget:return
		remove_extension(key)
	_extensions[key]={"title":title,"widget":widget}
	if is_instance_valid(ui) and ui.extras_sections.has("Examples"):ui.add_extension(key,title,widget)
	else:
		if widget.get_parent():widget.get_parent().remove_child(widget)
		_get_extension_holder().add_child(widget)
func remove_extension(key: String) -> void:
	var widget: Control=_extensions.get(key,{}).get("widget")
	if is_instance_valid(ui):ui.remove_extension(key)
	if is_instance_valid(widget) and not widget.is_queued_for_deletion():
		widget.set_block_signals(true)
		for child in widget.find_children("*","Node",true,false):child.set_block_signals(true)
		if widget.get_parent():widget.get_parent().remove_child(widget)
		widget.queue_free()
	_extensions.erase(key)
func _renderer_dispatch_valid(target: Node3D,session: Node,generation: int) -> bool:
	if status=="ACTIVE" and enabled and not is_queued_for_deletion() and is_instance_valid(target) and not target.is_queued_for_deletion() and bound_world==target and is_instance_valid(session) and _session==session and generation==_renderer_dispatch_generation:return true
	last_error="Renderer request interrupted by component lifetime, target or newer request."
	return false
func _poll_operations() -> void:
	for id in _operations.keys():
		if status!="ACTIVE" or not is_instance_valid(bound_world):return
		if not _operations.has(id):continue
		var operation: Dictionary=_operations[id]
		if operation.action!="renderer":continue
		var actual: bool=bound_world.native_view_active
		if actual==operation.native:
			_finish_operation(id,{"success":true,"error":"","requested_native":operation.native,"actual_backend":"native" if actual else "godot"})
		elif not bound_world.native_view_error.is_empty() or Time.get_ticks_msec()>operation.deadline:
			var reason: String=bound_world.native_view_error if not bound_world.native_view_error.is_empty() else "Renderer transition timed out."
			if is_instance_valid(ui):ui.feedback=reason
			_finish_operation(id,{"success":false,"error":reason,"requested_native":operation.native,"actual_backend":"native" if actual else "godot"})
func configure_metrics() -> void:
	if not is_instance_valid(ui):return
	for name in ui.metric_checks:
		var reason := _action_rejection("metric",{"name":name})
		if reason.is_empty() and _performance_source:reason=_performance_source.availability(name)
		ui.metric_checks[name].disabled=not reason.is_empty();ui.metric_checks[name].set_meta("viewer_capability_disabled",not reason.is_empty());ui.metric_checks[name].tooltip_text=reason
		if not reason.is_empty():ui.metrics[name]=false;ui.metric_checks[name].set_pressed_no_signal(false)
func _apply_policy() -> void:
	for node in ui.find_children("*","Control",true,false):
		if not node.has_meta("viewer_action"):continue
		var action_id: StringName=node.get_meta("viewer_action")
		var reason := _action_rejection(action_id,node.get_meta("viewer_arguments",{}))
		if node is OptionButton:
			var any_available := false;var unavailable_reason := reason
			for index in node.item_count:
				var option_args: Dictionary=node.get_meta("viewer_arguments",{}).duplicate()
				if action_id==&"camera":option_args.id=index
				else:option_args.value=index
				var option_reason := _action_rejection(action_id,option_args)
				node.set_item_disabled(index,not option_reason.is_empty())
				if option_reason.is_empty():any_available=true
				elif unavailable_reason.is_empty():unavailable_reason=option_reason
			# A restricted choice must not disable the other choices in its selector.
			reason="" if any_available else unavailable_reason
		var capability_disabled := bool(node.get_meta("viewer_capability_disabled",false))
		if node is BaseButton:node.disabled=bool(node.get_meta("viewer_authored_disabled",false)) or capability_disabled or not reason.is_empty()
		elif node is Range or node is LineEdit:node.editable=bool(node.get_meta("viewer_authored_editable",true)) and not capability_disabled and reason.is_empty()
		if not reason.is_empty():node.tooltip_text=reason
func _load_preferences() -> void:
	if _preferences_loaded or not is_instance_valid(ui):return
	_preferences_loaded=true
	var scene: Node=get_tree().current_scene
	if not scene:
		scene=get_parent()
		while scene.get_parent() and scene.scene_file_path.is_empty():scene=scene.get_parent()
	var identity := preferences_id if not preferences_id.is_empty() else scene.scene_file_path+"::"+str(scene.get_path_to(self))
	_preference_registry_key=ProjectSettings.globalize_path("res://")+"::extras::"+identity
	var registry: Dictionary=get_tree().root.get_meta("mj_viewer_preference_ids",{})
	var existing: WeakRef=registry.get(_preference_registry_key)
	if existing and is_instance_valid(existing.get_ref()) and existing.get_ref()!=self:
		_preferences_enabled=false;ui.feedback="Duplicate Extras preferences_id; personal state will not be shared.";return
	registry[_preference_registry_key]=weakref(self);get_tree().root.set_meta("mj_viewer_preference_ids",registry)
	_config_path="user://mujoco_components/"+_preference_registry_key.sha256_text().substr(0,24)+".cfg"
	if not restore_preferences or _config.load(_config_path)!=OK:return
	if _preference_allowed("visibility"):
		ui.set_overlay(_config.get_value("view","performance",true) and action_allowed("performance"))
		for title in ui.extras_sections:ui.extras_sections[title].button.button_pressed=_config.get_value("expanded",title,ui.extras_sections[title].button.button_pressed)
	if _preference_allowed("layout") and is_instance_valid(ui.controls):ui.controls.position=_config.get_value("window","position",ui.controls.position);ui.controls.size=_config.get_value("window","size",ui.controls.size)
	if _preference_allowed("style") and not _has_authored_theme():
		for field in ["ui_spacing","ui_color","ui_font"]:
			if action_allowed(field):ui.set(field,_config.get_value("style",field,ui.get(field)))
		ui.apply_ui_theme()
	if _preference_allowed("metrics"):
		for metric in ui.metrics:
			ui.metrics[metric]=_config.get_value("metrics",metric,ui.metrics[metric]) and action_allowed("metric",{"name":metric})
			if ui.metric_checks.has(metric):ui.metric_checks[metric].set_pressed_no_signal(ui.metrics[metric])
	configure_metrics()
func save_view_preferences(immediate := false) -> void:
	if Engine.is_editor_hint() or not _preferences_enabled or _config_path.is_empty() or not is_instance_valid(ui):return
	if not immediate:_save_due=Time.get_ticks_msec()+1000;return
	_save_due=0
	if _preference_allowed("visibility"):
		_config.set_value("view","performance",ui.overlay_enabled)
		for title in ui.extras_sections:_config.set_value("expanded",title,ui.extras_sections[title].button.button_pressed)
	if _preference_allowed("layout") and is_instance_valid(ui.controls):_config.set_value("window","position",ui.controls.position);_config.set_value("window","size",ui.controls.size)
	if _preference_allowed("metrics"):
		for metric in ui.metrics:_config.set_value("metrics",metric,ui.metrics[metric])
	if _preference_allowed("style") and not _has_authored_theme():
		for field in ["ui_spacing","ui_color","ui_font"]:_config.set_value("style",field,ui.get(field))
	DirAccess.make_dir_recursive_absolute("user://mujoco_components")
	if _config.save(_config_path)!=OK:last_error="Cannot save Extras preferences."

func _component_name() -> String:return "MjGodotExtras"
