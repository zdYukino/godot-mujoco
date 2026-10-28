@tool
extends EditorPlugin
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const AuthorPanel = preload("author_panel.gd")
const Layout = preload("property_layout.gd")
var panel: Control
var map_panel: Control
var object_panel: Control
var heightfield_panel: Control
var heightfield_debugger: EditorDebuggerPlugin
var live_debugger: EditorDebuggerPlugin
var author_debugger: EditorDebuggerPlugin
var author_gizmo: EditorNode3DGizmoPlugin
var scene_inspector: EditorInspectorPlugin
var view_controls: Control
var editor_dock: EditorDock
var dock: VBoxContainer
var scope: OptionButton
var pages: Array[Control] = []
var preview_roots: Array[Node3D] = []
var selected_models := {}
var syncing := false
var modal_pending := false
var scan_at := 0
var history_states := {}
var last_history_version := -1
var last_scene: Node

func _enter_tree() -> void:
	if not ClassDB.class_exists("MjEditorDocument"): return
	EditorInterface.get_base_control().set_meta("mujoco_author_plugin", self)
	author_gizmo = preload("author_gizmo.gd").new(); add_node_3d_gizmo_plugin(author_gizmo)
	dock = VBoxContainer.new(); dock.name = "MuJoCo"; dock.custom_minimum_size.x = 280
	scope = OptionButton.new()
	for title in ["MJCF 层级模型", "静态地图", "地形", "场景对象"]: scope.add_item(title)
	dock.add_child(scope)
	editor_dock = EditorDock.new()
	editor_dock.name = "MuJoCo"; editor_dock.title = "MuJoCo"; editor_dock.layout_key = "mujoco_author"
	editor_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	editor_dock.add_child(dock); add_dock(editor_dock)
	panel = AuthorPanel.new(); panel.plugin = self
	map_panel = preload("map_panel.gd").new(); map_panel.plugin = self
	object_panel = preload("object_panel.gd").new(); object_panel.plugin = self
	heightfield_panel = preload("heightfield_panel.gd").new(); heightfield_panel.plugin = self
	live_debugger = preload("live_debugger.gd").new(); add_debugger_plugin(live_debugger)
	heightfield_debugger = preload("heightfield_debugger.gd").new(); add_debugger_plugin(heightfield_debugger)
	heightfield_panel.debugger = heightfield_debugger
	author_debugger = preload("author_debugger.gd").new(); author_debugger.plugin = self; add_debugger_plugin(author_debugger)
	for content in [panel, map_panel, heightfield_panel, object_panel]:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.add_child(content); dock.add_child(scroll); pages.append(scroll)
		Layout.fit(content)
	scope.item_selected.connect(show_scope)
	EditorInterface.get_selection().selection_changed.connect(selection_changed)
	get_undo_redo().history_changed.connect(history_changed)
	scene_changed.connect(scene_switched)
	scene_inspector = preload("scene_inspector.gd").new(); scene_inspector.plugin = self
	add_inspector_plugin(scene_inspector)
	view_controls = preload("view_controls.gd").new(); view_controls.plugin = self
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, view_controls)
	show_scope(0); selection_changed()
	if "--mj-author-test" in OS.get_cmdline_user_args(): call_deferred("run_author_test")
	if "--mj-author-gui" in OS.get_cmdline_user_args(): call_deferred("run_author_gui")
	if "--mj-live-test" in OS.get_cmdline_user_args(): call_deferred("run_live_test")

