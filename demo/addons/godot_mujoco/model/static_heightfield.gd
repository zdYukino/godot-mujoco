@tool
class_name MjStaticHeightField
extends Node3D
## Design edits are explicit. Runtime geometry changes only after boundary success.
const Bridge=preload("heightfield_bridge.gd")
var live_id := ""
var generation := 0
var _replace_design := false
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
	else:
		live_id=str(get_instance_id())+":"+str(Time.get_ticks_usec())
		Bridge.attach(self)
		if auto_apply: request_apply()

func dirty() -> bool:
	return not design or design.snapshot(global_transform,collision_layer,collision_mask) != _committed

func request_apply(expected_revision: int = -1) -> bool:
	if not design: last_error="Assign a heightfield design";return false
	return _queue(design,expected_revision)

func request_snapshot(snapshot: Dictionary,expected_revision: int) -> bool:
	if expected_revision<0: last_error="Explicit nonnegative revision required";return false
	if pending_request != 0: last_error="Wait for the pending heightfield edit";return false
	if not snapshot.get("width") is int or not snapshot.get("depth") is int or not snapshot.get("heights") is PackedFloat32Array or not snapshot.get("pose") is Transform3D:
		last_error="Expected grid dimensions, heights and pose";return false
	for key in ["layer","mask"]:
		if not snapshot.get(key) is int or snapshot[key]<0 or snapshot[key]>4294967295: last_error="Invalid collision layer/mask";return false
	var grid:=MjHeightFieldData.new();grid.width=snapshot.width;grid.depth=snapshot.depth;grid.heights=snapshot.heights.duplicate()
	return _queue(grid,expected_revision,snapshot)

func state() -> Dictionary:
	if not Engine.is_editor_hint(): _poll_result()
	return {"id":live_id,"generation":generation,"revision":revision,"pending":pending_request,"active":body_rid.is_valid(),"error":last_error,"committed":_committed.duplicate(true)}

func request_remove() -> bool:
	if not body_rid.is_valid(): last_error="No heightfield to remove";return false
	return _queue(null,revision)

func _queue(value: MjHeightFieldData,expected: int,snapshot: Dictionary = {}) -> bool:
	if Engine.is_editor_hint() or not is_inside_tree() or is_queued_for_deletion(): last_error="A live runtime node is required";return false
	if pending_request != 0: last_error="Wait for the pending heightfield edit";return false
	if not PhysicsServer3D.has_method("scene_request_heightfield"): last_error="MuJoCo heightfield backend is required";return false
	if value:
		last_error=value.validate()
		if not last_error.is_empty(): return false
	_replace_design=not snapshot.is_empty()
	_candidate=value.duplicate(true) if value else null
	_candidate_pose=snapshot.get("pose",global_transform)
	_candidate_snapshot = snapshot.duplicate(true) if not snapshot.is_empty() else (_candidate.snapshot(_candidate_pose,collision_layer,collision_mask) if _candidate else {})
	pending_request=PhysicsServer3D.call("scene_request_heightfield",get_world_3d().space,body_rid,_candidate_snapshot,get_instance_id(),revision if expected < 0 else expected)
	if pending_request == 0: last_error="Heightfield queue is full";return false
	last_error="";Bridge.publish(self);return true

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		var current := design.snapshot(Transform3D(),collision_layer,collision_mask) if design else {}
		if current != _editor_snapshot and _visual:
			_editor_snapshot=current;_visual.mesh=design.mesh() if design else null
		return
	# Parent/node movement is a design change; committed visual stays with collision.
	if _visual and body_rid.is_valid(): _visual.global_transform=_committed.pose
	_poll_result()

func _poll_result() -> void:
	if pending_request == 0: return
	var result: Dictionary=PhysicsServer3D.call("scene_heightfield_result",pending_request)
	if result.is_empty(): return
	pending_request=0;last_error=result.error
	Bridge.finished(self,result)
	if result.success:
		body_rid=result.body
		revision=result.revision if body_rid.is_valid() else 0
		if _candidate:
			if _replace_design:
				design=_candidate.duplicate(true);global_transform=_candidate_pose
				collision_layer=_candidate_snapshot.layer;collision_mask=_candidate_snapshot.mask
			_committed=_candidate_snapshot.duplicate(true)
			_visual.mesh=_candidate.mesh();_visual.global_transform=_candidate_pose
		else:
			_committed={};_visual.mesh=null;generation+=1
			Bridge.detach(self);live_id=str(get_instance_id())+":"+str(Time.get_ticks_usec());Bridge.attach(self)
	_candidate=null
	Bridge.publish(self)
	edit_finished.emit(result)

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	Bridge.detach(self)
	if pending_request: PhysicsServer3D.call("scene_cancel_heightfield",pending_request)
	pending_request=0
	if body_rid.is_valid(): PhysicsServer3D.free_rid(body_rid)
	body_rid=RID();revision=0;_committed={}
	if _visual: _visual.queue_free();_visual=null
	request_ready()
