@tool
extends RefCounted
var passed := 0
var failed := 0
var tree: SceneTree
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ", label)
func settle() -> void:
	for i in 8: await tree.process_frame
func count_viewports(node: Node) -> int:
	var total := 1 if node is SubViewport or node is SubViewportContainer else 0
	for child in node.get_children(): total += count_viewports(child)
	return total
func expand_groups(node: Node) -> void:
	if node is Button and node.toggle_mode and not node is CheckBox: node.button_pressed=true
	for child in node.get_children(): expand_groups(child)
func controls(node: Node, result: Array[Control]) -> void:
	if node is LineEdit or node is OptionButton or node is Button or node is TextEdit: result.append(node)
	for child in node.get_children(): controls(child,result)
func run(plugin) -> void:
	tree=plugin.get_tree(); await settle()
	check(not plugin._has_main_screen() and count_viewports(plugin.dock)==0,"one native 3D screen; no plugin viewport or main screen")
	check(plugin.dock.get_parent()!=EditorInterface.get_editor_main_screen(),"property UI is docked outside central main screen")
	for root in plugin.preview_roots:
		check(root.owner==null and root.get_parent()==EditorInterface.get_editor_viewport_3d(0),"draft root is outside the edited scene in the native viewport")
	plugin.map_panel.path_field.text="res://fixtures/box.glb"; plugin.map_panel.unit.select(1)
	check(plugin.map_panel.import_source(false),"map fixture imports into native view")
	var map=plugin.map_panel
	var path: String=str(map.session.visual.get_path_to(map.session.meshes()[0]))
	map.items[path].select(0); map.select_tree(); map.strategy.select(1); map.friction.value=.4
	check(map.configure(),"selected map object explicitly configured")
	map.session.history.undo(); map.rebuild(); check(map.session.specs.is_empty(),"map draft undo")
	map.session.history.redo(); map.rebuild(); check(map.session.specs[path].friction==.4,"map draft redo")
	plugin.panel.add_primitive("box")
	plugin.panel.select_entity("geom",str(plugin.state.document.geometry()[0].name))
	if plugin.panel.inputs.has("friction"):
		plugin.panel.inputs.friction.text="[0.4,0.005,0.0001]";plugin.panel.pending=true
	var selected: Dictionary=plugin.panel.selected.duplicate(true)
	plugin.panel.select_entity("body","world")
	check(plugin.panel.pending and plugin.panel.selected==selected,"MJCF pending fields block entity selection")
	plugin.state.document.set_paused(false)
	for index in 12: plugin.show_scope(index%4)
	check(not plugin.state.document.is_paused(),"page switches do not pause or start simulation")
	plugin.state.document.set_paused(true)
	var host := Node3D.new(); host.name="LayoutHost"
	var packed := PackedScene.new(); packed.pack(host); ResourceSaver.save(packed,"res://LayoutHost.tscn"); host.free()
	EditorInterface.open_scene_from_path("res://LayoutHost.tscn"); await settle()
	check(map.apply_scene(),"explicit scene Apply retained")
	var scene:=EditorInterface.get_edited_scene_root()
	check(map.world.get_world_3d()==scene.get_world_3d(),"draft bridge shares native scene World3D")
	check(map.world.get_child_count()==0,"Apply removes temporary map preview nodes")
	check(not map.open_scene_map(scene.get_node("StaticMap")),"scene-map load protects dirty draft")
	var package: Dictionary=map.Package.pack(map.session,"res://layout_maps")
	check(package.error.is_empty() and map.open_scene_map(scene.get_node("StaticMap")),"explicit Inspector scene-map load after save")
	var selected_mesh: Node=scene.get_node("StaticMap/Visual").get_node(NodePath(path))
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(selected_mesh); await settle()
	check(map.selected==path and is_equal_approx(map.friction.value,.4),"scene selection drives matching map draft properties")
	var saved:=PackedScene.new(); saved.pack(scene); ResourceSaver.save(saved,"res://LayoutHost.tscn")
	var text:=FileAccess.get_file_as_string("res://LayoutHost.tscn")
	check(not text.contains("MapDraft") and not text.contains("MJCFDraft") and scene.get_child_count()==1,"saved scene excludes draft bridge and overlays")
	var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(scene))
	history.undo(); check(not scene.has_node("StaticMap"),"scene undo removes Apply")
	history.redo(); check(scene.get_child_count()==1,"scene redo creates only authored map")
	plugin.heightfield_panel.create_terrain(); await settle()
	check(plugin.scope.selected==2 and is_instance_valid(plugin.heightfield_panel.target),"terrain scene selection opens corresponding scope")
	plugin.heightfield_panel.heights.text="1 0\n0 0"; plugin.heightfield_panel.heights.text_changed.emit()
	check(plugin.heightfield_panel.preview_text(),"terrain draft previews in native view")
	check(plugin.heightfield_panel.preview.get_world_3d()==scene.get_world_3d() and not scene.is_ancestor_of(plugin.heightfield_panel.preview),"terrain preview stays outside saved scene")
	plugin.heightfield_panel.friction.value=.7
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(scene); await settle()
	check(plugin.heightfield_panel.dirty and plugin.heightfield_panel.target==scene.get_node("Heightfield"),"dirty terrain selection switch retains draft and target")
	# Measure right-dock content at real requested widths, independent of the editor's persisted splitter.
	var parent=plugin.dock.get_parent(); var position=plugin.dock.get_index()
	var measure:=Control.new(); EditorInterface.get_base_control().add_child(measure)
	plugin.dock.reparent(measure)
	plugin.dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for window_size in [Vector2i(1180,812),Vector2i(900,600)]:
		tree.root.size=window_size
		for width in [320,360,420]:
			measure.size=Vector2(width,window_size.y-120)
			for index in 4:
				plugin.show_scope(index); expand_groups(plugin.pages[index]); await settle()
				var scroll: ScrollContainer=plugin.pages[index]
				check(plugin.dock.size.x<=width+1 and not scroll.get_h_scroll_bar().visible,"right dock fits %s / %d / page %d" % [window_size,width,index])
				var fields: Array[Control]=[]; controls(scroll,fields)
				var reachable:=true
				for control in fields:
					if not control.is_visible_in_tree(): continue
					var ancestor: Node=control.get_parent()
					while ancestor and ancestor!=plugin.dock:
						if ancestor is ScrollContainer:
							ancestor.ensure_control_visible(control); await tree.process_frame
							var bounds: Rect2=ancestor.get_global_rect()
							if ancestor.get_v_scroll_bar().visible: bounds.size.x-=ancestor.get_v_scroll_bar().size.x
							if not bounds.grow(2).encloses(control.get_global_rect()):
								reachable=false; print("UNREACHABLE ",width," page ",index," ",control.get_class()," ",control.get("text")," ",control.get_global_rect()," in ",bounds)
						ancestor=ancestor.get_parent()
				check(reachable,"all visible controls reachable in scroll bounds")
	plugin.dock.reparent(parent); parent.move_child(plugin.dock,position); measure.queue_free()
	var old_world=map.world
	var session=map.session
	EditorInterface.set_plugin_enabled("mujoco_editor",false); await settle()
	check(not is_instance_valid(old_world),"disable removes preview bridge")
	EditorInterface.set_plugin_enabled("mujoco_editor",true); await settle()
	plugin=EditorInterface.get_base_control().get_meta("mujoco_active_plugin")
	check(plugin.map_panel.session==session and session.specs[path].friction==.4,"reopen preserves map session and history")
	check(plugin.panel.pending,"reopen preserves MJCF pending fields")
	check(plugin.heightfield_panel.dirty and plugin.heightfield_panel.heights.text=="1 0\n0 0" and is_equal_approx(plugin.heightfield_panel.friction.value,.7),"reopen preserves terrain raw pending fields")
	plugin.heightfield_panel.discard()
	check(count_viewports(plugin.dock)==0 and plugin.preview_roots.size()==2,"reopen does not duplicate viewports or preview roots")
	plugin.panel.pending=false; plugin.state.dirty=false; session.dirty=false
	print("NATIVE_LAYOUT_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"scope":"headless editor logic and measured layout; actual dot GUI acceptance pending"}))
	tree.quit(0 if failed==0 else 1)