func _exit_tree() -> void:
	if author_gizmo: remove_node_3d_gizmo_plugin(author_gizmo)
	if is_instance_valid(view_controls):
		view_controls.shutdown(); remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, view_controls); view_controls.free()
	if scene_inspector: remove_inspector_plugin(scene_inspector)
	if EditorInterface.get_selection().selection_changed.is_connected(selection_changed): EditorInterface.get_selection().selection_changed.disconnect(selection_changed)
	if get_undo_redo().history_changed.is_connected(history_changed): get_undo_redo().history_changed.disconnect(history_changed)
	if scene_changed.is_connected(scene_switched): scene_changed.disconnect(scene_switched)
	for debugger in [live_debugger, heightfield_debugger, author_debugger]:
		if debugger:
			if debugger.has_method("shutdown"): debugger.shutdown()
			remove_debugger_plugin(debugger)
	for content in [panel, map_panel, heightfield_panel]:
		if is_instance_valid(content) and content.has_method("shutdown"): content.shutdown()
	for root in preview_roots:
		if is_instance_valid(root): root.free()
	preview_roots.clear()
	if is_instance_valid(editor_dock): remove_dock(editor_dock); editor_dock.free()
	var base := EditorInterface.get_base_control()
	if base.get_meta("mujoco_author_plugin", null) == self: base.remove_meta("mujoco_author_plugin")

func _get_plugin_name() -> String:
	return "MuJoCo"

func show_scope(index: int) -> void:
	scope.select(index)
	for i in pages.size(): pages[i].visible = i == index

func reveal_scope(index: int) -> void:
	show_scope(index)
	if is_instance_valid(editor_dock): editor_dock.make_visible()

func selection_changed() -> void:
	if syncing: return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var node: Node = selected[0] if selected.size() == 1 else null
	if node is MeshInstance3D and node.get_parent() and node.get_parent().has_method("author_kind"):
		node = node.get_parent(); syncing = true
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(node); syncing = false
	panel.select(node)
	if node is Model or (node and node.has_method("author_kind")):
		show_scope(0)
		if node.has_method("author_kind"):
			EditorInterface.inspect_object(node)
			var inspector: Node = EditorInterface.get_inspector()
			while inspector and not inspector is EditorDock: inspector=inspector.get_parent()
			if inspector: inspector.make_visible()
	elif node is Terrain: heightfield_panel.select_target(node); reveal_scope(2)

func attach_author_node(parent: Node, node: Node) -> void:
	parent.add_child(node, true)
	node.owner = EditorInterface.get_edited_scene_root()
	if node is Model and node.author_scene: node.author_scene.refresh_nodes()
	EditorInterface.mark_scene_as_unsaved()

func record_author_command(model: Node, command: Dictionary, result: Dictionary) -> void:
	var history := get_undo_redo()
	history.create_action("MJCF " + str(command.get("op", "edit")), UndoRedo.MERGE_DISABLE, model)
	history.add_do_method(model, "restore_author_snapshot", result.after)
	history.add_undo_method(model, "restore_author_snapshot", result.before)
	history.commit_action()
	author_status_changed(model)

func confirm_author_command(model: Node, command: Dictionary, result: Dictionary) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认关联对象修改"
	var descriptions := PackedStringArray()
	for impact in result.impacts: descriptions.append(str(impact.type) + ": " + str(impact.name))
	dialog.dialog_text = "以下关联对象也将被删除，可整体撤销：\n" + "\n".join(descriptions)
	add_child(dialog)
	dialog.confirmed.connect(func():
		var confirmed := command.duplicate(true); confirmed.confirmed = true
		model.apply_author_command(confirmed); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(520, 300))

func author_changed(model: Node, _pause_only := false) -> void:
	if author_debugger and author_debugger.has_method("pause_model"): author_debugger.pause_model(model)

func author_compiled(model: Node, result: Dictionary) -> void:
	if author_debugger and author_debugger.has_method("apply_model"): author_debugger.apply_model(model, result)
	author_status_changed(model)

func author_status_changed(model: Node) -> void:
	if panel and panel.model == model: panel.refresh()

func scene_switched(root: Node) -> void:
	last_scene = root; last_history_version = -1; history_states.clear(); selected_models.clear()
	selection_changed()

func history_changed() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root or root != last_scene: return
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(root))
	if not history or history.has_redo(): return
	# A new action after undo reuses a version number from the discarded branch.
	# Do not let that branch's cached author snapshot overwrite the new edit.
	for version in history_states.keys():
		if int(version) >= history.get_version(): history_states.erase(version)

func all_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child in root.get_children(): result.append_array(all_nodes(child))
	return result

