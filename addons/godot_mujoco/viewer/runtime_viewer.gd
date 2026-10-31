@tool
@icon("res://addons/godot_mujoco/icons/mj_viewer.svg")
class_name MjRuntimeViewer
extends MjRuntimeUiClient
## Optional original MuJoCo panel and interaction owner. Godot Extras is separate.
const DefaultUI = preload("default_ui.tscn")
const Keys = preload("shortcuts.gd")
enum LayoutMode { RESERVED, OVERLAY }
@export var layout_mode := LayoutMode.RESERVED
@export var output_path := "user://mujoco_viewer"
var _help := {}
var _dragging := false
var _perturbing := false
var _logical_button := 0
var _last_click := 0
var _last_click_button := 0
var _last_region := Rect2()
var _layout_ticks := 0
var _layout_pending := false
var _layout_changed_frame := -1
var _display_restore_pending := false
var _display_restore_revision := -1
var _setting_ui_bounds := false
var _preference_commands: Array[Dictionary] = []
var _display_save_wait := {}
func _init() -> void:layer=80;ui_scene=DefaultUI
func _attach_session() -> String:return _session.attach_consumer(self)
func _detach_session() -> void:_session.detach_consumer(self)
func _activate_component() -> void:
	_session.set_camera_control(_camera_interaction_allowed())
	_layout_ticks=0;_update_layout()
func _reset_component() -> void:
	_preference_commands.clear();_display_save_wait.clear();_last_region=Rect2()
	_display_restore_pending=false;_display_restore_revision=-1;_layout_changed_frame=-1
func _detach_ui(preserve: bool) -> void:
	ui.retire_model_controls();ui.retire_catalog_controls();ui.clear_sensor_images();ui.selected_image_sensor=-1
	ui.runtime_world=null;ui.frame={};ui.catalog={};ui.details={}
	if not preserve:ui.hide();ui.queue_free();ui=null
func add_help(key: String,title: String,text: String) -> void:
	_help[key]={"title":title,"text":text}
	if is_instance_valid(ui):ui.add_help(key,title,text)
func remove_help(key: String) -> void:
	_help.erase(key)
	if is_instance_valid(ui):ui.remove_help(key)
func _create_ui(preview: bool) -> bool:
	if is_instance_valid(ui):return true
	if not ui_scene:return _fail("Assign a UI PackedScene.")
	var candidate: Node=ui_scene.instantiate()
	if not candidate is MjViewerUI:
		candidate.free();return _fail("UI scene root must extend MjViewerUI.")
	if preview:
		for window in candidate.find_children("*","Window",true,false):window.visible=false;window.force_native=false
	ui=candidate as MjViewerUI
	ui.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	if preview:ui.size=Vector2(1024,704)
	add_child(ui,false,Node.INTERNAL_MODE_BACK)
	ui.configure(self,ui_theme,preview)
	var error: String=ui.validate_scene()
	if not error.is_empty():ui.queue_free();ui=null;return _fail(error)
	if preview:return true
	ui.action_requested.connect(_on_ui_action)
	ui.layout_changed.connect(_on_layout_changed)
	ui.runtime_world=bound_world
	ui.visible=true
	for key in _help:
		var data: Dictionary=_help[key]
		ui.add_help(key,data.title,data.text)
	_register_existing_windows(ui)
	if not ui.render_region.gui_input.is_connected(_scene_input):ui.render_region.gui_input.connect(_scene_input)
	return true
func _frame_changed(packet: Dictionary) -> void:
	# Session emits a value copy. Editable/custom UI must never own its frozen data.
	if is_instance_valid(ui):
		ui.frame=packet
		if packet.has("inspect"):ui.details=packet.inspect
	if not _display_save_wait.is_empty() and is_instance_valid(_session):
		var frame: Dictionary=_session.frame
		if frame.get("space",-1)==_display_save_wait.space and frame.get("revision",-1)==_display_save_wait.revision and frame.get("frame_id",0)>_display_save_wait.after_frame:_display_save_wait.clear()
func _model_changing() -> void:
	if is_instance_valid(ui):ui.retire_model_controls();ui.retire_catalog_controls();ui.clear_sensor_images();ui.selected_image_sensor=-1;ui.catalog={};ui.details={}
	cancel_interaction();_preference_commands.clear();_display_save_wait.clear()
