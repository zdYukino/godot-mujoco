@tool
@abstract
class_name MjRuntimeUiClient
extends CanvasLayer
## Internal lifetime and command owner shared by the two optional UI components.
signal target_changed(world: Node3D)
signal action_finished(request_id: int, result: Dictionary)
const Configuration = preload("configuration.gd")
@export var enabled := true:
	set(value):
		if enabled==value:return
		enabled=value
		if is_inside_tree() and not Engine.is_editor_hint():
			if not value:_detach_runtime()
			_refresh.call_deferred()
@export var world: Node3D:
	set(value):
		if world==value:return
		world=value;_target_edited()
@export var environment_host: Node:
	set(value):
		if environment_host==value:return
		environment_host=value;_target_edited()
@export var ui_scene: PackedScene
@export var ui_theme: Theme
@export var configuration: Configuration = Configuration.new():
	set(value):
		if configuration and configuration.changed.is_connected(_configuration_changed):configuration.changed.disconnect(_configuration_changed)
		configuration=value if value!=null else Configuration.new()
		if is_inside_tree():configuration.changed.connect(_configuration_changed);_configuration_changed()
@export var preview_in_editor := true
@export var restore_preferences := true
@export var preferences_id := ""
var ui
var bound_world: Node3D
var status := "UNBOUND"
var last_error := ""
var _session: Node
var _host: Node
var _observed_world: Node3D
var _requests := {}
var _results := {}
var _next_local := 1<<60
var managed_popups: Array[Window] = []
var _last_global_event := 0
var _target_rect := Rect2()
var _last_key_event := 0
var _next_info := 0
var _config := ConfigFile.new()
var _config_path := ""
var _preferences_loaded := false
var _preferences_enabled := true
var _preference_registry_key := ""
var _save_due := 0
var _refresh_queued := false
var _suspend_target_edits := false
var _pending_reload := {}
var _cancelling_reload := false
var _deferred_reload_result := {}
var _operations := {}
var _initializing_ui := false
var _detaching := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	set_process_input(false);set_process_unhandled_input(false);set_process_unhandled_key_input(false)
	if configuration==null:configuration=Configuration.new()
	if configuration.has_signal("changed") and not configuration.changed.is_connected(_configuration_changed):configuration.changed.connect(_configuration_changed)
	if Engine.is_editor_hint():
		if preview_in_editor:_create_ui(true)
		return
	get_tree().node_added.connect(_owned_window_added)
	_observe_authored_world()
	_refresh()
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if world==null and environment_host==null:warnings.append("Assign an explicit MjRuntimeWorld or EnvironmentHost target.")
	if world!=null and environment_host!=null:warnings.append("Choose one target: World or EnvironmentHost, not both.")
	if ui_scene==null:warnings.append("Assign the component UI PackedScene.")
	return warnings
func _target_edited() -> void:
	if not is_inside_tree() or _suspend_target_edits:return
	update_configuration_warnings()
	if Engine.is_editor_hint():return
	_observe_authored_world()
	_detach_runtime(true,true);_refresh.call_deferred()
func _fail(reason: String) -> bool:
	if last_error!=reason:push_error(_component_name()+": "+reason)
	last_error=reason;status="CONFIGURATION_ERROR";set_process_input(false);set_process_unhandled_input(false);set_process_unhandled_key_input(false)
	return false
func _refresh() -> void:
	if Engine.is_editor_hint() or not is_inside_tree():return
	_refresh_queued=false
	if not enabled:status="DISABLED";last_error="";return
	var has_world := is_instance_valid(world)
	var has_host := is_instance_valid(environment_host)
	if has_world and has_host:_fail("Choose one explicit World or EnvironmentHost target.");return
	if not has_world and not has_host:status="UNBOUND";last_error="Assign an explicit World or EnvironmentHost target.";return
	var target: Node3D=world if has_world else null
	if is_instance_valid(environment_host):
		if not environment_host.has_signal("world_committed"):_fail("Target is not an EnvironmentHost.");return
		if _host!=environment_host:
			_disconnect_host();_host=environment_host;_host.world_committed.connect(_host_committed)
		target=environment_host.get("world") as Node3D
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():status="WAITING_FOR_WORLD";last_error="Waiting for committed environment.";return
	if not target.has_method("_ensure_view_session"):_fail("Target is not an MjRuntimeWorld.");return
	if not target.get("ready_for_models") or not target.get("author_started"):status="WAITING_FOR_WORLD";last_error="Waiting for compiled runtime world.";return
	if bound_world==target and is_instance_valid(_session):return
	bound_world=target
	_session=target.call("_ensure_view_session")
	var error: String=_attach_session()
	if not error.is_empty():_session=null;bound_world=null;_fail(error);return
	bound_world.tree_exiting.connect(_bound_world_exiting.bind(bound_world))
	_session.result_finished.connect(_session_result)
	_session.frame_changed.connect(_frame_changed)
	_session.model_changing.connect(_model_changing)
	if not _create_ui(false):
		var reason := last_error;_detach_runtime(false);_fail(reason);return
	_initializing_ui=true
	ui.runtime_world=target;status="ACTIVE";last_error=""
	_prepare_component()
	_load_preferences()
	_initializing_ui=false
	set_process_input(true);set_process_unhandled_input(true);set_process_unhandled_key_input(true)
	_activate_component()
	if status!="ACTIVE":return
	_frame_changed(_session.frame.duplicate(true))
	target_changed.emit(target)
