@tool
extends RefCounted
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Artifact = preload("res://addons/godot_mujoco/model/editor_artifact.gd")
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const SceneBuilder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
var checks := 0
var failures: Array[String] = []

class ImportPanel:
	extends "res://addons/mujoco_editor/author_panel.gd"
	var captured: Resource
	func create_model(design: Resource) -> void:
		captured = design

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ", label)

func settle(editor: EditorPlugin, model: Node) -> bool:
	for frame in 2400:
		if model.author_scene.editor_ready(): return true
		if model.author_scene.verification_state == "error": break
		await editor.get_tree().process_frame
	check(false, "editor artifact reaches current readiness: " + model.last_error)
	return false

func run(editor: EditorPlugin) -> void:
	var design: Resource = Author.from_xml('<mujoco><worldbody><body name="arm" pos="0 0 1"><joint name="hinge"/><geom name="ball" size=".1"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>').design
	var source: Dictionary = design.author_snapshot()
	check(await SceneBuilder.save(design, "res://ArtifactGates.tscn") == OK, "stale Builder->prepare_tree->save branch succeeds in the actual editor")
	check(not design.editor_artifact_stamp.is_empty(), "builder's internal accepted replay preserves its new stamp")
	EditorInterface.open_scene_from_path("res://ArtifactGates.tscn")
	for frame in 120:
		await editor.get_tree().process_frame
		if EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().scene_file_path == "res://ArtifactGates.tscn": break
	var world := EditorInterface.get_edited_scene_root()
	var model: Node = world.get_node("Model")
	check(not model.author_scene.editor_ready() and not editor.author_debugger.models_valid(world), "serialized validation never releases editor/live readiness while verification is pending")
	check(not editor._build(), "actual F5 build gate refuses pending qualification")
	check(editor.export_author(model, "res://artifact-pending-export").contains("等待后台验证"), "export refuses pending qualification")
	if not await settle(editor, model): editor.get_tree().quit(1); return
	check(model.author_scene.last_artifact_kind == "hit" and model.design.author_snapshot() == source, "actual editor reopen is a source-preserving verified hit")
	check(editor._build() and editor.author_debugger.models_valid(world), "F5 and live publication accept the same verified current model")
	var replay := Artifact.payload(model.design).duplicate(true)
	replay.geometry[0].color = Color.MAGENTA
	model.author_scene.apply_compiled(replay)
	check(model.author_scene.drain_geometry().is_empty() and not model.author_scene.editor_ready(), "direct absent-stamp payload replay cannot retain old transient approval after its drain")
	check(not editor._build() and not editor.author_debugger.models_valid(world) and editor.export_author(model, "res://artifact-unverified-export").contains("等待后台验证"), "direct replay closes F5/export/live gates until worker qualification")
	if not await settle(editor, model): editor.get_tree().quit(1); return
	var before: Dictionary = model.design.author_snapshot()
	var joint: Node
	var joint_identity := ""
	for entity in model.design.entities():
		if entity.kind == "joint": joint = model.author_scene.nodes[entity.id]; joint_identity = entity.id
	joint.get_parent().remove_child(joint); joint.queue_free()
	editor.scan_at = 0; editor._process(0.0)
	check(editor.modal_pending and model.design.author_snapshot() == before, "native dependent deletion opens confirmation without mutating source")
	check(model.author_scene.editor_ready(), "modal case retains a locally verified source, exercising the editor-level barrier")
	check(not editor._build() and not editor.author_debugger.models_valid(world), "native/modal barrier closes F5 and live publication together")
	check(editor.export_author(model, "res://artifact-modal-export").contains("等待后台验证"), "export shares pending native/modal barrier")
	var dialog: ConfirmationDialog
	for child in editor.get_children():
		if child is ConfirmationDialog and child.title == "删除关联对象": dialog = child
	check(dialog != null, "actual native dependent-delete confirmation exists")
	# A real user cannot cancel in the same call stack as queue_free(). Let the
	# removed node finish deletion before the cancellation rebuilds its view.
	var delete_deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(joint) and Time.get_ticks_msec() < delete_deadline:
		await editor.get_tree().process_frame
	check(not is_instance_valid(joint), "native deletion finishes before the user cancels its confirmation")
	if is_instance_valid(dialog): dialog.get_cancel_button().pressed.emit()
	var cancel_deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(dialog) and Time.get_ticks_msec() < cancel_deadline:
		await editor.get_tree().process_frame
	var restored_joint: Variant = model.author_scene.nodes.get(joint_identity)
	check(not editor.modal_pending and not is_instance_valid(dialog) and model.design.author_snapshot() == before and is_instance_valid(restored_joint) and not restored_joint.is_queued_for_deletion(), "cancel restores native nodes without consenting to source deletion")
	if not await settle(editor, model): editor.get_tree().quit(1); return
	check(editor._build() and editor.author_debugger.models_valid(world), "resolving the modal restores F5/live authorization")
	check(editor.export_author(model, "res://artifact-ready-export").begins_with("已导出"), "resolved current source can export")
	var file := FileAccess.open("res://artifact-gui-source.xml", FileAccess.WRITE)
	file.store_string('<mujoco><worldbody><geom name="imported" size=".1"/></worldbody></mujoco>'); file.close()
	var result: Dictionary = await Builder.run_worker({"op":"import", "source":ProjectSettings.globalize_path("res://artifact-gui-source.xml")})
	var panel := ImportPanel.new(); panel.status = Label.new(); panel.add_child(panel.status)
	panel.import_finished(result)
	check(panel.captured != null and not panel.captured.editor_artifact_stamp.is_empty() and panel.captured.cache_path.is_empty(), "GUI import uses shared portable producer publication and clears scratch ownership")
	if panel.captured:
		var hit := await Builder.run_worker({"op":"verify_or_compile", "author":panel.captured.author_snapshot(), "context":preload("res://addons/godot_mujoco/model/collision_settings.gd").context(null,panel.captured), "editor_artifact_stamp":panel.captured.editor_artifact_stamp, "payload":Artifact.payload(panel.captured)})
		check(hit.get("artifact_kind") == "hit", "fresh GUI import qualification verifies without another native model result")
	panel.free()
	# Persist partial records without passing them through a builder/initializer,
	# then restore the real Inspector selection while qualification is pending.
	var partial := Author.new(); partial.restore_author(model.design.author_snapshot())
	partial.cached_entities = [{}]; partial.cached_geometry = [{}]
	partial.collision_geometry = [{}]; partial.collision_stats = [{}]
	partial.compiled_snapshot = model.design.compiled_snapshot.duplicate(true)
	partial.validated_revision = partial.revision; partial.validated_context = model.compilation_signature()
	partial.editor_artifact_stamp = model.design.editor_artifact_stamp.duplicate(true)
	var partial_world := preload("res://addons/godot_mujoco/model/runtime_world.gd").new()
	partial_world.name = "PartialArtifact"
	partial_world.world_design = Author.from_xml('<mujoco><worldbody/></mujoco>').design
	var partial_model := Model.new(); partial_model.name = "Model"; partial_model.design = partial
	partial_world.add_child(partial_model); partial_model.owner = partial_world
	var packed := PackedScene.new()
	check(packed.pack(partial_world) == OK and ResourceSaver.save(packed, "res://ArtifactPartial.tscn") == OK, "persist a partial saved cache without pre-repair")
	partial_world.free()
	EditorInterface.open_scene_from_path("res://ArtifactPartial.tscn")
	for frame in 120:
		await editor.get_tree().process_frame
		if EditorInterface.get_edited_scene_root() and EditorInterface.get_edited_scene_root().scene_file_path == "res://ArtifactPartial.tscn": break
	partial_model = EditorInterface.get_edited_scene_root().get_node("Model")
	check(partial_model.design.cached_entities.is_empty() and not partial_model.author_scene.editor_ready(), "malformed saved records are sanitized before pending native fallback reads")
	var body: Node
	for entity in partial_model.design.entities():
		if entity.kind == "body": body = partial_model.author_scene.nodes[entity.id]
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(body)
	EditorInterface.inspect_object(body)
	check(body.native_properties().is_empty() and float(body.get("mjcf/mass")) == 1.0, "restored actual Inspector selection uses safe pending fallback for partial records")
	if not await settle(editor, partial_model): editor.get_tree().quit(1); return
	check(partial_model.author_scene.last_artifact_kind == "compiled" and not body.native_properties().is_empty() and float(body.get("mjcf/mass")) > 0, "partial saved cache safely misses and current Inspector computed data repairs")
	var report := {"checks":checks,"failed":failures.size(),"failures":failures}
	FileAccess.open("res://artifact-editor-result.json", FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("NODE_ARTIFACT_EDITOR_RESULT ", JSON.stringify(report))
	editor.get_tree().quit(0 if failures.is_empty() else 1)