func _snapshot() -> Dictionary:
	var presentation := {"ready":is_instance_valid(_session) and not _layout_pending and not _session.frames_retiring and _session.presented_frame_id>0 and _session.presented_layout==_session.layout_generation,"region":_last_region}
	if is_instance_valid(_session):presentation.merge({"revision":_session.presented_revision,"frame_id":_session.presented_frame_id,"layout":_session.presented_layout,"generation":_session.layout_generation})
	return {"presentation":presentation,"status":status,"reason":last_error,"enabled":enabled,"frame":_session.frame.duplicate(true) if is_instance_valid(_session) else {},"catalog":_session.catalog.duplicate(true) if is_instance_valid(_session) else {},"details":_session.details.duplicate(true) if is_instance_valid(_session) else {},"backend":bound_world.rendering_status() if is_instance_valid(bound_world) else "","renderer_fps":_session.renderer_fps if is_instance_valid(_session) else 0.,"host_fps":_session.host_fps if is_instance_valid(_session) else 0.}
func action_allowed(action_id: StringName, arguments: Dictionary = {}) -> bool:return _action_rejection(action_id,arguments).is_empty()
func _action_rejection(action_id: StringName, arguments: Dictionary) -> String:
	if str(action_id) in ["controls","performance","metric","renderer","capture_snapshot","restore_snapshot","step"]:return "This action belongs to MjGodotExtras."
	if configuration and configuration.has_method("rejection_reason"):
		var reason: String=configuration.rejection_reason(action_id,arguments)
		if not reason.is_empty():return reason
		var normalized: Dictionary=configuration.normalize(action_id,arguments)
		reason=configuration.rejection_reason(normalized.action,normalized.arguments)
		if not reason.is_empty():return reason
	if _has_authored_theme() and action_id in [&"ui_color",&"ui_font",&"ui_spacing"]:return "Preset styling is controlled by the authored Theme resource."
	if is_instance_valid(ui) and not ui.provides_action(action_id):return "Current UI scene does not provide this presentation module: "+str(action_id)
	if is_instance_valid(_session) and action_id==&"group":
		for group in _session.catalog.get("groups",[]):
			if group.name==arguments.get("name","") and not group.get("supported",true):return group.get("reason","Current model does not support this display group.")
	if is_instance_valid(_session) and action_id==&"visual":
		for field in _session.catalog.get("visual",[]):
			if field.name==arguments.get("name","") and not field.get("supported",true):return field.get("reason","Visual option unavailable on this backend.")
	if is_instance_valid(_session) and action_id in [&"vis",&"rnd"] and arguments.has("id"):
		var flags: Array=_session.catalog.get(str(action_id),[]);var index: int=arguments.id
		if index>=0 and index<flags.size() and not flags[index].get("supported",true):return flags[index].get("reason","Display option unavailable on this backend.")
	return ""
