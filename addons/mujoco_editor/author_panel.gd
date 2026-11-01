@tool
extends VBoxContainer
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
var plugin: EditorPlugin
var model: Node
var selected_id := ""
var status: Label
var importer: Node
var show_visuals := true
var show_collisions := false
var runtime_targets: OptionButton
var runtime_status: Label
var runtime_target_key := ""
var preset_service: Node
var preset_path := ""
var preset_target: WeakRef
var preset_revision := -1

func button(label: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label
	result.pressed.connect(callback)
	add_child(result)
	return result

func _ready() -> void:
	button("载入 MJCF", import_dialog)
	button("导出 MJCF 与依赖", export_dialog)
	var help := Label.new()
	help.text = "场景树中选部件，Inspector 修改参数，操作轴移动/旋转。Ctrl+D 复制，Ctrl+S 保存。运行中修改会自动暂停，编译成功后手动继续。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	button("新增 body", func(): add_entity("body"))
	for shape in ["box", "sphere", "cylinder", "capsule", "ellipsoid", "plane"]:
		button("新增 " + shape, add_entity.bind("geom", shape))
	button("导入 mesh 几何", mesh_dialog)
	var add_joint := button("新增 joint", add_entity.bind("joint", "free"))
	add_joint.tooltip_text = "默认创建 free joint；选中后可在 Inspector 的 Mjcf → Type 中切换关节类型。"
	button("复制选中部件", func(): command({"op":"duplicate"}))
	button("删除选中部件", func(): command({"op":"delete"}))
	button("取消后台编译", func():
		if model and model.author_scene:
			model.author_scene.cancel_compile()
			if plugin.author_debugger: plugin.author_debugger.cancel_model(model))
	button("恢复上次有效设计", restore_valid)
	importer = Service.new()
	add_child(importer)
	importer.completed.connect(import_finished)
	importer.status_changed.connect(func(message): status.text = message)
	var separator := HSeparator.new(); add_child(separator)
	button("导出当前设计控制预设", save_preset_dialog)
	runtime_targets = OptionButton.new(); runtime_targets.fit_to_longest_item = false; add_child(runtime_targets)
	runtime_targets.item_selected.connect(func(index):
		runtime_target_key = runtime_targets.get_item_metadata(index); refresh_runtime_targets())
	runtime_status = Label.new(); runtime_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(runtime_status)
	button("应用整份运行预设", runtime_preset_dialog)
	button("取消待提交运行预设", func(): plugin.author_debugger.send_preset(runtime_target_key,"cancel_preset",{}))
	preset_service = Service.new(); add_child(preset_service)
	preset_service.completed.connect(preset_captured)
	plugin.author_debugger.instances_changed.connect(refresh_runtime_targets)
	refresh_runtime_targets()
	refresh()

func select(node: Node) -> void:
	selected_id = ""
	model = null
	if node and node.has_method("author_kind"):
		model = node.author_model()
		selected_id = node.entity_id
	elif node is Model: model = node
	refresh()

func refresh() -> void:
	if not status: return
	if not is_instance_valid(model):
		model = null
		status.text = "选择模型根节点或 body / geom / joint；也可直接载入 MJCF。"
	elif not model.design:
		status.text = "请选择或导入当前 MJCF 作者设计。"
	else:
		status.text = "%s · 设计版本 %d\n%s" % [model.name, model.design.revision, model.author_scene.compiled_status if model.author_scene else "初始化"]
		if not model.last_error.is_empty(): status.text += "\n" + model.last_error

func import_dialog() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.xml ; MJCF"])
	add_child(dialog)
	dialog.file_selected.connect(func(path): import_file(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(.65)

func import_file(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root is Node3D:
		status.text = "请先打开或新建一个 3D 场景。"
		return
	if path.get_extension().to_lower() != "xml":
		status.text = "仅支持 MJCF XML，请重新导入源文件。"
		return
	var request := {"op":"import", "source":path, "generation":"import", "revision":0}
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = selected[0] if selected.size() == 1 else null
	while parent and not parent is World: parent = parent.get_parent()
	if parent and parent.world_design: request.context = preload("res://addons/godot_mujoco/model/collision_settings.gd").context(parent,parent.world_design)
	importer.submit(request)

func import_finished(result: Dictionary) -> void:
	if not result.has("author"): status.text = result.get("error", "导入失败"); return
	var design := Author.new()
	var error: String = design.restore_author(result.author)
	if not error.is_empty(): status.text = error; return
	if result.get("success", false):
		error = preload("res://addons/godot_mujoco/model/author_builder.gd").apply_result(design, result)
		if not error.is_empty(): status.text = error; return
	else:
		design.validation_error = result.get("error", "设计尚未完成")
	create_model(design)

func create_model(design: Resource) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var parent: Node = root
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if selected.size() == 1 and selected[0] is Node3D: parent = selected[0]
	while parent and parent.has_method("author_kind"): parent = parent.get_parent()
	if parent is Model: parent = parent.get_parent()
	var world: Node = parent
	while world and not world is World: world = world.get_parent()
	var created_world: Node
	if not world:
		created_world = World.new()
		created_world.name = "MuJoCoWorld"
		created_world.world_design = design.fork()
		world = created_world
	elif not world.world_design:
		status.text = "World 需要当前作者设计，请重新导入 MJCF。"
		return
	var instance := Model.new()
	instance.name = str(design.tree.attrs.get("model", "Model")).validate_node_name()
	instance.design = design
	var history := plugin.get_undo_redo()
	history.create_action("载入 MJCF 层级节点", UndoRedo.MERGE_DISABLE, root)
	if created_world:
		history.add_do_method(plugin, "attach_author_node", parent, created_world)
		history.add_undo_method(parent, "remove_child", created_world)
		history.add_do_reference(created_world)
	history.add_do_method(plugin, "attach_author_node", world, instance)
	history.add_undo_method(world, "remove_child", instance)
	history.add_do_reference(instance)
	history.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(instance)
	select(instance)

func parent_identity() -> String:
	if not model or selected_id.is_empty(): return ""
	var item: Dictionary = model.design.entity(selected_id)
	return selected_id if item.get("kind") == "body" else str(item.get("parent_id", ""))

func add_entity(kind: String, type := "") -> void:
	if not model or not model.design: status.text = "请先选择一个节点化 MJCF 模型。"; return
	var operation := {"op":"add_" + kind, "id":parent_identity()}
	if not type.is_empty(): operation.type = type
	var result: Dictionary = model.apply_author_command(operation)
	if not result.get("error", "").is_empty(): status.text = result.error
	elif kind == "joint" and result.has("selected") and model.author_scene:
		var joint: Node = model.author_scene.nodes.get(result.selected)
		if joint:
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(joint)

func command(value: Dictionary) -> void:
	if not model or not model.design or selected_id.is_empty(): return
	value.id = selected_id
	var result: Dictionary = model.apply_author_command(value)
	if not result.get("error", "").is_empty(): status.text = result.error

func restore_valid() -> void:
	if not model or not model.author_scene or model.author_scene.last_valid.is_empty(): return
	var result := {"before":model.design.author_snapshot(), "after":model.author_scene.last_valid}
	plugin.record_author_command(model, {"op":"restore"}, result)

func mesh_dialog() -> void:
	if not model or not model.design: return
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.obj,*.stl ; MuJoCo mesh"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		plugin.add_mesh_asset(model, parent_identity(), path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(.65)

func export_dialog() -> void:
	if not model or not model.design: return
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	add_child(dialog)
	dialog.dir_selected.connect(func(path):
		status.text = plugin.export_author(model, path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(.65)

func update_overlay_visibility() -> void:
	pass # ViewControls owns render visibility; it never edits physical design.

func shutdown() -> void:
	if importer: importer.cancel()
	if preset_service: preset_service.cancel()
	if plugin.author_debugger.instances_changed.is_connected(refresh_runtime_targets): plugin.author_debugger.instances_changed.disconnect(refresh_runtime_targets)

func refresh_runtime_targets() -> void:
	if not runtime_targets: return
	var targets: Dictionary = plugin.author_debugger.runtime_targets()
	runtime_targets.clear()
	for key in targets:
		runtime_targets.add_item(str(targets[key].label))
		runtime_targets.set_item_metadata(runtime_targets.item_count-1,key)
		if key == runtime_target_key: runtime_targets.select(runtime_targets.item_count-1)
	if not targets.has(runtime_target_key): runtime_target_key = str(targets.keys()[0]) if not targets.is_empty() else ""
	if runtime_target_key.is_empty(): runtime_status.text = "F5 运行后可选择实例应用控制预设。"; return
	var value: Dictionary = targets[runtime_target_key]
	var outcome: Dictionary = value.get("preset", {})
	runtime_status.text = "revision %d · %s" % [value.revision,"pending" if value.pending else "ready"]
	if not outcome.is_empty(): runtime_status.text += " · %s #%d" % [outcome.get("status",""),outcome.get("request",0)]
	if not value.get("error", "").is_empty(): runtime_status.text += "\n" + str(value.error)

func runtime_preset_dialog() -> void:
	var targets: Dictionary = plugin.author_debugger.runtime_targets()
	if not targets.has(runtime_target_key): return
	var key := runtime_target_key
	var revision: int = targets[key].revision
	var dialog := EditorFileDialog.new(); dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.json ; 控制预设 v2"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var current: Dictionary = plugin.author_debugger.runtime_targets()
		var loaded: Dictionary = preload("control_presets.gd").read_file(path)
		if key != runtime_target_key or not current.has(key) or current[key].revision != revision: runtime_status.text = "运行目标或版本已变化，请重新选择预设。"
		elif not loaded.error.is_empty(): runtime_status.text = loaded.error
		elif not plugin.author_debugger.send_preset(key,"preset",{"preset":loaded.value}): runtime_status.text = "目标不可用或正在提交。"
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.65)

func save_preset_dialog() -> void:
	if not model or not model.design: return
	var target := weakref(model)
	var revision: int = model.design.revision
	var dialog := EditorFileDialog.new(); dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE; dialog.filters = PackedStringArray(["*.json ; 控制预设 v2"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var selected: Node = target.get_ref()
		if selected and selected.design.revision == revision:
			preset_target = target; preset_revision = revision; preset_path = path
			preset_service.submit({"op":"capture_preset", "author":selected.design.author_snapshot(), "context":selected.compilation_context()})
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.65)

func preset_captured(result: Dictionary) -> void:
	if not result.get("success",false): status.text = result.get("error","预设导出失败"); return
	var target: Node = preset_target.get_ref() if preset_target else null
	if not target or target.design.revision != preset_revision: status.text = "设计已变化，请重新导出预设。"; return
	var file := FileAccess.open(preset_path+".tmp",FileAccess.WRITE)
	if not file: status.text = "无法写入预设"; return
	file.store_string(JSON.stringify(result.preset,"\t")); file.close()
	status.text = "控制预设已导出" if DirAccess.rename_absolute(preset_path+".tmp",preset_path)==OK else "无法保存预设"
