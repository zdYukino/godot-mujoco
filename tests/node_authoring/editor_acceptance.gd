extends RefCounted
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
var checks := 0
var failures: Array[String] = []
var plugin: EditorPlugin

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); print("FAIL ", message)

func wait_valid(model: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if not is_instance_valid(model): break
		if model.is_inside_tree() and model.author_scene and model.author_scene.editor_ready(): return
		await plugin.get_tree().process_frame
	check(false, "compiler settled: " + (str(model.last_error) if is_instance_valid(model) else "captured model was freed"))
	print("NODE_EDITOR_WAIT_STATE ", JSON.stringify(wait_state(model)))
	print("NODE_EDITOR_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	plugin.get_tree().quit(1)
	# Stop the waiting caller before it dereferences a view that never arrived.
	await plugin.get_tree().process_frame

func wait_state(model: Variant) -> Dictionary:
	var current_root := EditorInterface.get_edited_scene_root()
	var current_model: Variant = current_root.get_node_or_null("Model") if is_instance_valid(current_root) else null
	var current_design: Variant = current_model.get("design") if is_instance_valid(current_model) else null
	var report := {"current_root_path":current_root.scene_file_path if is_instance_valid(current_root) else "", "current_root_id":current_root.get_instance_id() if is_instance_valid(current_root) else 0, "current_root_inside_tree":current_root.is_inside_tree() if is_instance_valid(current_root) else false, "current_model_id":current_model.get_instance_id() if is_instance_valid(current_model) else 0, "current_model_inside_tree":current_model.is_inside_tree() if is_instance_valid(current_model) else false, "current_document_id":current_design.get("document_id") if is_instance_valid(current_design) else "", "captured_model_valid":is_instance_valid(model)}
	if not is_instance_valid(model): return report
	report.captured_model_id = model.get_instance_id()
	report.captured_is_current_model = current_model == model
	report.captured_document_id = model.design.document_id if model.design else ""
	var manager: Variant = model.author_scene
	if not is_instance_valid(manager):
		report.manager_valid = false; return report
	var compiler: Variant = manager.compiler
	var active: Dictionary = compiler.active if is_instance_valid(compiler) else {}
	var mismatches := []
	for field in manager._scheduled_source:
		if model.design.get("format_version" if field == "format" else field) != manager._scheduled_source[field]: mismatches.append(field)
	var lineage := []
	var node: Node = model
	while node and lineage.size() < 8:
		lineage.append({"name":str(node.name), "class":node.get_class(), "mode":node.process_mode, "processing":node.is_processing(), "can_process":node.can_process()})
		node = node.get_parent()
	var tree: Variant = model.get_tree() if model.is_inside_tree() else null
	report.merge({"path":str(model.get_path()) if model.is_inside_tree() else "", "inside_tree":model.is_inside_tree(), "node_ready":model.is_node_ready(), "tree_paused":tree.paused if is_instance_valid(tree) else null, "lineage":lineage, "closed":manager._closed, "verification_state":manager.verification_state, "status":manager.compiled_status, "due_ms":manager.due_ms, "now_ms":Time.get_ticks_msec(), "token":manager.compile_token, "scheduled_source_empty":manager._scheduled_source.is_empty(), "scheduled_revision":manager._scheduled_source.get("revision"), "source_mismatch_fields":mismatches, "pending_transforms":var_to_str(manager.pending_transforms), "geometry_queue_size":manager.geometry_queue.size(), "queue_active":manager._queue_active, "queue_generation":manager._queue_generation, "dependency_generation":manager._dependency_generation, "request_dependency_generation":manager._request_dependency_generation, "verification_active":manager._verification_active, "recheck_pending":manager._recheck_pending, "revision":model.design.revision, "validated_revision":model.design.validated_revision, "validation_error":model.design.validation_error, "compiler_valid":is_instance_valid(compiler), "compiler_serial":compiler.serial if is_instance_valid(compiler) else -1, "compiler_busy":compiler.busy() if is_instance_valid(compiler) else false, "active_job":active.get("job_id"), "active_generation":active.get("generation"), "active_directory":active.get("directory"), "current_ready":manager.editor_ready()})
	return report

func appearance_editor(property_name: String) -> EditorProperty:
	for node in plugin.all_nodes(EditorInterface.get_inspector()):
		if node is EditorProperty and node.get_edited_property() == property_name: return node
	return null

func wait_query(condition: Callable, label: String) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if condition.call(): return
		await plugin.get_tree().process_frame
	check(false, label)

func native_reparent_pose(node: Node3D, parent: Node, pose: Transform3D) -> void:
	node.reparent(parent, false)
	node.transform = pose

func structural_queries(edited: Node) -> void:
	var undo := plugin.get_undo_redo()
	var model := Model.new(); model.name = "QueryModel"
	model.design = Author.from_xml('<mujoco><worldbody><frame pos="1 0 0" euler="0 0 30"><body name="left"><joint name="hinge"/><geom name="shape" size=".1"/><geom name="left_anchor" size=".05"/><geom name="mass_anchor" size=".02"/></body></frame><body name="right" pos="0 0 2"><geom name="target_shape" size=".1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="5"/></actuator><sensor><framepos name="shape_sensor" objtype="geom" objname="shape"/></sensor></mujoco>').design
	undo.create_action("Query native model", UndoRedo.MERGE_DISABLE, edited)
	undo.add_do_method(plugin, "attach_author_node", edited, model)
	undo.add_undo_method(edited, "remove_child", model)
	undo.add_do_reference(model)
	undo.commit_action()
	await wait_valid(model)
	var left: Node3D = model.get_node("left")
	var right: Node3D = model.get_node("right")
	var shape: Node3D = left.get_node("shape")
	var identity: String = shape.entity_id
	var history := undo.get_history_undo_redo(undo.get_object_history_id(edited))
	# Native edits use Godot history, while the author snapshot follows the scan.
	undo.create_action("Query native rename", UndoRedo.MERGE_DISABLE, shape)
	undo.add_do_property(shape, "name", "first_branch")
	undo.add_undo_property(shape, "name", "shape")
	undo.commit_action()
	await wait_query(func(): return model.design.entity(identity).name == "first_branch", "native rename reaches author source")
	await wait_valid(model)
	var discarded_revision: int = model.design.revision
	history.undo()
	await wait_query(func(): return model.design.entity(identity).name == "shape", "native rename Undo restores source")
	await wait_valid(model)
	undo.create_action("Query native branch", UndoRedo.MERGE_DISABLE, shape)
	undo.add_do_property(shape, "name", "branch_shape")
	undo.add_undo_property(shape, "name", "shape")
	undo.commit_action()
	await wait_query(func(): return model.design.entity(identity).name == "branch_shape", "new native Undo branch reaches author source")
	await wait_valid(model)
	check(model.design.revision == discarded_revision and model.design.entity(identity).name == "branch_shape", "native Undo branch reusing a source revision publishes fresh entity data: " + str([discarded_revision, model.design.revision, model.design.entity(identity).name]))
	var pose: Transform3D = shape.global_transform
	undo.create_action("Query native reparent", UndoRedo.MERGE_DISABLE, shape)
	undo.add_do_method(shape, "reparent", right, true)
	undo.add_undo_method(shape, "reparent", left, true)
	undo.commit_action()
	await wait_query(func(): return model.design.entity(identity).parent_id == right.entity_id, "native reparent reaches author source")
	await wait_valid(model)
	check(shape.global_transform.is_equal_approx(pose) and model.design.entity(identity).parent_id == right.entity_id, "native reparent preserves the source world pose through a hidden frame: " + str([pose, shape.global_transform, model.design.entity(identity).transform]))
	history.undo()
	await wait_query(func(): return model.design.entity(identity).parent_id == left.entity_id, "native reparent Undo restores source parent")
	await wait_valid(model)
	check(shape.get_parent() == left and shape.global_transform.is_equal_approx(pose), "native reparent Undo restores hierarchy and pose with fresh read stages")
	# Two reparent operations, a rename and a real drag arrive before any scan.
	# A source refresh for the first edit must not erase the remaining intents.
	var anchor: Node3D = left.get_node("left_anchor")
	var anchor_id: String = anchor.entity_id
	var shape_local: Transform3D = shape.transform
	var anchor_local: Transform3D = anchor.transform
	var anchor_world: Transform3D = anchor.global_transform
	var dragged := pose; dragged.origin += Vector3(.25, 0, -.1)
	undo.create_action("Query native batch before save", UndoRedo.MERGE_DISABLE, model)
	undo.add_do_method(self, "native_reparent_pose", shape, right, right.global_transform.affine_inverse() * dragged)
	undo.add_do_method(self, "native_reparent_pose", anchor, right, right.global_transform.affine_inverse() * anchor_world)
	undo.add_do_property(anchor, "name", "saved_anchor")
	undo.add_undo_method(self, "native_reparent_pose", shape, left, shape_local)
	undo.add_undo_method(self, "native_reparent_pose", anchor, left, anchor_local)
	undo.add_undo_property(anchor, "name", "left_anchor")
	undo.commit_action()
	plugin._apply_changes()
	check(not plugin.author_sync_pending and model.author_scene.pending_transforms.is_empty() and model.design.entity(identity).parent_id == right.entity_id and model.design.entity(anchor_id).parent_id == right.entity_id and model.design.entity(anchor_id).name == "saved_anchor", "immediate save flush settles every native reparent/rename in the batch")
	check(Commands.world_pose(model.design, identity).is_equal_approx(dragged) and shape.global_transform.is_equal_approx(dragged), "a real drag immediately after reparent survives structural refresh and save flushing")
	var final_source: Dictionary = model.design.author_snapshot()
	var saved := PackedScene.new(); saved.pack(edited)
	check(ResourceSaver.save(saved, "res://QueryNativeSaved.tscn") == OK, "save accepts the fully synchronized native batch")
	var reopened: Node = ResourceLoader.load("res://QueryNativeSaved.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(reopened.get_node("QueryModel").design.author_snapshot() == final_source, "save/reopen retains every native batch edit and the final drag pose")
	reopened.free()
	await wait_valid(model)
	history.undo()
	await wait_query(func(): return model.design.entity(identity).parent_id == left.entity_id and model.design.entity(anchor_id).name == "left_anchor", "native batch Undo restores both source parents and name")
	await wait_valid(model)
	check(shape.global_transform.is_equal_approx(pose) and anchor.get_parent() == left, "native batch Undo restores the pre-drag world pose")
	history.redo()
	await wait_query(func(): return model.design.entity(anchor_id).name == "saved_anchor" and model.design.entity(identity).parent_id == right.entity_id, "native batch Redo restores the final source")
	await wait_valid(model)
	check(model.design.author_snapshot() == final_source and shape.global_transform.is_equal_approx(dragged), "native batch Redo uses the complete final history snapshot")
	var before_delete: Dictionary = model.design.author_snapshot()
	undo.create_action("Query native dependent delete", UndoRedo.MERGE_DISABLE, shape)
	undo.add_do_method(right, "remove_child", shape)
	undo.add_undo_method(right, "add_child", shape)
	undo.add_undo_reference(shape)
	undo.commit_action()
	plugin._apply_changes()
	check(plugin.modal_pending and plugin.author_sync_pending and not plugin._build() and model.design.author_snapshot() == before_delete, "save/F5 synchronization does not consent to a dependent native deletion")
	var confirmation: ConfirmationDialog
	for child in plugin.get_children():
		if child is ConfirmationDialog and child.title == "删除关联对象": confirmation = child
	check(confirmation != null, "dependent native deletion keeps its confirmation dialog")
	if confirmation: confirmation.canceled.emit()
	await wait_query(func(): return not plugin.modal_pending and shape.get_parent() == right, "cancelling native deletion restores the source hierarchy")
	plugin._apply_changes()
	await wait_valid(model)
	check(model.design.author_snapshot() == before_delete and not plugin.author_sync_pending, "cancelled deletion preserves source and clears the explicit synchronization barrier")
	var other := Model.new(); other.name = "OtherQueryModel"
	other.design = Author.from_xml('<mujoco><worldbody><body name="other"><geom size=".1"/></body></worldbody></mujoco>').design
	edited.add_child(other); other.owner = edited
	await wait_valid(other)
	var before: Dictionary = model.design.author_snapshot()
	var other_before: Dictionary = other.design.author_snapshot()
	shape.reparent(other, true)
	await wait_query(func(): return shape.get_parent() == right, "cross-model native move is rejected")
	check(model.design.author_snapshot() == before and other.design.author_snapshot() == other_before, "cross-model rejection precedes deletion handling in both models")
	# A duplicated model initially shares its exported resource/instance identity.
	var copy := model.duplicate()
	edited.add_child(copy); copy.owner = edited
	await wait_query(func(): return copy.design != model.design and copy.design_instance_id != model.design_instance_id, "native model duplication forks resource and instance identity")
	await wait_valid(copy)
	var copied_shape: Node = copy.author_scene.nodes[identity]
	copied_shape.set("mjcf/name", "independent_shape")
	await wait_valid(copy)
	check(copy.design.entity(identity).name == "independent_shape" and model.design.entity(identity).name == "branch_shape", "native duplicate's derived source data stays independent after an edit")
	var original_color: Color = shape.get("mjcf/color")
	var original_appearance: Dictionary = model.design.author_snapshot()
	var source_preview := [shape.get_node("_Visual").get_instance_id(),shape.get_node("_Visual").mesh.get_instance_id()]
	var copied_preview := [copied_shape.get_node("_Visual").get_instance_id(),copied_shape.get_node("_Visual").mesh.get_instance_id()]
	copied_shape.set("mjcf/color",Color(.2,.7,.4))
	await wait_valid(copy)
	check(model.design.author_snapshot()==original_appearance and shape.get("mjcf/color")==original_color and shape.get_node("_Visual").material_override.albedo_color.is_equal_approx(original_color), "first native duplicate appearance edit leaves original source/material unchanged")
	check([shape.get_node("_Visual").get_instance_id(),shape.get_node("_Visual").mesh.get_instance_id()]==source_preview and [copied_shape.get_node("_Visual").get_instance_id(),copied_shape.get_node("_Visual").mesh.get_instance_id()]==copied_preview and copied_shape.get_node("_Visual").material_override!=shape.get_node("_Visual").material_override, "native duplicate appearance uses copy-on-write without replacing either visual or Mesh")
	var appearance_saved := PackedScene.new(); appearance_saved.pack(edited)
	check(ResourceSaver.save(appearance_saved,"res://NativeDuplicateAppearance.tscn")==OK,"native duplicate appearance saves")
	var appearance_reopened: Node = ResourceLoader.load("res://NativeDuplicateAppearance.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var reopened_source: Node = appearance_reopened.get_node(NodePath(str(edited.get_path_to(shape))))
	var reopened_copy: Node = appearance_reopened.get_node(NodePath(str(edited.get_path_to(copied_shape))))
	check(reopened_source.get("mjcf/color")==original_color and reopened_copy.get("mjcf/color").is_equal_approx(Color(.2,.7,.4)) and reopened_source.get_node("_Visual").material_override!=reopened_copy.get_node("_Visual").material_override,"save/reopen retains isolated native duplicate appearance")
	appearance_reopened.free()
	# Keep fixture nodes owned by the edited scene through editor shutdown; freeing
	# them synchronously can race Godot's queued gizmo redraw notifications.

func bounded_native_sync_queries() -> void:
	var xml := '<mujoco><worldbody><body name="kept"><geom name="anchor" size=".1"/>'
	for index in 64: xml += '<geom name="removed_%d" size=".01"/>' % index
	xml += '</body><body name="target"/>'
	for index in 16: xml += '<body name="moving_%d"/>' % index
	xml += '</worldbody></mujoco>'
	var root := Node3D.new(); root.name = "BoundedNativeSync"
	var model := Model.new(); model.name = "Model"
	model.design = Author.from_xml(xml).design
	root.add_child(model); model.owner = root
	var scene := PackedScene.new(); scene.pack(root)
	check(ResourceSaver.save(scene, "res://BoundedNativeSync.tscn") == OK, "create native synchronization boundary fixture")
	root.free()
	EditorInterface.open_scene_from_path("res://BoundedNativeSync.tscn")
	await wait_query(func(): return EditorInterface.get_edited_scene_root() != null and EditorInterface.get_edited_scene_root().scene_file_path == "res://BoundedNativeSync.tscn", "native synchronization fixture opens")
	var edited := EditorInterface.get_edited_scene_root()
	if not edited or edited.scene_file_path != "res://BoundedNativeSync.tscn": return
	model = edited.get_node("Model")
	await wait_valid(model)
	var undo := plugin.get_undo_redo()
	var kept: Node = model.get_node("kept")
	var removed_ids: Array[String] = []
	# Removed nodes no longer contribute to the visible-tree size, but each
	# independent source deletion still needs its own reconciliation pass.
	undo.create_action("Query bulk native deletion", UndoRedo.MERGE_DISABLE, model)
	for index in 64:
		var node: Node = kept.get_node("removed_%d" % index)
		removed_ids.append(node.entity_id)
		undo.add_do_method(kept, "remove_child", node)
		undo.add_undo_method(kept, "add_child", node)
		undo.add_undo_reference(node)
	undo.commit_action()
	plugin._apply_changes()
	check(not plugin.author_sync_pending and removed_ids.all(func(identity): return model.design.entity(identity).is_empty()), "one save synchronizes bulk deletion after the visible hierarchy shrinks")
	await wait_valid(model)
	var target: Node = model.get_node("target")
	var renamed := {}
	# A body can require separate name and parent commands, with no visual child
	# nodes to incidentally increase the synchronization budget.
	undo.create_action("Query bulk native rename and reparent", UndoRedo.MERGE_DISABLE, model)
	for index in 16:
		var node: Node = model.get_node("moving_%d" % index)
		var label := "moved_%d" % index
		renamed[node.entity_id] = label
		undo.add_do_method(node, "reparent", target, true)
		undo.add_do_property(node, "name", label)
		undo.add_undo_method(node, "reparent", model, true)
		undo.add_undo_property(node, "name", str(node.name))
	undo.commit_action()
	plugin._apply_changes()
	var complete: bool = not plugin.author_sync_pending and model.author_scene.pending_transforms.is_empty()
	for identity in renamed:
		var item: Dictionary = model.design.entity(identity)
		complete = complete and item.name == renamed[identity] and item.parent_id == target.entity_id
	check(complete, "one save synchronizes both rename and reparent for every body in a native batch")
	var final_source: Dictionary = model.design.author_snapshot()
	scene = PackedScene.new(); scene.pack(edited)
	check(ResourceSaver.save(scene, "res://BoundedNativeSaved.tscn") == OK, "save accepts fully synchronized bulk native edits")
	var reopened: Node = ResourceLoader.load("res://BoundedNativeSaved.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(reopened.get_node("Model").design.author_snapshot() == final_source, "save/reopen retains all bulk native source edits")
	reopened.free()
	await wait_valid(model)

func run(editor: EditorPlugin) -> void:
	plugin = editor
	var root := Node3D.new(); root.name = "AuthorTest"
	var model := Model.new(); model.name = "Model"
	model.design = Author.from_xml('<mujoco><compiler angle="radian"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" type="capsule" fromto="0 0 0 0 0 -.6" size=".04"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>').design
	# Rewriting a restored, already-open same-path scene can asynchronously
	# replace the captured Model. Isolate this run while keeping native names.
	var fixture_path := "res://AuthorTest_%d_%d.tscn" % [OS.get_process_id(), Time.get_ticks_usec()]
	var expected_document_id: String = model.design.document_id
	root.add_child(model); model.owner = root
	var scene := PackedScene.new(); scene.pack(root)
	check(ResourceSaver.save(scene, fixture_path) == OK, "create fixture scene")
	root.free()
	EditorInterface.open_scene_from_path(fixture_path)
	await wait_query(func():
		var current := EditorInterface.get_edited_scene_root()
		if not current or current.scene_file_path != fixture_path or not current.is_inside_tree(): return false
		var candidate: Variant = current.get_node_or_null("Model")
		return is_instance_valid(candidate) and candidate.is_inside_tree() and candidate.is_node_ready() and candidate.design and candidate.design.document_id == expected_document_id, "requested current in-tree AuthorTest model opens")
	var edited := EditorInterface.get_edited_scene_root()
	var candidate: Variant = edited.get_node_or_null("Model") if is_instance_valid(edited) else null
	if not edited or edited.scene_file_path != fixture_path or not is_instance_valid(candidate) or not candidate.is_inside_tree() or not candidate.is_node_ready() or candidate.design.document_id != expected_document_id:
		print("NODE_EDITOR_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
		plugin.get_tree().quit(1)
		return
	model = candidate
	await wait_valid(model)
	check(model.author_scene.nodes.size() == 3, "formal body/geom/joint nodes created")
	var arm: Node3D = model.get_node("arm")
	var rod: Node3D = arm.get_node("rod")
	var joint: Node3D = arm.get_node("hinge")
	check(rod.get_node_or_null("_Visual") is MeshInstance3D, "geometry belongs to its body hierarchy")
	check(arm.owner == edited and rod.owner == edited and joint.owner == edited, "nodes owned by edited scene")
	check(joint.get("mjcf/type") == "hinge", "typed Inspector joint properties")
	var stable_preview := [rod.get_node("_Visual").get_instance_id(), rod.get_node("_Visual").mesh.get_instance_id(), rod.get_node("_Visual").material_override.get_instance_id()]
	var undo := plugin.get_undo_redo()
	undo.create_action("Inspector damping", UndoRedo.MERGE_DISABLE, joint)
	undo.add_do_property(joint, "mjcf/damping", .3)
	undo.add_undo_property(joint, "mjcf/damping", 0.0)
	undo.commit_action()
	await wait_valid(model)
	check(is_equal_approx(float(model.design.entity(joint.entity_id).attrs.damping), .3), "Inspector updates physical author field")
	check([rod.get_node("_Visual").get_instance_id(), rod.get_node("_Visual").mesh.get_instance_id(), rod.get_node("_Visual").material_override.get_instance_id()] == stable_preview, "Inspector damping validation preserves visual, Mesh and material identity")
	var original: Transform3D = rod.transform
	var moved := original; moved.origin.x += .2
	undo.create_action("Native transform", UndoRedo.MERGE_DISABLE, rod)
	undo.add_do_property(rod, "transform", moved)
	undo.add_undo_property(rod, "transform", original)
	undo.commit_action()
	for frame in 5: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, moved.origin.x), "native transform writes source pose")
	check([rod.get_node("_Visual").get_instance_id(), rod.get_node("_Visual").mesh.get_instance_id(), rod.get_node("_Visual").material_override.get_instance_id()] == stable_preview, "native pose validation preserves compatible visual resources")
	var history := undo.get_history_undo_redo(undo.get_object_history_id(edited))
	history.undo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, original.origin.x), "one native undo restores author pose")
	history.redo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, moved.origin.x), "redo restores physical author pose")
	var packed := PackedScene.new(); packed.pack(edited)
	check(ResourceSaver.save(packed, "res://Roundtrip.tscn") == OK, "save hierarchical scene")
	var reopened: PackedScene = ResourceLoader.load("res://Roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var copy: Node = reopened.instantiate()
	check(copy.get_node_or_null("Model/arm/rod/_Visual") != null, "hierarchy and geometry serialize")
	check(copy.get_node("Model").design.document_id == model.design.document_id, "author identity persists")
	copy.free()
	var revision: int = model.design.revision
	var until := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<until: await plugin.get_tree().process_frame
	check(model.design.revision==revision,"display refresh cannot generate author edits or compile loops")
	check(plugin._build(), "valid current author version permits F5")
	# Exercise the single creation entry through its actual button handler, then
	# change the physical joint type through the native Inspector/Undo path.
	var created := model.apply_author_command({"op":"add_body"})
	var body_id: String = created.selected
	created = model.apply_author_command({"op":"add_geom","id":body_id,"type":"box"})
	plugin.panel.select(model.author_scene.nodes[created.selected])
	var joint_buttons := []
	for control in plugin.panel.get_children():
		if control is Button and control.text.begins_with("新增 ") and control.text.ends_with("joint"): joint_buttons.append(control)
	check(joint_buttons.size()==1 and joint_buttons[0].text=="新增 joint", "one joint creation entry in the panel")
	joint_buttons[0].pressed.emit()
	await wait_valid(model)
	var added_joint := {}
	for entity in model.design.entities():
		if entity.kind=="joint" and entity.parent_id==body_id: added_joint=entity
	check(not added_joint.is_empty() and added_joint.attrs.type=="free", "joint button creates a free joint on the selected geom's body")
	var added_node: Node = model.author_scene.nodes[added_joint.id]
	check(EditorInterface.get_selection().get_selected_nodes()==[added_node], "new joint is selected for immediate Inspector editing")
	undo.create_action("Inspector joint type",UndoRedo.MERGE_DISABLE,added_node)
	undo.add_do_property(added_node,"mjcf/type","hinge")
	undo.add_undo_property(added_node,"mjcf/type","free")
	undo.commit_action()
	await wait_valid(model)
	check(model.design.entity(added_joint.id).attrs.type=="hinge", "default free joint remains editable through Inspector Type")
	check(appearance_editor("mjcf/axis") != null, "joint type layout changes still add hinge Inspector fields")
	history.undo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(model.design.entity(added_joint.id).attrs.type=="free", "Inspector type undo restores the default free joint")
	check(appearance_editor("mjcf/axis") == null, "joint type undo removes hinge-only Inspector fields")
	EditorInterface.inspect_object(rod)
	for frame in 12: await plugin.get_tree().process_frame
	check(appearance_editor("mjcf/color") != null and appearance_editor("mjcf/opacity") != null and appearance_editor("mjcf/texture_file") != null, "Visibility exposes native color, opacity and texture property editors")
	check(rod.get_property_list().filter(func(field):return field.name == "mjcf/density").size() == 1, "appearance editor keeps inherited geom properties unique")
	if appearance_editor("mjcf/color"):
		var color_editor := appearance_editor("mjcf/color")
		var gesture_preview := [rod.get_node("_Visual").get_instance_id(), rod.get_node("_Visual").mesh.get_instance_id()]
		var original_color: Color = rod.get("mjcf/color")
		var continuous := true
		for point in 8:
			if not is_instance_valid(color_editor): continuous = false; break
			color_editor.emit_changed("mjcf/color", original_color.lerp(Color(.15,.55,.85), float(point + 1) / 8), "", true)
			for frame in 3: await plugin.get_tree().process_frame
		if is_instance_valid(color_editor): color_editor.emit_changed("mjcf/color", Color(.15,.55,.85), "", false)
		await wait_valid(model)
		check(continuous and is_instance_valid(color_editor) and appearance_editor("mjcf/color") == color_editor, "continuous color edits and background compile preserve the active Inspector control")
		check([rod.get_node("_Visual").get_instance_id(), rod.get_node("_Visual").mesh.get_instance_id()] == gesture_preview, "continuous Inspector color gesture retains visual and Mesh identity")
		check(rod.get_node("_Visual").material_override.albedo_color.is_equal_approx(Color(.15,.55,.85)), "Inspector RGB refresh replaces the previous preview material")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/color").is_equal_approx(original_color), "one Undo restores the color before the continuous gesture")
		history.redo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/color").is_equal_approx(Color(.15,.55,.85)), "one Redo restores the final continuous color")
		appearance_editor("mjcf/opacity").emit_changed("mjcf/opacity", .4)
		await wait_valid(model)
		check(is_equal_approx(rod.get_node("_Visual").material_override.albedo_color.a,.4) and rod.get_node("_Visual").material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Inspector opacity changes MJCF and enables actual transparency")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(is_equal_approx(rod.get("mjcf/opacity"),1.0), "native Inspector undo restores MJCF opacity")
		history.redo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		var texture := Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.9,.2,.1,.8))
		check(texture.save_png("res://inspector-texture.png") == OK, "create Inspector texture fixture")
		appearance_editor("mjcf/texture_file").emit_changed("mjcf/texture_file", "res://inspector-texture.png")
		await wait_valid(model)
		check(rod.get_node("_Visual").material_override.albedo_texture != null, "Inspector file selection displays texture after background compile")
		var appearance_scene := PackedScene.new(); appearance_scene.pack(edited)
		check(ResourceSaver.save(appearance_scene,"res://AppearanceScene.tscn") == OK, "save hierarchical scene with MJCF material and texture")
		var appearance_copy: Node = ResourceLoader.load("res://AppearanceScene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		check(is_equal_approx(appearance_copy.get_node("Model/arm/rod").get("mjcf/opacity"),.4) and appearance_copy.get_node("Model/arm/rod/_Visual").material_override.albedo_texture != null, "scene reopen retains source opacity and rendered texture")
		appearance_copy.free()
		var exported: String = plugin.export_author(model,"res://appearance-export")
		var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
		check(exported.begins_with("已导出") and document.import_file(ProjectSettings.globalize_path("res://appearance-export/model.xml")), "exported MJCF and texture assets compile independently")
		var rod_geometry: Dictionary = document.geometry().filter(func(geometry):return geometry.name == "rod")[0]
		check(rod_geometry.has("texture_image") and is_equal_approx(rod_geometry.color.a,.4), "export retains physical MJCF appearance rather than only Godot overrides")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/texture_file") == "" and rod.get_node("_Visual").material_override.albedo_texture == null, "texture import is undoable through native Inspector history")
	await structural_queries(edited)
	await bounded_native_sync_queries()
	print("NODE_EDITOR_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