func execute(action_id: StringName, arguments: Dictionary = {}) -> int:
	if status!="ACTIVE" or not enabled or not is_instance_valid(_session) or not is_instance_valid(bound_world) or not is_instance_valid(ui):last_error="UNAVAILABLE: component is disabled or unbound";return 0
	if _requests.size()+_operations.size()+(0 if _pending_reload.is_empty() else 1)>=64:last_error="Viewer request capacity reached; wait for pending results.";return 0
	last_error=_action_rejection(action_id,arguments)
	if _layout_pending and str(action_id) in ["select","move","perturb_begin"]:last_error="Display layout is changing; wait for the next presented frame."
	if not last_error.is_empty():ui.feedback=last_error;return 0
	var normalized: Dictionary=configuration.normalize(action_id,arguments)
	action_id=normalized.action
	var args: Dictionary=normalized.arguments
	match str(action_id):
		"help","info","profiler","sensors":
			var shown: bool=ui.windows.get(str(action_id),ui).visible
			ui.set_auxiliary(str(action_id),args.get("value",not shown));_update_inspection()
		"panels":ui.set_native_panels(args.get("left",true),args.get("right",true))
		"image_sensor":ui.selected_image_sensor=int(args.get("id",-1));ui.clear_sensor_images();ui.update_sensors()
		"watch":ui.watch_field=str(args.get("field",ui.watch_field));ui.watch_index=int(args.get("index",ui.watch_index));_update_inspection()
		"ui_color","ui_font","ui_spacing":ui.set(str(action_id),int(args.get("value",0)));ui.apply_ui_theme();save_view_preferences()
		"vsync":DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if args.get("value",true) else DisplayServer.VSYNC_DISABLED)
		"fullscreen":
			if ui.is_embedded_game():last_error="Embedded GameView fullscreen is managed by the editor.";ui.feedback=last_error;return 0
			get_window().mode=Window.MODE_FULLSCREEN if args.get("value",get_window().mode!=Window.MODE_FULLSCREEN) else Window.MODE_WINDOWED
		"reload":
			return _begin_reload()
		"quit":get_tree().quit()
		"screenshot":
			var id := _next_local;_next_local+=1;_operations[id]={"action":"screenshot"};_capture_screenshot(id);return id
		_:
			if str(action_id) in ["print_model","print_data","save_xml","save_mjb"] and not args.has("path"):
				var folder := output_directory()
				if folder.is_empty():return 0
				args.path=folder.path_join({"print_model":"MJMODEL.TXT","print_data":"MJDATA.TXT","save_xml":"mjmodel.xml","save_mjb":"mjmodel.mjb"}[str(action_id)])

			args.action=str(action_id)
			var request: int=_session.send(args)
			if request>0:_requests[request]=str(action_id)
			else:last_error="UNAVAILABLE: session has no current frame or its queue is full"
			return request
	var id := _next_local;_next_local+=1
	_remember_result(id,{"success":true,"action":str(action_id),"error":""})
	return id
func show_native_panels(left: bool,right: bool) -> bool:return execute("panels",{"left":left,"right":right})>0
func show_info(value: bool) -> bool:return execute("info",{"value":value})>0
func _camera_interaction_allowed() -> bool:
	for action_id in ["move","camera","cycle_camera","align"]:
		if action_allowed(action_id):return true
	return false
func _configuration_changed() -> void:
	if Engine.is_editor_hint() or _detaching:return
	cancel_interaction()
	if is_instance_valid(_session):_session.set_camera_control(_camera_interaction_allowed())
	if is_instance_valid(ui):
		if ui.use_default_presenters and not ui.catalog.is_empty():ui.build_catalog();ui.update_info()
		ui.refresh_help();_apply_policy()
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
	for key in ui.fields:
		var action_id := str(key).get_slice(":",0)
		if action_id not in ["joint","control","equality","vis","rnd","group"]:continue
		var node: Object=ui.fields[key]
		if not node is Control:continue
		var args := {}
		if str(key).contains(":") and str(key).get_slice(":",1).is_valid_int():args.id=int(str(key).get_slice(":",1))
		if action_id=="group":args={"name":str(key).get_slice(":",1),"id":int(str(key).get_slice(":",2))}
		var reason := _action_rejection(action_id,args)
		if action_id in ["joint","control"] and is_instance_valid(_session):
			for data in _session.details.get("joints" if action_id=="joint" else "controls",[]):
				if data.id==args.get("id",-1) and data.disabled:reason="Pause simulation to edit joints." if action_id=="joint" else "Actuator design group is disabled."
		var unavailable := bool(node.get_meta("viewer_capability_disabled",false)) or not reason.is_empty()
		if node is BaseButton:node.disabled=unavailable
		elif node is Range:node.editable=not unavailable
		if not reason.is_empty():node.tooltip_text=reason
func _update_inspection() -> void:
	if not is_instance_valid(_session) or not is_instance_valid(ui):return
	_session.inspection_options=ui.inspection_request()
	_session.inspection_options.sensors=_session.inspection_options.get("sensors",false) and action_allowed("sensors")
	_session.inspection_options.profiler=_session.inspection_options.get("profiler",false) and action_allowed("profiler")
