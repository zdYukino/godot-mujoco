class_name MjEnvironmentHost
extends SubViewportContainer
## Owns a saved environment independently of game UI/input. Rebuild discards runtime additions.
signal rebuild_finished(success: bool, error: String)
@export var environment_scene: PackedScene
var world: MjRuntimeWorld
var active_viewport: SubViewport
var rebuilding := false
var install_runtime_viewer := true
var environment_world_path := NodePath(".")
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
		if not node.world_design: return "Environment has no world_design"
		var error: String=node.world_design.validate_dependencies()
		if not error.is_empty(): return error
	if node is MjModelInstance:
		if not node.design: return "Environment model instance has no resource"
		var error: String=node.design.validate_dependencies()
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

func saved_pose(node: Node) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var current := node
	while current:
		if current is Node3D: pose=current.transform*pose
		current=current.get_parent()
	return pose

func saved_environment(scene: PackedScene) -> Node:
	var source: Node=scene.instantiate() if scene else null
	if not source: last_error="Cannot instantiate saved environment"; return null
	var candidate: Node=source.get_node_or_null(environment_world_path)
	if not candidate is MjRuntimeWorld:
		last_error="Saved source no longer contains the configured MjRuntimeWorld"; source.free(); return null
	if candidate!=source:
		# Extract only the saved world and its view context. Game/controller scripts
		# are never entered into the candidate tree; their live instances survive.
		for body in source.find_children("*","PhysicsBody3D",true,false):
			if not candidate.is_ancestor_of(body): last_error="Saved physics bodies outside this world require an explicit EnvironmentHost"; source.free(); return null
		var view_copies: Array[Node]=[]
		for type in ["Camera3D","Light3D","WorldEnvironment"]:
			for node in source.find_children("*",type,true,false):
				if candidate.is_ancestor_of(node): continue
				var copy: Node=node.duplicate()
				if copy is Node3D: copy.transform=saved_pose(node)
				view_copies.append(copy)
		var pose := saved_pose(candidate)
		candidate.get_parent().remove_child(candidate)
		candidate.transform=pose
		for copy in view_copies:
			if copy is Node3D: copy.transform=pose.affine_inverse()*copy.transform
			candidate.add_child(copy)
		for node in candidate.find_children("*","Node",true,false): node.owner=candidate
		source.free()
	candidate.set_meta("mj_saved_scene",scene.resource_path)
	candidate.set_meta("mj_saved_world_path",str(environment_world_path))
	return candidate

func rebuild_environment() -> void:
	last_error=""
	var scene := environment_scene
	if scene and not scene.resource_path.is_empty() and not scene.resource_path.contains("::"):
		scene=ResourceLoader.load(scene.resource_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var candidate: Node=saved_environment(scene)
	if not candidate is MjRuntimeWorld:
		if last_error.is_empty(): last_error="Saved environment root must be MjRuntimeWorld"
	else:
		last_error=validate_models(candidate)
	if not last_error.is_empty():
		if candidate: candidate.free()
		rebuilding=false
		rebuild_finished.emit(false,last_error)
		return
	var running: bool = not world.info().paused if is_instance_valid(world) else not candidate.start_paused
	candidate.start_paused=true
	candidate.viewer_deferred=true
	var viewport := SubViewport.new()
	viewport.own_world_3d=true
	viewport.size=Vector2i(maxf(size.x,1),maxf(size.y,1))
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(candidate)
	# Keep the active environment until asynchronous composition and preview construction succeed.
	var deadline := Time.get_ticks_msec() + 125000
	while is_instance_valid(candidate) and candidate.ready_for_models and not candidate.author_started:
		var status: Dictionary = candidate.info()
		if status.get("compile_status") == "failed" or Time.get_ticks_msec() > deadline: break
		await get_tree().process_frame
	last_error=candidate.last_error if not candidate.author_started else loaded_models(candidate)
	if not candidate.author_started and last_error.is_empty(): last_error = "Environment compilation did not complete"
	if not last_error.is_empty():
		remove_child(viewport)
		viewport.queue_free()
		rebuilding=false
		rebuild_finished.emit(false,last_error)
		return
	# All candidate composition succeeded in an independent space; only now replace old nodes.
	var previous_viewer: Node=world.runtime_viewer if is_instance_valid(world) else null
	var previous_camera: Dictionary=previous_viewer.frame.get("camera",{}).duplicate() if is_instance_valid(previous_viewer) else {}
	if is_instance_valid(world):
		running=not world.info().paused
		world.set_paused(true); world.stop_native_view()
	if is_instance_valid(previous_viewer): previous_viewer.bind_world(candidate,previous_camera)
	if is_instance_valid(active_viewport):
		remove_child(active_viewport)
		active_viewport.queue_free()
	world=candidate
	active_viewport=viewport
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.set_paused(not running)
	if install_runtime_viewer:
		world.activate_runtime_viewer(previous_viewer)
		world.runtime_viewer.environment_host=self
		if not rebuild_finished.is_connected(world.runtime_viewer.host_rebuilt): rebuild_finished.connect(world.runtime_viewer.host_rebuilt)
	rebuilding=false
	rebuild_finished.emit(true,"")