func _bound_world_exiting(target: Node3D) -> void:
	if target!=bound_world:return
	_target_lost()
func _target_lost() -> void:
	_detach_runtime(false)
	status="WAITING_FOR_WORLD" if is_instance_valid(environment_host) else "UNBOUND"
	last_error="Waiting for committed environment." if is_instance_valid(environment_host) else "Target World left the scene tree."
func _disconnect_host() -> void:
	if is_instance_valid(_host) and _host.world_committed.is_connected(_host_committed):_host.world_committed.disconnect(_host_committed)
	_host=null
func _host_committed(target: Node3D) -> void:
	if target==bound_world:return
	_detach_runtime(false,true,not _pending_reload.is_empty() and _pending_reload.source==_host)
	_refresh()
func _target_replaced(_target: Node3D, host: Node) -> void:
	var preserve_reload: bool=not _pending_reload.is_empty() and _pending_reload.source==_session
	_detach_runtime(false,true,preserve_reload)
	_suspend_target_edits=true;world=null;environment_host=host;_suspend_target_edits=false
	_observe_authored_world()
	_refresh()
func _detach_runtime(disconnect_host := true, preserve_ui := false, preserve_reload := false) -> void:
	if Engine.is_editor_hint() or _detaching:return
	_detaching=true
	status="DISABLED" if not enabled else "UNBOUND"
	_cancel_owned_interaction()
	if not preserve_reload:_cancel_reload()
	for id in _operations.keys():_finish_operation(id,{"success":false,"error":"Component target changed or disabled","cancelled":true})
	if is_instance_valid(ui):save_view_preferences(true);_detach_ui(preserve_ui)
	for popup in managed_popups.duplicate():
		if is_instance_valid(popup):popup.hide()
	if is_instance_valid(bound_world):
		var exiting := _bound_world_exiting.bind(bound_world)
		if bound_world.tree_exiting.is_connected(exiting):bound_world.tree_exiting.disconnect(exiting)
	if is_instance_valid(_session):
		_session.cancel_requests(_requests.keys())
		for row in [["result_finished",_session_result],["frame_changed",_frame_changed],["model_changing",_model_changing]]:
			if _session.is_connected(row[0],row[1]):_session.disconnect(row[0],row[1])
		_detach_session()
	for request in _requests.keys():_remember_result(request,{"success":false,"error":"Component target changed or disabled","cancelled":true})
	_requests.clear();_reset_component()
	_session=null;bound_world=null;_preferences_loaded=false;_save_due=0
	set_process_input(false);set_process_unhandled_input(false);set_process_unhandled_key_input(false)
	if disconnect_host:_disconnect_host()
	if get_window().has_meta("mj_viewer_keyboard_owner") and get_window().get_meta("mj_viewer_keyboard_owner")==self:get_window().remove_meta("mj_viewer_keyboard_owner")
	status="DISABLED" if not enabled else "UNBOUND"
	_detaching=false
func _session_result(id: int, result: Dictionary) -> void:
	if not _requests.has(id):return
	var action_id: String=_requests[id];_requests.erase(id)
	_remember_result(id,result)
	_on_result(action_id,result)
func _remember_result(id: int, value: Dictionary) -> void:
	var result := value.duplicate(true);result.request_id=id;_results[id]=result
	while _results.size()>128:_results.erase(_results.keys()[0])
	action_finished.emit(id,result.duplicate(true))
func action_result(request_id: int) -> Dictionary:return _results.get(request_id,{}).duplicate(true)
func read_state() -> Dictionary:
	return _snapshot()