func _on_layout_changed() -> void:
	if _setting_ui_bounds:return
	_layout_changed_frame=Engine.get_process_frames();_layout_ticks=0
	if _initializing_ui:_layout_pending=true;return
	# A child Control may report its new position before its Container has
	# applied the new size. Retire now; validate after the deferred layout pass.
	_invalidate_layout()
func _invalidate_layout() -> void:
	if not is_instance_valid(_session):return
	_layout_pending=true;cancel_interaction();_session.begin_frame_retirement()
func _update_layout() -> void:
	if _initializing_ui or _setting_ui_bounds:return
	if status!="ACTIVE" or not is_instance_valid(ui) or not is_instance_valid(_session):return
	var viewport: Viewport=bound_world.get_viewport()
	_target_rect=get_viewport().get_visible_rect()
	if viewport!=get_viewport() and viewport is SubViewport and viewport.get_parent() is SubViewportContainer:_target_rect=viewport.get_parent().get_global_rect()
	if ui.position!=_target_rect.position or ui.size!=_target_rect.size:
		_setting_ui_bounds=true;ui.position=_target_rect.position;ui.size=_target_rect.size;_setting_ui_bounds=false
		_layout_changed_frame=Engine.get_process_frames();_layout_ticks=0
		_invalidate_layout()
		# Container layout is deferred; do not validate its old rectangle against new bounds.
		return
	if Engine.get_process_frames()<=_layout_changed_frame:return
	var region := Rect2(ui.render_region.get_global_rect())
	if layout_mode==LayoutMode.OVERLAY:region=_target_rect
	if region.size.x<=0 or region.size.y<=0:
		if _layout_ticks>2:_detach_runtime();_fail("UI render_region must have a positive size.")
		return
	if not _target_rect.encloses(region):
		_detach_runtime();_fail("UI render_region must be a positive rectangle inside the target viewport.");return
	var scale := viewport.get_visible_rect().size/_target_rect.size
	var source := Rect2((region.position-_target_rect.position)*scale,region.size*scale)
	if source!=_last_region:_last_region=source;cancel_interaction();_session.set_region(source)
	_layout_changed_frame=-1
	_update_inspection()
func _input(event: InputEvent) -> void:global_input(event,get_viewport())
func _handle_global_input(event: InputEvent, viewport: Viewport) -> void:
	if status!="ACTIVE" or not enabled:return
	if event is InputEventMouseButton:
		if _dragging and (not event.pressed or viewport!=get_viewport()):cancel_interaction()
		if not event.pressed and viewport!=get_viewport():save_view_preferences()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode not in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_TAB]:return
		if event.get_instance_id()==_last_global_event:return
		_last_global_event=event.get_instance_id()
		if key_input(event):viewport.set_input_as_handled()
func _unhandled_input(event: InputEvent) -> void:
	# OVERLAY displays the complete target. Ordinary controls consume input first;
	# transparent space outside the authored render_region still belongs to 3D.
	if layout_mode!=LayoutMode.OVERLAY or status!="ACTIVE" or not enabled or not is_instance_valid(_session) or not is_instance_valid(bound_world) or not is_instance_valid(ui):return
	if not event is InputEventMouse or not _target_rect.has_point(event.position):return
	_scene_input(event.xformed_by(ui.render_region.get_global_transform_with_canvas().affine_inverse()))
	get_viewport().set_input_as_handled()
func _unhandled_key_input(event: InputEvent) -> void:
	if key_input(event):get_viewport().set_input_as_handled()
func _keyboard_scope() -> bool:
	if status!="ACTIVE" or not enabled or not is_instance_valid(bound_world) or not is_instance_valid(_session) or not is_instance_valid(ui):return false
	if _session.extras_has_focus():return true
	for popup in managed_popups:
		if is_instance_valid(popup) and popup.visible and popup.has_focus():return true
	return _owns_keyboard_scope()
func key_input(event: InputEvent) -> bool:
	if event.get_instance_id()==_last_key_event:return true
	var handled := _route_key(event)
	if handled:_last_key_event=event.get_instance_id()
	return handled