func _process(_delta: float) -> void:
	if author_debugger: author_debugger.poll(_delta)
	if syncing or modal_pending or Time.get_ticks_msec() < scan_at: return
	scan_at = Time.get_ticks_msec() + 50
	var root := EditorInterface.get_edited_scene_root()
	if not root: return
	if root != last_scene: scene_switched(root)
	# Native drag-and-drop can cross model roots. Reject that before reconciling
	# either source, otherwise it could look like a deletion in the old model.
	for node in all_nodes(root):
		if not node.has_method("author_kind") or not node.source_model: continue
		var original: Node = node.source_model.get_ref()
		if not original or original == node.author_model() or not original.author_scene: continue
		var entity: Dictionary = original.design.entity(node.entity_id)
		if entity.is_empty(): continue
		var parent: Node = original.author_scene.nodes.get(entity.parent_id,original)
		node.reparent(parent,true)
		original.last_error = "仅支持在同一个模型内重新挂载；跨模型移动已撤回。"
		original.author_scene.refresh_nodes()
		author_status_changed(original)
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(root))
	var version := int(history.get_version()) if history else 0
	var current_models := {}; var instance_ids := {}
	for node in all_nodes(root):
		if not node is Model or not node.design: continue
		if node.design_instance_id.is_empty(): node.design_instance_id = Xml.uuid()
		if instance_ids.has(node.design_instance_id):
			node.design_instance_id = Xml.uuid(); node.design = node.design.fork()
			if node.author_scene: node.author_scene.shutdown()
			node.author_scene = preload("res://addons/godot_mujoco/model/author_scene.gd").new(); node.author_scene.initialize(node)
		instance_ids[node.design_instance_id] = true; current_models[node.design_instance_id] = node
	if version != last_history_version and history_states.has(version):
		syncing = true
		for key in current_models:
			if history_states[version].has(key): current_models[key].restore_author_snapshot(history_states[version][key])
		syncing = false
	else:
		for model in current_models.values(): reconcile_nodes(model)
	if version != last_history_version or not history_states.has(version):
		var snapshots := {}
		for key in current_models: snapshots[key] = current_models[key].design.author_snapshot()
		history_states[version] = snapshots; last_history_version = version
	selected_models = current_models

func reconcile_nodes(model: Node) -> void:
	if not model.author_scene or model.author_scene.applying: return
	var manager: RefCounted = model.author_scene
	var seen := {}
	for node in all_nodes(model):
		if not node.has_method("author_kind") or node.author_model() != model: continue
		if seen.has(node.entity_id):
			var result := Commands.execute(model.design, {"op":"duplicate", "id":node.entity_id})
			if not result.error.is_empty(): continue
			for descendant in all_nodes(node):
				if descendant.has_method("author_kind") and result.get("id_map", {}).has(descendant.entity_id):
					descendant.entity_id = result.id_map[descendant.entity_id]; manager.nodes[descendant.entity_id] = descendant
			model.restore_author_snapshot(result.after); return
		seen[node.entity_id] = true
		var item: Dictionary = model.design.entity(node.entity_id)
		if item.is_empty(): continue
		if str(node.name) != manager.last_names.get(node.entity_id, str(node.name)):
			model.apply_author_command({"op":"rename", "id":node.entity_id, "name":str(node.name)}, false); return
		var parent_id: String = node.get_parent().entity_id if node.get_parent().has_method("author_kind") else ""
		if parent_id != item.parent_id:
			model.apply_author_command({"op":"reparent", "id":node.entity_id, "parent_id":parent_id}, false); return
	for item in model.design.entities():
		if seen.has(item.id): continue
		var result := Commands.execute(model.design, {"op":"delete", "id":item.id})
		if result.get("confirmation_required", false):
			modal_pending = true
			var dialog := ConfirmationDialog.new(); dialog.title = "删除关联对象"
			var labels := PackedStringArray()
			for impact in result.impacts: labels.append(str(impact.type) + ": " + str(impact.name))
			dialog.dialog_text = "删除节点还会删除：\n" + "\n".join(labels); add_child(dialog)
			dialog.confirmed.connect(func():
				modal_pending = false; model.apply_author_command({"op":"delete", "id":item.id, "confirmed":true}, false); dialog.queue_free())
			dialog.canceled.connect(func():
				modal_pending = false
				var undo := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(model))
				if undo and undo.has_undo(): undo.undo()
				manager.refresh_nodes(); dialog.queue_free())
			dialog.popup_centered(Vector2i(520, 300))
		else: model.apply_author_command({"op":"delete", "id":item.id, "confirmed":true}, false)
		return