func _begin_reload() -> int:
	if not _pending_reload.is_empty():last_error="Reload already pending";return 0
	cancel_interaction()
	var source: Node=environment_host if is_instance_valid(environment_host) else _session
	var signal_name := "rebuild_finished" if source==environment_host else "reload_finished"
	var id := _next_local;_next_local+=1
	_pending_reload={"id":id,"source":source,"signal":signal_name,"world":bound_world,"host":environment_host}
	_deferred_reload_result.clear()
	source.connect(signal_name,_reload_finished)
	if signal_name=="reload_finished":source.target_replaced.connect(_reload_target_replaced)
	var accepted: bool=source.request_rebuild_environment(true) if source==environment_host else source.reload_saved()
	if not accepted:
		last_error=str(source.get("last_error"))
		var rejected: Dictionary=_pending_reload;_pending_reload={};_deferred_reload_result.clear()
		_disconnect_reload_operation(rejected)
		return 0
	return id
func _reload_finished(success: bool,error: String) -> void:
	if _pending_reload.is_empty():return
	if _cancelling_reload:
		_deferred_reload_result={"success":success,"error":error};return
	var operation := _pending_reload;_pending_reload={}
	_disconnect_reload_operation(operation)
	last_error=error if not success else ""
	if is_instance_valid(ui):ui.feedback="已重载最后保存的设计" if success else "重载失败，保留原世界："+error
	_remember_result(operation.id,{"success":success,"error":error,"action":"reload"})
func _reload_target_replaced(_target: Node3D,host: Node) -> void:
	if _pending_reload.is_empty():return
	var operation: Dictionary=_pending_reload
	if world!=operation.world or environment_host!=operation.host:return
	# The active binding handler owns normal replacement. This operation-only
	# listener survives disable, but never overrides an explicit later retarget.
	if _session==operation.source:return
	_suspend_target_edits=true;world=null;environment_host=host;_suspend_target_edits=false
	if enabled:_refresh()
func _disconnect_reload_operation(operation: Dictionary) -> void:
	if not is_instance_valid(operation.source):return
	if operation.source.is_connected(operation.signal,_reload_finished):operation.source.disconnect(operation.signal,_reload_finished)
	if operation.signal=="reload_finished" and operation.source.target_replaced.is_connected(_reload_target_replaced):operation.source.target_replaced.disconnect(_reload_target_replaced)
func _cancel_reload() -> void:
	if _pending_reload.is_empty() or _cancelling_reload:return
	var operation := _pending_reload
	var transaction_cancelled := false
	_cancelling_reload=true
	if is_instance_valid(operation.source):
		transaction_cancelled=operation.source.cancel_rebuild_environment() if operation.signal=="rebuild_finished" else operation.source.cancel_reload()
	_cancelling_reload=false
	if transaction_cancelled or not is_instance_valid(operation.source):
		_pending_reload={};_deferred_reload_result.clear();_disconnect_reload_operation(operation)
		_remember_result(operation.id,{"success":false,"error":"Reload request cancelled by component target/lifetime change","cancelled":true,"transaction_cancelled":transaction_cancelled,"action":"reload"})
	elif not _deferred_reload_result.is_empty():
		var result: Dictionary=_deferred_reload_result;_deferred_reload_result={}
		_reload_finished(result.success,result.error)
	# A committed transaction is irreversible. Keep its completion and target
	# subscription so a disabled component reports reality and can re-enable.
func _on_ui_action(action_id: StringName, arguments: Dictionary) -> void:execute(action_id,arguments)
func _has_authored_theme() -> bool:return ui_theme!=null or is_instance_valid(ui) and ui.authored_theme!=null
func _finish_operation(id: int,result: Dictionary) -> void:
	if not _operations.has(id):return
	var operation: Dictionary=_operations[id];_operations.erase(id)
	result.action=operation.action
	if not result.get("success",false):last_error=str(result.get("error",""))
	_remember_result(id,result)
func _owned_window_added(node: Node) -> void:
	if node is Window and is_ancestor_of(node) and is_instance_valid(ui):manage_popup(node)
func manage_popup(popup: Window) -> void:
	if Engine.is_editor_hint() or not is_ancestor_of(popup):return
	if not managed_popups.has(popup):managed_popups.append(popup)
	var input := _popup_input.bind(popup)
	if not popup.window_input.is_connected(input):popup.window_input.connect(input)
	var exiting := _popup_exiting.bind(popup)
	if not popup.tree_exiting.is_connected(exiting):popup.tree_exiting.connect(exiting)
	if is_instance_valid(ui):ui.managed_popups=managed_popups
func _popup_input(event: InputEvent,popup: Window) -> void:
	if is_inside_tree() and is_instance_valid(popup) and is_ancestor_of(popup):global_input(event,popup)