func _route_key(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo or not _keyboard_scope():return false
	if event.keycode in [KEY_F8,KEY_F9,KEY_F10,KEY_F12]:return false
	if _session.extras_has_focus() and event.keycode not in [KEY_F1,KEY_F2,KEY_F3,KEY_F4]:return false
	if event.keycode==KEY_TAB:
		if text_has_focus():return false
		var left: bool=is_instance_valid(ui.left_panel) and ui.left_panel.visible;var right: bool=is_instance_valid(ui.right_panel) and ui.right_panel.visible
		return show_native_panels(left,not right) if event.shift_pressed else show_native_panels(not left,right)
	if not event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6,KEY_F7] and text_has_focus():return false
	if event.ctrl_pressed or event.meta_pressed:
		if Keys.CTRL.has(event.keycode):return execute(Keys.CTRL[event.keycode],{"precise":event.shift_pressed})>0
		return false
	if event.alt_pressed and Keys.SECTIONS.has(event.keycode):
		if not action_allowed("panels"):return false
		var section: Dictionary=ui.sections.get(Keys.SECTIONS[event.keycode],{})
		if section.is_empty():return false
		section.button.button_pressed=not section.button.button_pressed
		if section.panel.visible:section.panel.ensure_control_visible(section.button)
		return true
	for row in Keys.ACTIONS:
		if event.keycode==row[0]:
			if row[1] in ["slower","faster"] and event.shift_pressed:return false
			return execute(row[1])>0
	if event.keycode>=KEY_0 and event.keycode<=KEY_5:return execute("group",{"name":"site" if event.shift_pressed else "geom","id":event.keycode-KEY_0})>0
	for action_id in ["vis","rnd"]:
		for flag in _session.catalog.get(action_id,[]):
			if flag.supported and not str(flag.shortcut).is_empty() and event.keycode==str(flag.shortcut).unicode_at(0):return execute(action_id,{"id":flag.id})>0
	return false
func _scene_input(event: InputEvent) -> void:
	if status!="ACTIVE" or not enabled or not is_instance_valid(_session) or not is_instance_valid(ui):return
	ui.render_region.accept_event()
	var rect: Rect2=_target_rect if layout_mode==LayoutMode.OVERLAY else ui.render_region.get_global_rect()
	var position: Vector2 = ui.render_region.get_global_transform_with_canvas()*event.position if event is InputEventMouse else Vector2.ZERO
	var height := maxf(rect.size.y,1)
	if event is InputEventMouseButton:
		get_window().set_meta("mj_viewer_keyboard_owner",self)
		var logical: int=event.button_index
		if event.alt_pressed:
			if logical==MOUSE_BUTTON_LEFT:logical=MOUSE_BUTTON_RIGHT
			elif logical==MOUSE_BUTTON_RIGHT:logical=MOUSE_BUTTON_LEFT
		if logical in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:execute("move",{"mouse":5,"dx":0.,"dy":-.02 if logical==MOUSE_BUTTON_WHEEL_UP else .02,"perturb":false});return
		if not logical in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:return
		if not event.pressed:cancel_interaction();return
		var now := Time.get_ticks_msec();var double_click: bool=logical==_last_click_button and now-_last_click<250
		_last_click=now;_last_click_button=logical
		if double_click:execute("select",{"button":logical,"x":(position.x-rect.position.x)/maxf(rect.size.x,1),"y":1-(position.y-rect.position.y)/height,"aspect":_last_region.size.x/maxf(_last_region.size.y,1),"control":event.ctrl_pressed});return
		var perturb: bool=event.ctrl_pressed and logical in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]
		if not action_allowed("perturb_begin") and perturb or not action_allowed("move") and not perturb:return
		_dragging=true;_perturbing=perturb;_logical_button=logical
		if perturb:execute("perturb_begin",{"mode":1 if logical==MOUSE_BUTTON_RIGHT else 2})
	elif event is InputEventMouseMotion and _dragging:
		var mouse := 5
		if _logical_button==MOUSE_BUTTON_LEFT:mouse=2 if event.shift_pressed else 1
		elif _logical_button==MOUSE_BUTTON_RIGHT:mouse=4 if event.shift_pressed else 3
		var relative: Vector2=ui.render_region.get_global_transform_with_canvas().basis_xform(event.relative)
		execute("move",{"mouse":mouse,"dx":relative.x/height,"dy":relative.y/height,"perturb":_perturbing})
