@tool
extends RefCounted
## Observation only: mouse/keyboard actions are sent through the desktop XTEST driver.
var plugin: EditorPlugin
var folder := ""
var elapsed := 0.0
func run(editor: EditorPlugin) -> void:
	plugin = editor
	for frame in 30: await plugin.get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-dir="): folder = arg.trim_prefix("--probe-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	if not FileAccess.file_exists("res://GuiAuthor.tscn"):
		var root := Node3D.new(); root.name = "GuiAuthor"
		var packed := PackedScene.new(); packed.pack(root); ResourceSaver.save(packed,"res://GuiAuthor.tscn"); root.free()
	EditorInterface.open_scene_from_path("res://GuiAuthor.tscn")
	plugin.reveal_scope(0); EditorInterface.set_main_screen_editor("3D")
	plugin.get_tree().process_frame.connect(tick)
func rect(control: Control) -> Array:
	var r := Rect2(control.get_screen_transform().origin,control.size)
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func tree_items(tree: Tree, item: TreeItem, output: Array) -> void:
	if not item: return
	var r := tree.get_item_area_rect(item); r.position += tree.get_screen_transform().origin
	var icon := item.get_icon(0)
	output.append({"text":item.get_text(0),"selected":item.is_selected(0),"icon":icon.resource_path if icon else "","rect":[r.position.x,r.position.y,r.size.x,r.size.y]})
	for child in item.get_children(): tree_items(tree,child,output)
func controls(node: Node, output: Array, rows: Array, fields: Dictionary) -> void:
	if node is Control and not node.is_visible_in_tree(): return
	if node is Button: output.append({"text":node.text,"tooltip":node.tooltip_text,"rect":rect(node)})
	if node is TabBar:
		for index in node.tab_count:
			var area: Rect2 = node.get_tab_rect(index); area.position += node.get_screen_transform().origin
			output.append({"text":node.get_tab_title(index),"rect":[area.position.x,area.position.y,area.size.x,area.size.y]})
	if node is FileDialog or node is EditorFileDialog:
		if node.visible: output.append({"dialog":true,"file":rect(node.get_line_edit()),"ok":rect(node.get_ok_button())})
	if node is Tree: tree_items(node,node.get_root(),rows)
	if node is EditorProperty:
		var values := []
		field_controls(node,values)
		fields[str(node.get_edited_property())] = values
	for child in node.get_children(): controls(child,output,rows,fields)
func field_controls(node: Node, output: Array) -> void:
	if node is ColorPickerButton and node.is_visible_in_tree(): output.append({"class":"ColorPickerButton","instance":node.get_instance_id(),"pressed":node.button_pressed,"rect":rect(node),"color":[node.color.r,node.color.g,node.color.b,node.color.a]})
	if node is LineEdit and node.is_visible_in_tree(): output.append({"class":"LineEdit","rect":rect(node),"text":node.text})
	if node.get_class() == "EditorSpinSlider" and node.is_visible_in_tree(): output.append({"class":"EditorSpinSlider","rect":rect(node)})
	for child in node.get_children(): field_controls(child,output)
func scroll_tree(node: Node, text: String) -> void:
	if node is Tree and node.is_visible_in_tree():
		var items := [node.get_root()]
		while not items.is_empty():
			var item: TreeItem = items.pop_back()
			if not item: continue
			if item.get_text(0)==text:
				var parent := item.get_parent()
				while parent: parent.collapsed=false; parent=parent.get_parent()
				node.scroll_to_item(item)
			items.append_array(item.get_children())
	for child in node.get_children(): scroll_tree(child,text)
func tick() -> void:
	elapsed += plugin.get_process_delta_time()
	if elapsed<.15: return
	elapsed = 0
	var request := folder.path_join("request.json")
	if FileAccess.file_exists(request):
		var value = JSON.parse_string(FileAccess.get_file_as_string(request)); DirAccess.remove_absolute(request)
		if value is Dictionary:
			if value.get("quit",false): plugin.get_tree().quit(); return
			if value.has("scroll"): scroll_tree(EditorInterface.get_base_control(),value.scroll)
			if value.has("capture"): plugin.get_viewport().get_texture().get_image().save_png(folder.path_join(value.capture))
	var cs := []; var rows := []; var fields := {}
	controls(EditorInterface.get_base_control(),cs,rows,fields)
	var models := []; var entities := []; var points := {}
	var root := EditorInterface.get_edited_scene_root()
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var origin: Vector2 = viewport.get_parent().get_screen_transform().origin
	if root:
		for node in plugin.all_nodes(root):
			if node is MjModelInstance and node.design:
				models.append({"id":node.design_instance_id,"name":str(node.name),"revision":node.design.revision,"validated":node.design.validated_revision,"error":node.design.validation_error})
				for item in node.design.entities():
					entities.append({"id":item.id,"name":item.name,"kind":item.kind,"attrs":item.attrs,"position":[item.transform.origin.x,item.transform.origin.y,item.transform.origin.z]})
					if item.kind == "geom" and node.author_scene:
						var geom: Node = node.author_scene.nodes.get(item.id)
						var visual: MeshInstance3D = geom.get_node_or_null("_Visual") if geom else null
						if visual and visual.material_override is StandardMaterial3D:
							var material: StandardMaterial3D = visual.material_override
							entities[-1].appearance = {"color":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a],"texture":material.albedo_texture.resource_path if material.albedo_texture else "","transparency":material.transparency}
			if node.has_method("author_kind") and camera:
				var point: Vector2 = camera.unproject_position(node.global_position)+origin
				var right: Vector2 = camera.unproject_position(node.global_position+Vector3.RIGHT*.3)+origin
				points[str(node.name)]={"origin":[point.x,point.y],"right":[right.x,right.y]}
	var selection := []
	for node in EditorInterface.get_selection().get_selected_nodes(): selection.append(str(node.name))
	var history := {}
	if root:
		var timeline: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
		if timeline: history = {"version":timeline.get_version(),"action":timeline.get_current_action(),"count":timeline.get_history_count(),"undo":timeline.has_undo(),"redo":timeline.has_redo()}
	var data := {"controls":cs,"rows":rows,"fields":fields,"models":models,"entities":entities,"points":points,"selected":selection,"history":history,"mouse":plugin.get_viewport().get_mouse_position(),"window_position":DisplayServer.window_get_position(),"panel_status":plugin.panel.status.text}
	var output := FileAccess.open(folder.path_join("state.tmp"),FileAccess.WRITE); output.store_string(JSON.stringify(data)); output.close()
	DirAccess.rename_absolute(folder.path_join("state.tmp"),folder.path_join("state.json"))
