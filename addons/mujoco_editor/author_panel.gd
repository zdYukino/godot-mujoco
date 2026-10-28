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

func button(label: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = label
	result.pressed.connect(callback)
	add_child(result)
	return result

func _ready() -> void:
	button("载入 MJCF / 模型包", import_dialog)
	button("升级选中模型为层级节点", upgrade_selected)
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
		status.text = "旧模型资源：点击升级后直接编辑层级节点。"
	else:
		status.text = "%s · 设计版本 %d\n%s" % [model.name, model.design.revision, model.author_scene.compiled_status if model.author_scene else "初始化"]
		if not model.last_error.is_empty(): status.text += "\n" + model.last_error

func import_dialog() -> void:
	var dialog := EditorFileDialog.new()
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.xml ; MJCF", "*.tres ; Saved MuJoCo model", "*.gmj.json ; Legacy document"])
	add_child(dialog)
	dialog.file_selected.connect(func(path): import_file(path); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(.65)

func import_file(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if not root is Node3D:
		status.text = "请先打开或新建一个 3D 场景。"
		return
	if path.get_extension() == "tres":
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var result := Author.from_legacy(resource)
		if not result.error.is_empty(): status.text = result.error; return
		import_legacy(result.design,path)
	elif path.ends_with(".gmj.json"):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or not value.get("xml") is String:
			status.text = "Invalid legacy document"
			return
		var result := Author.from_snapshot(value,path.get_base_dir())
		if not result.error.is_empty(): status.text = result.error; return
		import_legacy(result.design,path)
	else:
		importer.submit({"op":"import", "source":path, "generation":"import", "revision":0})

func import_legacy(design: Resource, path: String) -> void:
	importer.submit({"op":"import_author","author":design.author_snapshot(),"source":path,"source_sha256":FileAccess.get_sha256(path),"generation":"import","revision":design.revision})

func import_finished(result: Dictionary) -> void:
	if not result.has("author"): status.text = result.get("error", "导入失败"); return
	var design := Author.new()
	var error: String = design.restore_author(result.author)
	if not error.is_empty(): status.text = error; return
	if result.get("success", false):
		design.cache_path = result.directory.path_join("result.bin")
		design.cached_entities = result.entities
		design.cached_geometry = result.geometry
		design.collision_geometry = result.collision_geometry
		design.compiled_snapshot = result.snapshot
		design.validated_revision = design.revision
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
		created_world.world_design = design
		world = created_world
	elif not world.world_design:
		var error: String = world.upgrade_author_world()
		if not error.is_empty(): status.text=error; return
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

func upgrade_selected() -> void:
	if not model: return
	var error: String = model.upgrade_author_model()
	if not error.is_empty(): status.text = error
	else: EditorInterface.mark_scene_as_unsaved(); refresh()

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