func _apply_changes() -> void:
	for model in selected_models.values():
		if is_instance_valid(model) and model.author_scene: model.author_scene.flush_transforms()

func _build() -> bool:
	_apply_changes()
	var root := EditorInterface.get_edited_scene_root()
	if not root: return true
	for node in all_nodes(root):
		if node is Model and node.design:
			if not node.global_transform.is_finite() or not node.global_basis.orthonormalized().is_equal_approx(node.global_basis) or not node.global_basis.get_scale().is_equal_approx(Vector3.ONE) or node.global_basis.determinant() <= 0:
				push_warning("MuJoCo 模型摆放必须为刚性变换："+str(node.name)); return false
			if node.design.validated_revision != node.design.revision or not node.design.validation_error.is_empty() or (node.author_scene and (node.author_scene.due_ms > 0 or node.author_scene.compiler.busy())):
				push_warning("MuJoCo 设计未通过当前版本验证：" + str(node.name)); return false
	return true

func create_preview_root(title: String) -> Node3D:
	var root := Node3D.new(); root.name = title
	EditorInterface.get_editor_viewport_3d(0).add_child(root); preview_roots.append(root)
	return root

func frame_preview(_center: Vector3, _distance: float) -> bool:
	EditorInterface.set_main_screen_editor("3D")
	return true

func select_preview_target(_path := "") -> void:
	pass

func add_mesh_asset(model: Node, parent_id: String, path: String, geom_id := "") -> void:
	var service := preload("res://addons/godot_mujoco/model/compile_service.gd").new()
	add_child(service)
	var reference := weakref(model)
	var document_id: String = model.design.document_id
	service.completed.connect(func(result):
		var target: Node = reference.get_ref()
		if not result.get("success",false): panel.status.text = result.get("error","Mesh import failed")
		elif target and target.design and target.design.document_id == document_id:
			finish_mesh_asset(target,parent_id,path,result,geom_id)
		service.queue_free())
	service.status_changed.connect(func(message): panel.status.text=message)
	service.submit({"op":"mesh_asset","source":path,"document_id":document_id})

func finish_mesh_asset(model: Node, parent_id: String, source_path: String, asset: Dictionary, geom_id: String) -> void:
	var before: Dictionary = model.design.author_snapshot()
	var tree: Dictionary = model.design.tree.duplicate(true)
	var mesh_name := Commands.unique_name(tree, "mesh", source_path.get_file().get_basename().validate_filename())
	Xml.section(tree, "asset", true).children.append({"tag":"mesh", "id":Xml.uuid(), "attrs":{"name":mesh_name, "file":asset.path}, "children":[]})
	var after := before.duplicate(true); after.tree = tree; after.dependencies[asset.path] = asset.sha256
	var temp := Author.new(); temp.restore_author(after)
	var result := Commands.execute(temp, {"op":"add_geom", "id":parent_id, "type":"mesh", "mesh":mesh_name} if geom_id.is_empty() else {"op":"set","id":geom_id,"values":{"mesh":mesh_name}})
	if result.error.is_empty(): result.before = before; record_author_command(model, {"op":"add_mesh"}, result)

