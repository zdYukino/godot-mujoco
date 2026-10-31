@tool
extends VBoxContainer
## Scene-authoring shortcut only: never installs runtime UI implicitly.
const Viewer = preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Host = preload("res://addons/godot_mujoco/model/environment_host.gd")
var plugin: EditorPlugin
var add_button: Button
var target_note: Label

func _ready() -> void:
	add_button = Button.new()
	add_button.name = "AddMuJoCoRuntimePanel"
	add_button.text = "添加 MuJoCo 运行面板"
	add_button.tooltip_text = "在所选 World / EnvironmentHost 旁添加原版 MuJoCo 面板；Godot Extras（F11）需单独添加。"
	add_child(add_button)
	add_button.pressed.connect(add_selected)
	target_note = Label.new()
	target_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(target_note)
	EditorInterface.get_selection().selection_changed.connect(refresh)
	plugin.scene_changed.connect(_scene_changed)
	refresh()

func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(refresh):
		EditorInterface.get_selection().selection_changed.disconnect(refresh)
	if is_instance_valid(plugin) and plugin.scene_changed.is_connected(_scene_changed):
		plugin.scene_changed.disconnect(_scene_changed)

func _scene_changed(_root: Node) -> void:
	refresh()

func selection_state() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if not root: return {"reason":"请先打开可编辑场景。"}
	if selected.size() != 1: return {"reason":"请选择一个 Runtime World 或 EnvironmentHost。"}
	var target: Node = selected[0]
	if not (target is World or target is Host): return {"reason":"所选节点不是 Runtime World / EnvironmentHost。"}
	if target == root: return {"reason":"目标是场景根节点：请先提供普通场景根节点，面板需要可保存的同级位置。"}
	if not root.is_ancestor_of(target) or not _editable(root, target):
		return {"reason":"目标或其父节点不可编辑；请在所属场景中添加，或启用实例的可编辑子节点。"}
	return {"target":target,"root":root,"reason":"目标：" + str(root.get_path_to(target))}

func _editable(root: Node, target: Node) -> bool:
	# Instance children may only be authored when their instance is explicitly editable.
	for node in [target, target.get_parent()]:
		if node == root: continue
		if not is_instance_valid(node.owner): return false
		if node.owner != root and not root.is_editable_instance(node.owner): return false
	var ancestor := target.get_parent()
	while ancestor != root:
		if not ancestor.scene_file_path.is_empty() and not root.is_editable_instance(ancestor): return false
		ancestor = ancestor.get_parent()
		if not ancestor: return false
	return true

func refresh() -> void:
	if not is_instance_valid(add_button): return
	var state := selection_state()
	add_button.disabled = not state.has("target")
	target_note.text = state.reason

func _existing(node: Node, target: Node) -> Node:
	if node is Viewer and ((target is World and node.world == target) or (target is Host and node.environment_host == target)):
		return node
	for child in node.get_children():
		var found := _existing(child, target)
		if found: return found
	return null

func _select(node: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	EditorInterface.edit_node(node)

func add_selected() -> void:
	var state := selection_state()
	if not state.has("target"):
		refresh()
		return
	var target: Node = state.target
	var root: Node = state.root
	var existing := _existing(root, target)
	if existing:
		_select(existing)
		return
	var component := Viewer.new()
	component.name = "RuntimeViewer"
	var history := plugin.get_undo_redo()
	history.create_action("添加 MuJoCo 运行面板", UndoRedo.MERGE_DISABLE, root)
	history.add_do_method(self, "_attach", target.get_parent(), component, root, target)
	history.add_do_reference(component)
	history.add_undo_method(self, "_detach", component, target)
	history.commit_action()

func _attach(parent: Node, component: Node, root: Node, target: Node) -> void:
	parent.add_child(component, true)
	component.owner = root
	component.world = target if target is World else null
	component.environment_host = target if target is Host else null
	_select(component)
	EditorInterface.mark_scene_as_unsaved()

func _detach(component: Node, target: Node) -> void:
	component.world = null
	component.environment_host = null
	component.get_parent().remove_child(component)
	_select(target)
	EditorInterface.mark_scene_as_unsaved()