func _popup_exiting(popup: Window) -> void:managed_popups.erase(popup)
func text_has_focus() -> bool:
	for viewport in [get_viewport()]+managed_popups:
		if not is_instance_valid(viewport) or viewport is Window and not viewport.visible:continue
		var focus: Control=viewport.gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:return true
	return false
func _preference_allowed(category: String) -> bool:return configuration==null or not configuration.has_method("allows_preference") or configuration.allows_preference(category)
func _exit_tree() -> void:
	if Engine.is_editor_hint():return
	_disconnect_observed_world()
	_detach_runtime()
	if get_tree().node_added.is_connected(_owned_window_added):get_tree().node_added.disconnect(_owned_window_added)
	if not _preference_registry_key.is_empty():
		var registry: Dictionary=get_tree().root.get_meta("mj_viewer_preference_ids",{});var ref: WeakRef=registry.get(_preference_registry_key)
		if ref and ref.get_ref()==self:registry.erase(_preference_registry_key)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():return
	if enabled and status in ["WAITING_FOR_WORLD","UNBOUND"]:_refresh()
	if status!="ACTIVE":return
	if not is_instance_valid(_session) or not is_instance_valid(bound_world) or not bound_world.is_inside_tree():_target_lost();return
	if not is_instance_valid(ui):
		_detach_runtime(false);_fail("The configured UI instance left the scene tree.");return
	_process_active()
	if _save_due>0 and Time.get_ticks_msec()>=_save_due:save_view_preferences(true)
func _register_existing_windows(node: Node) -> void:
	var nodes: Array[Node]=[node]
	while not nodes.is_empty():
		var current: Node=nodes.pop_back();_owned_window_added(current);nodes.append_array(current.get_children(true))
func _on_result(_action: String,_result: Dictionary) -> void:pass
func _prepare_component() -> void:pass
func _activate_component() -> void:pass
func _reset_component() -> void:pass
func _attach_session() -> String:return "No client role configured"
func _detach_session() -> void:pass
func _detach_ui(_preserve: bool) -> void:pass
func _create_ui(_preview: bool) -> bool:return false
func _process_active() -> void:pass
func _configuration_changed() -> void:pass
func _load_preferences() -> void:pass
func save_view_preferences(_immediate := false) -> void:pass
func cancel_interaction() -> void:pass
func _owns_keyboard_scope() -> bool:
	var owner: Variant=get_window().get_meta("mj_viewer_keyboard_owner") if get_window().has_meta("mj_viewer_keyboard_owner") else null
	if is_instance_valid(owner) and owner is MjRuntimeUiClient and owner.enabled and owner.status=="ACTIVE":
		return owner==self or owner==_session.consumer or owner==_session.extras_client
	return bound_world.get_viewport()==get_viewport() or _target_rect.has_point(get_viewport().get_mouse_position())
func global_input(event: InputEvent,viewport: Viewport) -> void:
	# All owned embedded Windows share the same role pair. Dispatch once per role
	# (the role guards event IDs), including releases that cross UI viewports.
	if not is_instance_valid(_session):return
	if viewport==get_viewport() and event is InputEventMouseButton and event.pressed and _target_rect.has_point(event.position):
		get_window().set_meta("mj_viewer_keyboard_owner",self)
	for client in [_session.consumer,_session.extras_client]:
		if is_instance_valid(client):client._handle_global_input(event,viewport)
func _handle_global_input(_event: InputEvent,_viewport: Viewport) -> void:pass
func _component_name() -> String:return "MuJoCo runtime component"
func _frame_changed(_packet: Dictionary) -> void:pass
func _model_changing() -> void:pass
func _snapshot() -> Dictionary:return {}
func execute(_action_id: StringName,_arguments: Dictionary = {}) -> int:return 0
func _cancel_owned_interaction() -> void:pass

func _disconnect_observed_world() -> void:
	if is_instance_valid(_observed_world) and _observed_world.is_connected("runtime_replaced",_authored_world_replaced):_observed_world.disconnect("runtime_replaced",_authored_world_replaced)
	_observed_world=null
func _observe_authored_world() -> void:
	_disconnect_observed_world()
	if is_instance_valid(environment_host) or not is_instance_valid(world) or not world.has_signal("runtime_replaced"):return
	_observed_world=world
	_observed_world.connect("runtime_replaced",_authored_world_replaced)
func _authored_world_replaced(target: Node3D,host: Node) -> void:
	if not is_instance_valid(_observed_world) or world!=_observed_world or is_instance_valid(environment_host):return
	# Disabled components follow their explicit authored target without attaching
	# a session, UI, camera, sampler or command consumer.
	_target_replaced(target,host)
