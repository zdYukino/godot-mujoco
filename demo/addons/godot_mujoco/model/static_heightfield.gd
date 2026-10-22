@tool
class_name MjStaticHeightField
extends Node3D
## Design edits are explicit. Runtime geometry changes only after boundary success.
@export var design: MjHeightFieldData
@export_flags_3d_physics var collision_layer := 1
@export_flags_3d_physics var collision_mask := 1
@export var auto_apply := true
signal edit_finished(result: Dictionary)
var body_rid := RID()
var revision := 0
var pending_request := 0
var last_error := ""
var _visual: MeshInstance3D
var _candidate: MjHeightFieldData
var _candidate_pose := Transform3D()
var _committed := {}
var _candidate_snapshot := {}
var _editor_snapshot := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_visual = MeshInstance3D.new();_visual.name="HeightfieldVisual";add_child(_visual)
	if Engine.is_editor_hint():
		if design: _visual.mesh=design.mesh()
	elif auto_apply: request_apply()

func dirty() -> bool:
	return not design or design.snapshot(global_transform,collision_layer,collision_mask) != _committed

func request_apply(expected_revision: int = -1) -> bool:
	if not design: last_error="Assign a heightfield design";return false
	return _queue(design,expected_revision)

func request_remove() -> bool:
	if not body_rid.is_valid(): last_error="No heightfield to remove";return false
	return _queue(null,revision)

func _queue(value: MjHeightFieldData,expected: int) -> bool:
	if Engine.is_editor_hint() or not is_inside_tree() or is_queued_for_deletion(): last_error="A live runtime node is required";return false
	if pending_request != 0: last_error="Wait for the pending heightfield edit";return false
	if not PhysicsServer3D.has_method("scene_request_heightfield"): last_error="MuJoCo heightfield backend is required";return false
	if value:
		last_error=value.validate()
		if not last_error.is_empty(): return false
	_candidate=value.duplicate(true) if value else null
	_candidate_pose=global_transform
	_candidate_snapshot = _candidate.snapshot(_candidate_pose,collision_layer,collision_mask) if _candidate else {}
	pending_request=PhysicsServer3D.call("scene_request_heightfield",get_world_3d().space,body_rid,_candidate_snapshot,get_instance_id(),revision if expected < 0 else expected)
	if pending_request == 0: last_error="Heightfield queue is full";return false
	last_error="";return true

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var current := design.snapshot(Transform3D(),collision_layer,collision_mask) if design else {}
		if current != _editor_snapshot and _visual:
			_editor_snapshot=current;_visual.mesh=design.mesh() if design else null
		return
	# Parent/node movement is a design change; committed visual stays with collision.
	if _visual and body_rid.is_valid(): _visual.global_transform=_committed.pose
	if pending_request == 0: return
	var result: Dictionary=PhysicsServer3D.call("scene_heightfield_result",pending_request)
	if result.is_empty(): return
	pending_request=0;last_error=result.error
	if result.success:
		body_rid=result.body
		revision=result.revision if body_rid.is_valid() else 0
		if _candidate:
			_committed=_candidate_snapshot.duplicate(true)
			_visual.mesh=_candidate.mesh();_visual.global_transform=_candidate_pose
		else:
			_committed={};_visual.mesh=null
	_candidate=null
	edit_finished.emit(result)

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	if pending_request: PhysicsServer3D.call("scene_cancel_heightfield",pending_request)
	pending_request=0
	if body_rid.is_valid(): PhysicsServer3D.free_rid(body_rid)
	body_rid=RID();revision=0;_committed={}
	if _visual: _visual.queue_free();_visual=null
	request_ready()
