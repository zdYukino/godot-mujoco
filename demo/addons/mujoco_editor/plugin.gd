@tool
extends EditorPlugin
const Terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const State = preload("editor_state.gd")
const EditorPanel = preload("panel.gd")
var map_panel:Control
var object_panel:Control
var heightfield_debugger:EditorDebuggerPlugin
var heightfield_panel:Control
var live_debugger: EditorDebuggerPlugin
var panel: Control
var state: RefCounted
var syncing_draft_selection := false
var view_controls: Control
var scene_inspector: EditorInspectorPlugin
var dock: VBoxContainer
var pages: Array[Control] = []
var scope: OptionButton
var selection_label: Label
var preview_roots: Array[Node3D] = []
const Layout = preload("property_layout.gd")
const META := "mujoco_editor_document"

func _enter_tree() -> void:
	if not ClassDB.class_exists("MjEditorDocument"):
		push_error("MuJoCo editor requires the rebuilt Linux godot_mujoco GDExtension. Build and restart the editor.")
		return
	dock = VBoxContainer.new(); dock.name = "MuJoCo"
	dock.custom_minimum_size.x = 280
	selection_label = Label.new(); selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; dock.add_child(selection_label)
	scope = OptionButton.new()
	for title in ["MJCF 文档", "静态地图草稿", "地形", "创建场景对象"]: scope.add_item(title)
	dock.add_child(scope)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	map_panel=preload("map_panel.gd").new(); map_panel.plugin=self

	object_panel=preload("object_panel.gd").new();object_panel.plugin=self

	live_debugger = preload("live_debugger.gd").new()
	add_debugger_plugin(live_debugger)
	heightfield_debugger=preload("heightfield_debugger.gd").new()
	add_debugger_plugin(heightfield_debugger)
	heightfield_panel=preload("heightfield_panel.gd").new()
	heightfield_panel.plugin=self;heightfield_panel.debugger=heightfield_debugger

	var base := EditorInterface.get_base_control()
	base.set_meta("mujoco_active_plugin",self)
	state = base.get_meta(META) if base.has_meta(META) else State.new()
	base.set_meta(META, state)
	state.activate()
	panel = EditorPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.plugin = self
	panel.state = state
	for content in [panel, map_panel, heightfield_panel, object_panel]:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		dock.add_child(scroll); pages.append(scroll)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		Layout.fit(content)
	scope.item_selected.connect(show_scope)
	EditorInterface.get_selection().selection_changed.connect(selection_changed)
	scene_changed.connect(scene_switched)
	set_input_event_forwarding_always_enabled()
	scene_inspector=preload("scene_inspector.gd").new(); scene_inspector.plugin=self; add_inspector_plugin(scene_inspector)
	view_controls=preload("view_controls.gd").new(); view_controls.plugin=self
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU,view_controls)
	show_scope(0); selection_changed()
	if "--ui-layout-test" in OS.get_cmdline_user_args() and not base.has_meta("mj_layout_started"):
		base.set_meta("mj_layout_started",true)
		call_deferred("_run_layout_test")
	if "--static-map-test" in OS.get_cmdline_user_args(): call_deferred("_run_static_map_test")
	if "--mj-editor-test" in OS.get_cmdline_user_args() and not base.has_meta("mj_test_started"):
		base.set_meta("mj_test_started", true)
		call_deferred("_run_acceptance")