func cancel_interaction() -> void:
	_dragging=false;_perturbing=false
	if is_instance_valid(_session):_session.cancel_gesture()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_WM_WINDOW_FOCUS_OUT] and not Engine.is_editor_hint():cancel_interaction()
func output_directory() -> String:
	var base: String=output_path if is_instance_valid(ui) else "user://mujoco_viewer"
	var folder := base.path_join(Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_msec()))
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:last_error="Cannot create output directory: "+folder;return ""
	return folder
func _capture_screenshot(id: int) -> void:
	var folder := output_directory()
	if folder.is_empty():_finish_operation(id,{"success":false,"error":last_error});return
	await RenderingServer.frame_post_draw
	if not _operations.has(id) or not is_inside_tree():return
	var path := folder.path_join("screenshot.png")
	var error := get_tree().root.get_texture().get_image().save_png(path)
	var message := "" if error==OK else "Screenshot write failed: "+path
	if is_instance_valid(ui):ui.feedback="截图："+path if error==OK else message
	_finish_operation(id,{"success":error==OK,"error":message,"path":path})
func _load_preferences() -> void:
	if _preferences_loaded or not is_instance_valid(ui):return
	_display_restore_pending=false;_display_restore_revision=-1;_preference_commands.clear()
	_preferences_loaded=true
	var scene: Node=get_tree().current_scene
	if not scene:
		scene=get_parent()
		while scene.get_parent() and scene.scene_file_path.is_empty():scene=scene.get_parent()
	var identity := preferences_id if not preferences_id.is_empty() else scene.scene_file_path+"::"+str(scene.get_path_to(self))
	_preference_registry_key=ProjectSettings.globalize_path("res://")+"::original::"+identity
	var registry: Dictionary=get_tree().root.get_meta("mj_viewer_preference_ids",{})
	var existing: WeakRef=registry.get(_preference_registry_key)
	if existing and is_instance_valid(existing.get_ref()) and existing.get_ref()!=self:
		_preferences_enabled=false;ui.feedback="Duplicate viewer preferences_id; personal state will not be shared.";return
	registry[_preference_registry_key]=weakref(self);get_tree().root.set_meta("mj_viewer_preference_ids",registry)
	_config_path="user://mujoco_components/"+_preference_registry_key.sha256_text().substr(0,24)+".cfg"
	if not restore_preferences or _config.load(_config_path)!=OK:return
	if _preference_allowed("visibility"):
		ui.set_native_panels(_config.get_value("view","left",true),_config.get_value("view","right",true));ui.set_info(_config.get_value("view","info",false) and action_allowed("info"))
		for title in ui.sections:ui.sections[title].button.button_pressed=_config.get_value("expanded",title,ui.sections[title].button.button_pressed)
	if _preference_allowed("style") and not _has_authored_theme():
		for field in ["ui_spacing","ui_color","ui_font"]:
			if action_allowed(field):ui.set(field,_config.get_value("style",field,ui.get(field)))
		ui.apply_ui_theme()
	if _preference_allowed("output"):output_path=_config.get_value("view","output",output_path)
	if _preference_allowed("display"):_display_restore_pending=true;call_deferred("_restore_display_preferences")
func _restore_display_preferences() -> void:
	_preference_commands.clear()
	if not restore_preferences or not _preferences_enabled or not _preference_allowed("display"):
		_display_restore_pending=false;_display_restore_revision=-1;return
	if not is_instance_valid(_session) or _session.catalog.is_empty() or _session.frame.is_empty():return
	_display_restore_pending=false;_display_restore_revision=int(_session.frame.revision)
	var settings: Dictionary=_config.get_value("display","settings",{})
	for action_id in ["vis","rnd"]:
		for flag in _session.catalog.get(action_id,[]):
			if flag.supported and int(flag.id)<settings.get(action_id,[]).size():_preference_commands.append({"action":action_id,"id":flag.id,"value":settings[action_id][flag.id]})
	for group_name in settings.get("groups",{}):
		for i in mini(6,settings.groups[group_name].size()):_preference_commands.append({"action":"group","name":group_name,"id":i,"value":settings.groups[group_name][i]})
	for action_id in ["frame","label"]:
		if settings.has(action_id):_preference_commands.append({"action":action_id,"value":settings[action_id]})
	if settings.has("bvh_depth"):_preference_commands.append({"action":"tree_depth","value":settings.bvh_depth})
	for field in settings.get("visual",[]):
		if field.name in ["global.fovy","global.orthographic","global.azimuth","global.elevation","stat.center","stat.extent","map.znear","map.zfar"]:continue
		if not _session.catalog.get("visual",[]).filter(func(candidate):return candidate.name==field.name and candidate.get("supported",true)).is_empty():_preference_commands.append({"action":"visual","name":field.name,"values":field.values})
