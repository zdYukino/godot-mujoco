class_name MjEnvironmentHost
extends SubViewportContainer
## Owns a saved environment independently of game UI/input. Rebuild discards runtime additions.
signal rebuild_finished(success: bool, error: String)
@export var environment_scene: PackedScene
var world: MjRuntimeWorld
var active_viewport: SubViewport
var rebuilding := false
var last_error := ""

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	stretch=true
	request_rebuild_environment(true)

func request_rebuild_environment(discard_runtime_changes: bool) -> bool:
	if not discard_runtime_changes:
		last_error="Environment rebuild discards runtime changes; use world.reset_simulation() to keep them"
		return false
	if rebuilding:
		last_error="Environment rebuild already pending"
		return false
	rebuilding=true
	call_deferred("rebuild_environment")
	return true

func validate_models(node: Node) -> String:
	if node is MjRuntimeWorld:
		if not node.world_model: return "Environment has no world_model"
		var error: String=node.world_model.validate_package()
		if not error.is_empty(): return error
	if node is MjModelInstance:
		if not node.model: return "Environment model instance has no resource"
		var error: String=node.model.validate_package()
		if not error.is_empty(): return error
	for child in node.get_children():
		var error := validate_models(child)
		if not error.is_empty(): return error
	return ""

func loaded_models(node: Node) -> String:
	if node is MjModelInstance and not node.model_rid.is_valid(): return node.last_error
	for child in node.get_children():
		var error := loaded_models(child)
		if not error.is_empty(): return error
	return ""

func rebuild_environment() -> void:
	last_error=""
	var scene := environment_scene
	if scene and not scene.resource_path.is_empty() and not scene.resource_path.contains("::"):
		scene=ResourceLoader.load(scene.resource_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE)
	var candidate: Node=scene.instantiate() if scene else null
	if not candidate is MjRuntimeWorld:
		last_error="Saved environment root must be MjRuntimeWorld"
	else:
		last_error=validate_models(candidate)
	if not last_error.is_empty():
		if candidate: candidate.free()
		rebuilding=false
		rebuild_finished.emit(false,last_error)
		return
	var running: bool = not world.info().paused if is_instance_valid(world) else not candidate.start_paused
	candidate.start_paused=true
	var viewport := SubViewport.new()
	viewport.own_world_3d=true
	viewport.size=Vector2i(maxf(size.x,1),maxf(size.y,1))
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(candidate)
	last_error=candidate.last_error if not candidate.ready_for_models else loaded_models(candidate)
	if not last_error.is_empty():
		remove_child(viewport)
		viewport.queue_free()
		rebuilding=false
		rebuild_finished.emit(false,last_error)
		return
	# All candidate composition succeeded in an independent space; only now replace old nodes.
	if is_instance_valid(world): world.set_paused(true)
	if is_instance_valid(active_viewport):
		remove_child(active_viewport)
		active_viewport.queue_free()
	world=candidate
	active_viewport=viewport
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.set_paused(not running)
	rebuilding=false
	rebuild_finished.emit(true,"")
