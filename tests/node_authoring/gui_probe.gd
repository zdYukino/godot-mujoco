@tool
extends RefCounted
## Observe rendered controls and inject ordinary GUI input through their Window viewport.
## No author commands or property setters are invoked by this probe.
var plugin: EditorPlugin
var folder := ""
var elapsed := 0.0
var busy := false
var completed_request := ""
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
	if node is Window and not node.visible: return
	if node.get_class() == "EditorInspectorSection":
		var properties := []
		for editor in node.find_children("*","EditorProperty",true,false): properties.append(str(editor.get_edited_property()))
		output.append({"section":str(node.name),"properties":properties,"rect":rect(node),"text":""})
	if node is LineEdit: output.append({"class":"LineEdit","text":node.text,"rect":rect(node),"placeholder":node.placeholder_text})
	if node is Button: output.append({"text":node.text,"tooltip":node.tooltip_text,"rect":rect(node)})
	if node is TabBar:
		for index in node.tab_count:
			var area: Rect2 = node.get_tab_rect(index); area.position += node.get_screen_transform().origin
			output.append({"text":node.get_tab_title(index),"rect":[area.position.x,area.position.y,area.size.x,area.size.y]})
	if node is FileDialog or node is EditorFileDialog:
		if node.visible: output.append({"dialog":true,"directory":node.current_dir,"file":rect(node.get_line_edit()),"ok":rect(node.get_ok_button())})
	if node is ItemList:
		for index in node.item_count:
			var area: Rect2 = node.get_item_rect(index); area.position += node.get_screen_transform().origin
			output.append({"list_item":node.get_item_text(index),"rect":[area.position.x,area.position.y,area.size.x,area.size.y]})
	if node is Tree: tree_items(node,node.get_root(),rows)
	if node is EditorProperty:
		var values := []
		field_controls(node,values)
		fields[str(node.get_edited_property())] = values
	for child in node.get_children(true): controls(child,output,rows,fields)
func field_controls(node: Node, output: Array) -> void:
	if node is ColorPickerButton and node.is_visible_in_tree(): output.append({"class":"ColorPickerButton","instance":node.get_instance_id(),"pressed":node.button_pressed,"popup_visible":node.get_popup().visible,"popup_position":[node.get_popup().position.x,node.get_popup().position.y],"popup_size":[node.get_popup().size.x,node.get_popup().size.y],"rect":rect(node),"color":[node.color.r,node.color.g,node.color.b,node.color.a]})
	if node is OptionButton and node.is_visible_in_tree():
		var items := []
		for index in node.item_count: items.append({"label":node.get_item_text(index),"id":node.get_item_id(index),"metadata":node.get_item_metadata(index)})
		output.append({"class":"OptionButton","rect":rect(node),"selected":node.selected,"items":items,"disabled":node.disabled,"instance":node.get_instance_id(),"popup_visible":node.get_popup().visible,"popup_position":[node.get_popup().position.x,node.get_popup().position.y],"popup_size":[node.get_popup().size.x,node.get_popup().size.y]})
	if node is SpinBox and node.is_visible_in_tree():
		output.append({"class":"SpinBox","rect":rect(node),"value":node.value})
	if node is Button and not node is OptionButton and not node is ColorPickerButton and node.is_visible_in_tree(): output.append({"class":node.get_class(),"rect":rect(node),"pressed":node.button_pressed,"text":node.text})
	if node is Label and node.is_visible_in_tree(): output.append({"class":"Label","rect":rect(node),"text":node.text,"tooltip":node.tooltip_text})
	if node is LineEdit and node.is_visible_in_tree(): output.append({"class":"LineEdit","rect":rect(node),"text":node.text})
	if node.get_class() == "EditorSpinSlider" and node.is_visible_in_tree(): output.append({"class":"EditorSpinSlider","rect":rect(node)})
	if node is ColorPicker and node.is_visible_in_tree(): picker_controls(node,output)
	for child in node.get_children(true): field_controls(child,output)