func _exit_tree() -> void:
	if view_controls:
		view_controls.shutdown(); remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU,view_controls); view_controls.free(); view_controls=null
	if scene_inspector: remove_inspector_plugin(scene_inspector); scene_inspector=null
	if scene_changed.is_connected(scene_switched): scene_changed.disconnect(scene_switched)
	if EditorInterface.get_selection().selection_changed.is_connected(selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(selection_changed)
	if map_panel:
		map_panel.shutdown(); map_panel.free(); map_panel=null
	if object_panel:
		object_panel.free();object_panel=null
	if heightfield_panel:
		heightfield_panel.shutdown();heightfield_panel.free();heightfield_panel=null
	if heightfield_debugger:
		heightfield_debugger.shutdown();remove_debugger_plugin(heightfield_debugger);heightfield_debugger=null
	if live_debugger:
		live_debugger.shutdown()
		remove_debugger_plugin(live_debugger)
		live_debugger = null
	if panel:
		panel.shutdown()
		panel.free()
		panel = null
	if state:
		state.deactivate()
	if dock:
		remove_control_from_docks(dock); dock.free(); dock=null
	pages.clear(); preview_roots.clear()

func _has_main_screen() -> bool:
	return false

func _get_plugin_name() -> String:
	return "MuJoCo"

func _make_visible(_value: bool) -> void:
	pass # Dock visibility does not control the explicit Run / Pause state.

func create_preview_root(title: String) -> Node3D:
	var root := Node3D.new(); root.name = title
	# Sibling of the edited scene, in its native viewport's World3D. Never set owner.
	EditorInterface.get_editor_viewport_3d(0).add_child(root)
	preview_roots.append(root)
	return root

func frame_preview(center: Vector3, distance: float) -> bool:
	EditorInterface.set_main_screen_editor("3D")
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var surface: Control
	# Godot 4.7's native viewport receives its navigation shortcuts on this
	# sibling input surface. Use its public signal, never mutate Camera3D.
	for child in viewport.get_parent().get_parent().get_children():
		if child.get_class()=="Control" and child.focus_mode==Control.FOCUS_ALL and not child.get_signal_connection_list("gui_input").is_empty():
			surface=child; break
	if not surface:
		push_warning("原生 3D 取景输入界面不可用"); return false
	var event := InputEventKey.new(); event.keycode=KEY_F; event.pressed=true
	var shortcuts: Variant=EditorInterface.get_editor_settings().get("shortcuts")
	if shortcuts is Array:
		for entry in shortcuts:
			if entry is Dictionary and entry.get("name")=="spatial_editor/focus_aabb":
				var shortcut: Shortcut=entry.get("shortcut")
				if shortcut and not shortcut.events.is_empty() and shortcut.events[0] is InputEventKey:
					event=shortcut.events[0].duplicate(); event.pressed=true
	var proxy := MeshInstance3D.new(); proxy.name="MuJoCoFrameBounds"
	var mesh := BoxMesh.new(); mesh.size=Vector3.ONE*maxf(distance/(1.5*sqrt(3.0)),.01)
	proxy.mesh=mesh; proxy.visible=false; viewport.add_child(proxy); proxy.global_position=center
	var selection := EditorInterface.get_selection()
	var previous := selection.get_selected_nodes()
	var blocked := selection.is_blocking_signals()
	selection.set_block_signals(true); selection.clear(); selection.add_node(proxy)
	# Native focus computes bounds synchronously, including the lazy selection
	# list update. No frame is yielded with the temporary selection installed.
	surface.gui_input.emit(event)
	selection.clear()
	for node in previous:
		if is_instance_valid(node) and node.is_inside_tree(): selection.add_node(node)
	selection.set_block_signals(blocked); proxy.free()
	return true

func reveal_scope(index: int) -> void:
	show_scope(index)
	var tabs := dock.get_parent() as TabContainer
	if tabs: tabs.current_tab=tabs.get_tab_idx_from_control(dock)

func show_scope(index: int) -> void:
	scope.select(index)
	for i in pages.size(): pages[i].visible = i == index
	if panel and is_instance_valid(panel.preview_root): panel.preview_root.visible = index == 0
	if map_panel and is_instance_valid(map_panel.world): map_panel.world.visible = index == 1

func selection_changed() -> void:
	if syncing_draft_selection: return
	var selected_nodes := EditorInterface.get_selection().get_selected_nodes()
	selection_label.text = "场景选择：" + (str(selected_nodes[0].name) if selected_nodes.size() == 1 else "无 / 多选") + " · 对象属性见右侧 Inspector"
	if selected_nodes.size() != 1: return
	var node: Node = selected_nodes[0]
	if node is Terrain:
		show_scope(2)
	elif node is Model:
		show_scope(0)
	var map_root: Node = node
	while map_root and not map_root.has_meta("map_specs"): map_root=map_root.get_parent()
	if map_root and not map_panel.scene_map_path.is_empty() and EditorInterface.get_edited_scene_root().get_node_or_null(map_panel.scene_map_path)==map_root:
		var visual:=map_root.get_node_or_null("Visual")
		if visual and (node==visual or visual.is_ancestor_of(node)):
			var path:=str(visual.get_path_to(node))
			if map_panel.items.has(path): map_panel.items[path].select(0); map_panel.select_tree(); show_scope(1)
		var terrain_node: Node=node
		while terrain_node and terrain_node.get_parent()!=map_root: terrain_node=terrain_node.get_parent()
		if terrain_node is Terrain and map_panel.items.has(str(terrain_node.name)):
			map_panel.items[str(terrain_node.name)].select(0); map_panel.select_tree(); show_scope(1)
	# Scene-owned values remain in Godot's native Inspector, including world options.

func scene_switched(_root: Node) -> void:
	# Keep document drafts, but remove their rendered nodes from the previous scene.
	if panel:
		for mesh in panel.meshes.values(): mesh.free()
		panel.meshes.clear()
	if map_panel:
		map_panel.clear_preview(); map_panel.reset_independent_preview()
	if heightfield_panel: heightfield_panel._clear_preview()
	call_deferred("refresh_previews")

func refresh_previews() -> void:
	if panel: panel.rebuild_meshes()
	if map_panel: map_panel.rebuild()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.alt_pressed:
		if scope.selected == 0:
			panel.camera=camera
			if not panel.pick_geometry(event.position).is_empty(): return AFTER_GUI_INPUT_STOP
		elif scope.selected == 1:
			map_panel.camera=camera
			if map_panel.pick(event.position): return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _save_external_data() -> void:
	if panel:
		panel.save_recovery()

func _get_unsaved_status(_for_scene: String) -> String:
	if map_panel and map_panel.session.dirty: return "静态地图有未保存草稿，请保存独立地图包。"
	if heightfield_panel and heightfield_panel.dirty: return "地形有未应用草稿，请应用到场景或 Discard。"
	return "MuJoCo document has unsaved edits. Use Save document; recovery is retained under user://." if state and (state.dirty or (panel and panel.pending)) else ""

func _run_acceptance() -> void:
	var script = load("res://acceptance.gd")
	if script:
		var runner = script.new()
		EditorInterface.get_base_control().set_meta("mj_test_runner", runner)
		runner.run(self)

func _run_static_map_test() -> void:
	var runner = load("res://map_editor_test.gd").new()
	EditorInterface.get_base_control().set_meta("map_test_runner",runner)
	runner.run(self)

func _run_layout_test() -> void:
	var runner = load("res://layout.gd").new()
	EditorInterface.get_base_control().set_meta("mj_layout_runner",runner)
	runner.run(self)

func select_preview_target(map_path := "") -> void:
	if syncing_draft_selection: return
	var target: Node
	var root:=EditorInterface.get_edited_scene_root()
	if not map_path.is_empty() and root and not map_panel.scene_map_path.is_empty():
		var map:=root.get_node_or_null(map_panel.scene_map_path)
		if map:
			target=map.get_node_or_null(NodePath("Visual/"+map_path))
			if not target: target=map.get_node_or_null(NodePath(map_path))
	var selection:=EditorInterface.get_selection()
	var previous:=selection.get_selected_nodes()
	if (target and previous.size()==1 and previous[0]==target) or (not target and previous.is_empty()): return
	syncing_draft_selection=true
	selection.clear()
	if target: selection.add_node(target)
	syncing_draft_selection=false