func export_author(model: Node, directory: String) -> String:
	if not model.design: return "Select a node author model"
	if model.design.validated_revision != model.design.revision: return "请先修复模型并等待后台验证完成。"
	var copy: Dictionary = model.design.tree.duplicate(true)
	DirAccess.make_dir_recursive_absolute(directory.path_join("assets"))
	for element in Xml.walk(copy):
		for key in element.get("attrs", {}):
			if key not in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"]: continue
			var original: String = element.attrs[key]
			var name := FileAccess.get_sha256(original) + "." + original.get_extension()
			if DirAccess.copy_absolute(original, directory.path_join("assets/" + name)) != OK: return "导出依赖失败：" + original
			element.attrs[key] = "assets/" + name
	if not model.design.initial_pose.is_empty():
		var qpos: Array = model.design.compiled_snapshot.get("state",{}).get("qpos",[])
		var keyframes := Xml.section(copy,"keyframe",true)
		keyframes.children.append({"tag":"key","id":Xml.uuid(),"attrs":{"name":Commands.unique_name(copy,"key","author_initial"),"qpos":Xml.numeric_text(qpos)},"children":[]})
	var file := FileAccess.open(directory.path_join("model.xml"), FileAccess.WRITE)
	if not file: return "无法保存导出的 MJCF"
	file.store_string(Xml.write(copy))
	return "已导出 model.xml 与 assets/"

func run_author_test() -> void:
	var script = load("res://editor_acceptance.gd")
	if script:
		var runner = script.new(); EditorInterface.get_base_control().set_meta("mj_author_test", runner); runner.run(self)

func execute_game_design(world: Node, command: Dictionary) -> Dictionary:
	if not world: return {"success":false, "error":"没有匹配的编辑器场景。"}
	var operation: String = command.get("op", "")
	if operation == "duplicate_model":
		var source: Node
		for node in all_nodes(world):
			if node is Model and node.design_instance_id == command.get("instance_id", ""): source = node; break
		if not source: return {"success":false, "error":"找不到要复制的设计模型。"}
		var copy: Node3D = source.duplicate()
		copy.design = source.design.fork()
		copy.design_instance_id = Xml.uuid()
		copy.name = command.get("name", str(source.name) + "_copy")
		copy.transform = source.transform
		if command.get("pose") is Transform3D: copy.transform = source.get_parent().global_transform.affine_inverse() * command.pose
		else: copy.position.x += 2.0
		var undo := get_undo_redo()
		undo.create_action("复制模型（游戏按钮）", UndoRedo.MERGE_DISABLE, world)
		undo.add_do_method(self, "attach_author_node", source.get_parent(), copy)
		undo.add_undo_method(source.get_parent(), "remove_child", copy)
		undo.add_do_reference(copy)
		undo.commit_action()
		return {"success":true, "error":"", "instance_id":copy.design_instance_id}
	if operation == "terrain_update":
		var target := world.get_node_or_null(command.get("path", ""))
		if not target is Terrain or not target.design: return {"success":false, "error":"找不到地形设计节点。"}
		var data: Resource = target.design.duplicate(true)
		if command.get("heights") is PackedFloat32Array: data.heights = command.heights.duplicate()
		elif command.get("index") is int or command.get("index") is float:
			var index: int = int(command.index)
			if not is_finite(float(command.index)) or float(index) != float(command.index): return {"success":false, "error":"地形索引必须为整数。"}
			if index < 0 or index >= data.heights.size(): return {"success":false, "error":"地形索引超出范围。"}
			data.heights[index] += float(command.get("delta", .1))
		var error: String = data.validate()
		if not error.is_empty(): return {"success":false, "error":error}
		var undo := get_undo_redo()
		undo.create_action("编辑地形（游戏按钮）", UndoRedo.MERGE_DISABLE, target)
		undo.add_do_property(target, "design", data)
		undo.add_undo_property(target, "design", target.design)
		undo.commit_action()
		return {"success":true, "error":""}
	return {"success":false, "error":"Unsupported editor design request"}

func run_author_gui() -> void:
	var runner = load("res://gui_probe.gd").new()
	EditorInterface.get_base_control().set_meta("mj_author_gui",runner)
	runner.run(self)

func run_live_test() -> void:
	var runner = load("res://live_editor_acceptance.gd").new()
	EditorInterface.get_base_control().set_meta("mj_live_test",runner)
	runner.run(self)