func save_view_preferences(immediate := false) -> void:
	if Engine.is_editor_hint() or not _preferences_enabled or _config_path.is_empty() or not is_instance_valid(ui):return
	if not immediate:_save_due=Time.get_ticks_msec()+1000;return
	_save_due=0
	if _preference_allowed("visibility"):
		_config.set_value("view","left",is_instance_valid(ui.left_panel) and ui.left_panel.visible);_config.set_value("view","right",is_instance_valid(ui.right_panel) and ui.right_panel.visible);_config.set_value("view","info",ui.info_enabled)
		for title in ui.sections:_config.set_value("expanded",title,ui.sections[title].button.button_pressed)
	if _preference_allowed("style") and not _has_authored_theme():
		for field in ["ui_spacing","ui_color","ui_font"]:_config.set_value("style",field,ui.get(field))
	if _preference_allowed("output"):_config.set_value("view","output",output_path)
	if _preference_allowed("display") and _display_save_wait.is_empty() and is_instance_valid(_session) and _session.frame.has("settings"):_config.set_value("display","settings",_session.frame.settings)
	DirAccess.make_dir_recursive_absolute("user://mujoco_components")
	if _config.save(_config_path)!=OK:last_error="Cannot save viewer preferences."

func _process_active() -> void:
	_layout_ticks+=1
	_update_layout()
	if status!="ACTIVE":return
	if _layout_pending and _layout_changed_frame<0 and not _session.frames_retiring and _session.presented_frame_id>0 and _session.presented_layout==_session.layout_generation:_layout_pending=false
	var now := Time.get_ticks_msec()
	if now>=_next_info:
		_next_info=now+200
		ui.apply_snapshot(_snapshot())
		_apply_policy()
		_update_inspection()
	if not restore_preferences or not _preferences_enabled or not _preference_allowed("display"):
		_display_restore_pending=false;_preference_commands.clear()
	elif _display_restore_pending and not _session.catalog.is_empty() and not _session.frame.is_empty():_restore_display_preferences()
	if not _preference_commands.is_empty() and not _session.frame.is_empty() and _requests.size()<24:
		for unused in mini(8,_preference_commands.size()):
			var command: Dictionary=_preference_commands.pop_front();var action_id := str(command.action);command.erase("action")
			if not action_allowed(action_id,command):continue
			if execute(action_id,command)==0:
				_preference_commands.push_front({"action":action_id}.merged(command));break
	if _save_due>0 and now>=_save_due:save_view_preferences(true)
func _on_result(action_id: String,result: Dictionary) -> void:
	if is_instance_valid(ui):
		if not result.get("success",false):last_error=result.get("error","");ui.feedback=last_error
		if result.get("success",false) and result.has("text") and action_id in ["copy_state","copy_camera"]:
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):DisplayServer.clipboard_set(str(result.text));ui.feedback="已复制到剪贴板"
			else:ui.feedback="当前显示后端没有剪贴板；结果文本可从动作结果读取。"
		elif result.get("success",false) and result.has("path"):ui.feedback="已输出："+str(result.path)
	if result.get("success",false) and action_id in ["vis","rnd","visual","frame","label","group","tree_depth"] and is_instance_valid(_session) and not _session.frame.is_empty():
		_display_save_wait={"space":_session.frame.space,"revision":_session.frame.revision,"after_frame":_session.frame.frame_id};_save_due=Time.get_ticks_msec()+1000

func _cancel_owned_interaction() -> void:cancel_interaction()

func _component_name() -> String:return "MjRuntimeViewer"