func picker_controls(node: Node, output: Array) -> void:
	if node is Control and node.is_visible_in_tree(): output.append({"class":node.get_class(),"picker_control":str(node.name),"rect":rect(node)})
	for child in node.get_children(true): picker_controls(child,output)
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
	if busy or not is_instance_valid(plugin): return
	elapsed += plugin.get_process_delta_time()
	if elapsed<.15: return
	elapsed = 0
	busy = true
	var request := folder.path_join("request.json")
	if FileAccess.file_exists(request):
		var value = JSON.parse_string(FileAccess.get_file_as_string(request)); DirAccess.remove_absolute(request)
		if value is Dictionary:
			if value.has("input"): await play_inputs(value.input)
			if value.get("quit",false):
				plugin.get_tree().process_frame.disconnect(tick)
				plugin.get_tree().quit(); return
			if value.has("scroll"): scroll_tree(EditorInterface.get_base_control(),value.scroll)
			if value.has("scope"): plugin.reveal_scope(int(value.scope))
			if value.has("capture"): capture_windows(plugin.get_tree().root,str(value.capture))
			completed_request = str(value.get("id",""))
	var cs := []; var rows := []; var fields := {}
	controls(EditorInterface.get_base_control(),cs,rows,fields)
	var models := []; var entities := []; var points := {}; var worlds := []
	var root := EditorInterface.get_edited_scene_root()
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d()
	var origin: Vector2 = viewport.get_parent().get_screen_transform().origin
	if root:
		for node in plugin.all_nodes(root):
			if node is MjModelInstance and node.design:
				models.append({"id":node.design_instance_id,"name":str(node.name),"revision":node.design.revision,"validated":node.design.validated_revision,"context_valid":node.design.validated_context==node.compilation_signature(),"error":node.design.validation_error,"mesh_options":node.design.mesh_options,"collision_stats":node.design.collision_stats})
				for item in node.design.entities():
					entities.append({"id":item.id,"name":item.name,"kind":item.kind,"attrs":item.attrs,"position":[item.transform.origin.x,item.transform.origin.y,item.transform.origin.z]})
					if item.kind == "geom" and node.author_scene:
						var geom: Node = node.author_scene.nodes.get(item.id)
						var visual: MeshInstance3D = geom.get_node_or_null("_Visual") if geom else null
						if visual and visual.material_override is StandardMaterial3D:
							var material: StandardMaterial3D = visual.material_override
							entities[-1].appearance = {"color":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a],"texture":material.albedo_texture.resource_path if material.albedo_texture else "","transparency":material.transparency}
			if node is MjRuntimeWorld and node.world_design:
				worlds.append({"name":str(node.name),"revision":node.world_design.revision,"settings":preload("res://addons/godot_mujoco/model/collision_settings.gd").world_values(node.world_design.tree)})
			if node.has_method("author_kind") and camera:
				var point: Vector2 = camera.unproject_position(node.global_position)+origin
				var right: Vector2 = camera.unproject_position(node.global_position+Vector3.RIGHT*.3)+origin
				points[str(node.name)]={"origin":[point.x,point.y],"right":[right.x,right.y]}
	var selection := []
	for node in EditorInterface.get_selection().get_selected_nodes(): selection.append(str(node.name))
	var inspected: Object = EditorInterface.get_inspector().get_edited_object()
	var history := {}
	if root:
		var timeline: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
		if timeline: history = {"version":timeline.get_version(),"action":timeline.get_current_action(),"count":timeline.get_history_count(),"undo":timeline.has_undo(),"redo":timeline.has_redo()}
	var data := {"completed_request":completed_request,"controls":cs,"windows":visible_windows(plugin.get_tree().root).map(func(window): return {"id":window.get_window_id(),"name":str(window.name),"position":[window.position.x,window.position.y],"size":[window.size.x,window.size.y]}),"worlds":worlds,"rows":rows,"fields":fields,"models":models,"entities":entities,"points":points,"selected":selection,"history":history,"mouse":plugin.get_viewport().get_mouse_position(),"window_position":DisplayServer.window_get_position(),"panel_status":plugin.panel.status.text}
	data.inspected = str(inspected.name) if inspected is Node else ""
	data.tooltip_texts = []
	for window in visible_windows(plugin.get_tree().root):
		if window == plugin.get_window(): continue
		for label in window.find_children("*","Label",true,false):
			if label.is_visible_in_tree(): data.tooltip_texts.append(label.text)
	var output := FileAccess.open(folder.path_join("state.tmp"),FileAccess.WRITE); output.store_string(JSON.stringify(data)); output.close()
	DirAccess.rename_absolute(folder.path_join("state.tmp"),folder.path_join("state.json"))
	busy = false

func capture_windows(root: Node, filename: String) -> void:
	if root is Window and root.visible:
		var path := filename if root == plugin.get_window() else filename.get_basename()+"_popup_"+str(root.get_window_id())+".png"
		var texture: ViewportTexture = root.get_texture()
		var picture: Image = texture.get_image() if texture else null
		if picture: picture.save_png(folder.path_join(path))
	for child in root.get_children(true): capture_windows(child,filename)

func visible_windows(node: Node) -> Array[Window]:
	var result: Array[Window] = []
	if node is Window and node.visible and not node.is_embedded() and node.get_window_id()>=0: result.append(node)
	for child in node.get_children(true): result.append_array(visible_windows(child))
	return result

func play_inputs(values: Array) -> void:
	for value in values:
		var window: Window = plugin.get_window()
		if value.get("kind") != "key" or value.has("x"):
			var point := Vector2(value.x,value.y)
			var area := window.size.x*window.size.y
			for candidate in visible_windows(plugin.get_tree().root):
				var box := Rect2(Vector2(candidate.position),Vector2(candidate.size))
				if box.has_point(point) and candidate.size.x*candidate.size.y<area:
					window=candidate;area=candidate.size.x*candidate.size.y
		else:
			for candidate in visible_windows(plugin.get_tree().root):
				if candidate.has_focus(): window=candidate
		var event
		if value.get("kind") == "key":
			event=InputEventKey.new();event.keycode={"Return":KEY_ENTER,"Escape":KEY_ESCAPE}.get(value.key,OS.find_keycode_from_string(str(value.key).to_upper()));event.pressed=value.pressed
			event.unicode=int(value.get("unicode",0))
			event.ctrl_pressed=value.get("ctrl",false);event.shift_pressed=value.get("shift",false)
		else:
			var local := Vector2(value.x,value.y)-Vector2(window.position)
			if value.get("kind") == "motion":
				event=InputEventMouseMotion.new();event.button_mask=MOUSE_BUTTON_MASK_LEFT if value.get("held",false) else 0
			else:
				event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=value.pressed
				event.button_mask=MOUSE_BUTTON_MASK_LEFT if value.pressed else 0
				event.double_click=value.get("double",false)
			event.position=local;event.global_position=local
		event.window_id=window.get_window_id()
		Input.parse_input_event(event)
		await plugin.get_tree().process_frame
