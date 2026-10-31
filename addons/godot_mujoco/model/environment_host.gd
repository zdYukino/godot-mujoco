@icon("res://addons/godot_mujoco/icons/mj_environment_host.svg")
class_name MjEnvironmentHost
extends SubViewportContainer
## Owns a saved environment independently of game UI/input. Rebuild discards runtime additions.
signal rebuild_finished(success: bool, error: String)
signal world_committed(world: Node3D)
@export var environment_scene: PackedScene
var world: MjRuntimeWorld
var active_viewport: SubViewport
var rebuilding := false
var environment_world_path := NodePath(".")
var last_error := ""
var _rebuild_generation := 0
var _candidate_viewport: SubViewport
var _commit_in_progress := false

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
	_rebuild_generation+=1
	call_deferred("_rebuild_environment",_rebuild_generation)
	return true

func cancel_rebuild_environment() -> bool:
	if not rebuilding or _commit_in_progress:return false
	_rebuild_generation+=1
	rebuilding=false
	var candidate := _candidate_viewport
	_candidate_viewport=null
	if is_instance_valid(candidate):
		if candidate.get_parent()==self:remove_child(candidate)
		candidate.queue_free()
	last_error="Environment rebuild cancelled before commit"
	rebuild_finished.emit(false,last_error)
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

func _rebuild_environment(generation: int) -> void:
	if generation!=_rebuild_generation or not rebuilding:return
	last_error=""
	var scene := environment_scene
	if scene and not scene.resource_path.is_empty() and not scene.resource_path.contains("::"):
		scene=preload("saved_scene_loader.gd").load_scene(scene.resource_path)
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
	candidate._presentation_suspended=true
	var viewport := SubViewport.new()
	_candidate_viewport=viewport
	viewport.own_world_3d=true
	viewport.size=Vector2i(maxf(size.x,1),maxf(size.y,1))
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	viewport.add_child(candidate)
	# Keep the active environment until asynchronous composition and preview construction succeed.
	var deadline := Time.get_ticks_msec() + 125000
	while is_instance_valid(candidate) and candidate.ready_for_models and not candidate.author_started:
		if generation!=_rebuild_generation or not rebuilding:return
		var status: Dictionary = candidate.info()
		if status.get("compile_status") == "failed" or Time.get_ticks_msec() > deadline: break
		await get_tree().process_frame
	if generation!=_rebuild_generation or not rebuilding:return
	last_error=candidate.last_error if not candidate.author_started else loaded_models(candidate)
	if not candidate.author_started and last_error.is_empty(): last_error = "Environment compilation did not complete"
	if not last_error.is_empty():
		_candidate_viewport=null
		remove_child(viewport)
		viewport.queue_free()
		rebuilding=false
		rebuild_finished.emit(false,last_error)
		return
	# All candidate composition succeeded in an independent space; only now replace old nodes.
	var previous_world: Node3D=world
	var previous_viewport: SubViewport=active_viewport
	var previous_camera: Dictionary={}
	if is_instance_valid(previous_world):
		running=not previous_world.info().paused
		if is_instance_valid(previous_world._view_session):
			previous_camera=previous_world._view_session.frame.get("camera",{}).duplicate(true)
			if not previous_world._view_session.camera_control and not previous_camera.is_empty():
				previous_camera.type=0
				previous_camera.erase("target")
		candidate.native_view_experimental=previous_world.native_view_experimental
		candidate.native_view_direct_experimental=previous_world.native_view_direct_experimental
		candidate.native_view_autostart_armed=candidate.native_view_experimental
		previous_world.set_paused(true)
		previous_world.stop_native_view()
	world=candidate
	active_viewport=viewport
	# Cancellation may discard candidates only before this commit boundary.
	_candidate_viewport=null
	_commit_in_progress=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world.set_paused(not running)
	if not previous_camera.is_empty(): world._view_session.restore_view(previous_camera)
	# Scene-owned consumers rebind while the previous authority still exists.
	world_committed.emit(world)
	world._activate_presentation()
	if is_instance_valid(previous_viewport):
		remove_child(previous_viewport)
		previous_viewport.queue_free()
	_commit_in_progress=false
	rebuilding=false
	rebuild_finished.emit(true,"")
