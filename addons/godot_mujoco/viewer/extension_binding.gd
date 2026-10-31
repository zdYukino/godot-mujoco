@tool
@icon("res://addons/godot_mujoco/icons/mj_viewer_binding.svg")
class_name MjViewerExtensionBinding
extends Node
## Optional explicit routes: original F1 help and Godot F11 widgets are independent.
@export var viewer: CanvasLayer:
	set(value):
		viewer=value
		_schedule_refresh()
@export var extras: CanvasLayer:
	set(value):
		extras=value
		_schedule_refresh()
## Relative to each destination's committed World; never relative to this node.
@export var provider_path := NodePath(""):
	set(value):
		provider_path=value
		_schedule_refresh()
var _routes: Array[Dictionary]=[]
var _refresh_queued := false

func _schedule_refresh() -> void:
	if not is_inside_tree():return
	if Engine.is_editor_hint():update_configuration_warnings()
	elif not _refresh_queued:
		_refresh_queued=true;_refresh.call_deferred()

func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not is_instance_valid(viewer) and not is_instance_valid(extras):
		warnings.append("Assign a RuntimeViewer for F1 help, GodotExtras for F11 tools, or both.")
	if is_instance_valid(viewer) and not viewer.has_method("add_help"):
		warnings.append("Viewer must be an explicit MjRuntimeViewer component.")
	if is_instance_valid(extras) and not extras.has_method("add_extension"):
		warnings.append("Extras must be an explicit MjGodotExtras component.")
	if provider_path.is_empty() or provider_path.is_absolute():
		warnings.append("Set Provider Path relative to the committed World, for example DisplayControls or .")
	return warnings

func _ready() -> void:
	if not Engine.is_editor_hint():_refresh()

func _destination(role: String) -> Node:
	# Exported references can retain a freed object until the author reassigns
	# the target. Validate before converting it to a typed local/return value.
	if role=="help":return viewer if is_instance_valid(viewer) else null
	return extras if is_instance_valid(extras) else null

func _refresh() -> void:
	_refresh_queued=false
	if not is_inside_tree():return
	for route in _routes.duplicate():
		var destination: Node=_destination(route.role)
		if route.destination!=destination or route.path!=provider_path:
			_disconnect_route(route);_routes.erase(route)
	if provider_path.is_empty() or provider_path.is_absolute():
		_disconnect_routes()
		push_error("ExtensionBinding needs a relative Provider Path")
		return
	for role in ["help","tools"]:
		var destination: Node=_destination(role)
		if not is_instance_valid(destination):continue
		if _routes.any(func(route):return route.role==role):continue
		var method := "add_help" if role=="help" else "add_extension"
		if not destination.has_signal("target_changed") or not destination.has_method(method):
			push_error("ExtensionBinding has an invalid "+role+" destination")
			continue
		var route := {"destination":destination,"role":role,"key":"","path":provider_path}
		var callback := func(target: Node3D):_bind_provider(target,route)
		route.callback=callback
		_routes.append(route)
		destination.connect("target_changed",callback)
		var target: Node3D=destination.get("bound_world")
		if is_instance_valid(target):_bind_provider(target,route)

func _remove_content(route: Dictionary) -> void:
	var destination: Node=route.destination if is_instance_valid(route.destination) else null
	if is_instance_valid(destination) and not str(route.key).is_empty():
		destination.call("remove_help" if route.role=="help" else "remove_extension",route.key)
	route.key=""

func _bind_provider(target: Node3D, route: Dictionary) -> void:
	_remove_content(route)
	if not is_instance_valid(target) or not is_instance_valid(route.destination):return
	var provider := target.get_node_or_null(provider_path)
	var method := "get_viewer_help" if route.role=="help" else "register_extras"
	if not is_instance_valid(provider) or not provider.has_method(method):
		push_error("Extension provider must implement "+method+": "+str(provider_path))
		return
	if route.role=="help":
		var content: Variant=provider.call(method)
		if not content is Dictionary or str(content.get("key","")).is_empty():
			push_error("get_viewer_help must return key, title and text")
			return
		route.key=str(content.key)
		route.destination.call("add_help",route.key,str(content.get("title","")),str(content.get("text","")))
	else:
		var key: Variant=provider.call(method,route.destination)
		if not key is String or key.is_empty():
			push_error("register_extras must return its registered extension key")
			return
		route.key=key

func _disconnect_route(route: Dictionary) -> void:
	_remove_content(route)
	var destination: Node=route.destination if is_instance_valid(route.destination) else null
	if is_instance_valid(destination) and destination.is_connected("target_changed",route.callback):
		destination.disconnect("target_changed",route.callback)

func _disconnect_routes() -> void:
	for route in _routes:_disconnect_route(route)
	_routes.clear()

func _exit_tree() -> void:
	if not Engine.is_editor_hint():_disconnect_routes()
