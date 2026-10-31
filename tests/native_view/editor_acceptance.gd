@tool
extends RefCounted
const Settings = preload("res://addons/godot_mujoco/native_view/settings.gd")
var plugin: EditorPlugin
var output := ""
var run_id := ""
var checks: Array = []
var samples: Array = []
var without_native := false
func check(ok: bool, name: String) -> bool:
	checks.append({"name":name,"passed":ok})
	if not ok: printerr("FAIL ",name)
	return ok
func wait_for(test: Callable, seconds := 60.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await plugin.get_tree().process_frame
	return test.call()
func state() -> Dictionary:
	var value = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("state.json"))) if FileAccess.file_exists(output.path_join("state.json")) else {}
	return value if value is Dictionary and value.get("run_id")==run_id else {}
func command(op: String) -> void:
	FileAccess.open(output.path_join("command.tmp"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":run_id,"op":op}))
	DirAccess.rename_absolute(output.path_join("command.tmp"),output.path_join("command.json"))
func run(editor: EditorPlugin) -> void:
	plugin=editor;output=OS.get_environment("GMJ_RENDER_TEST_OUT")
	without_native="--without-native" in OS.get_cmdline_user_args()
	if "--component-preview" in OS.get_cmdline_user_args():
		await component_preview();await finish();return
	if "--component-preset-reopen" in OS.get_cmdline_user_args():
		await component_preset_reopen();await finish();return
	if "--component-preset" in OS.get_cmdline_user_args():
		await component_preset();await finish();return
	EditorInterface.set_main_screen_editor("3D");plugin.reveal_scope(0)
	if "--reopen" in OS.get_cmdline_user_args():
		check(Settings.mode()==Settings.MUJOCO,"saved native project choice survives editor restart")
		check(plugin.view_controls.renderer_choice.selected==1,"reopened toolbar shows saved native choice")
		check(plugin.view_controls.renderer_choice.is_visible_in_tree(),"renderer selector is visible in MuJoCo dock")
		if without_native:check(plugin.view_controls.renderer_choice.is_item_disabled(1) and not Settings.unavailable_reason().is_empty(),"GL-OFF reopened selector retains an explicit native-unavailable reason")
		await RenderingServer.frame_post_draw
		EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor-selector.png"))
		await finish();return
	await scenario()
	await finish()
func component_preview() -> void:
	var editor_window := EditorInterface.get_base_control().get_window()
	editor_window.mode=Window.MODE_WINDOWED
	editor_window.size=Vector2i(1800,1100)
	EditorInterface.open_scene_from_path("res://Main.tscn")
	if not check(await wait_for(func():return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().scene_file_path=="res://Main.tscn"),"initial editor scene settles before standalone component previews"):return
	for unused in 10:await plugin.get_tree().process_frame
	EditorInterface.set_main_screen_editor("2D")
	for custom in [false,true]:
		var component := preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd").new()
		component.name="CustomComponentPreview" if custom else "DefaultComponentPreview"
		if custom:
			component.ui_scene=load("res://custom_ui.tscn")
			var theme := Theme.new();theme.set_color("font_color","Label",Color(.1,.9,.8));component.ui_theme=theme
		var saved := PackedScene.new();saved.pack(component)
		var source := "res://CustomComponentPreview.tscn" if custom else "res://DefaultComponentPreview.tscn"
		check(ResourceSaver.save(saved,source)==OK,"save explicit editor preview component "+str(custom));component.free()
		EditorInterface.open_scene_from_path(source)
		if not check(await wait_for(func():return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().scene_file_path==source),"open actual editor component preview "+str(custom)):return
		var preview: Node=EditorInterface.get_edited_scene_root()
		check(await wait_for(func():return is_instance_valid(preview.ui) and is_instance_valid(preview.ui.get_node_or_null("PreviewData"))),"editor draws authored UI with labeled placeholders "+str(custom))
		check(preview.bound_world==null and preview._session==null and not preview.is_processing_input(),"actual editor preview starts no simulation, MuJoCo renderer, sampler or viewer input "+str(custom))
		if custom:check(preview.ui.get_node("MainLayout/MuJoCoLeftPanel/@MarginContainer@6/@VBoxContainer@7/OptionSection/@Label@9").text=="Custom options" and preview.ui.theme==preview.ui_theme,"actual editor inherited UI keeps custom widget text and Theme")
		for unused in 10:await plugin.get_tree().process_frame
		check(preview.ui.render_region.get_global_rect().has_point(preview.ui.run_label.get_global_rect().get_center()),"preview pause marker follows the render region after container reflow "+str(custom))
		for unused in 3:await plugin.get_tree().process_frame
		check(EditorInterface.get_edited_scene_root()==preview,"captured preview remains the actual edited component scene "+str(custom))
		await RenderingServer.frame_post_draw
		var path := output.path_join("editor-component-custom.png" if custom else "editor-component-default.png")
		check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(path)==OK,"capture actual editor component preview "+str(custom))
		var packed := PackedScene.new();packed.pack(preview)
		check(packed.get_state().get_node_count()==1,"editor does not serialize internal preview UI children "+str(custom))
	await extras_preview()
func extras_preview() -> void:
	var inherited_text := """[gd_scene load_steps=2 format=3]
[ext_resource type="PackedScene" path="res://addons/godot_mujoco/viewer/extras_ui.tscn" id="1"]
[node name="CustomExtrasUI" instance=ExtResource("1")]
[node name="RendererSection" parent="@Window@24/@ScrollContainer@27/@VBoxContainer@28" index=1]
text = "Custom renderer tools"
"""
	FileAccess.open("res://CustomExtrasUI.tscn",FileAccess.WRITE).store_string(inherited_text)
	for custom in [false,true]:
		var component := preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new()
		component.name="CustomExtrasPreview" if custom else "DefaultExtrasPreview"
		if custom:
			component.ui_scene=load("res://CustomExtrasUI.tscn")
			var theme := Theme.new();theme.set_color("font_color","Label",Color(.9,.6,.2));component.ui_theme=theme
		var saved := PackedScene.new();saved.pack(component)
		var source := "res://CustomExtrasPreview.tscn" if custom else "res://DefaultExtrasPreview.tscn"
		check(ResourceSaver.save(saved,source)==OK,"save explicit standalone Extras preview "+str(custom));component.free()
		EditorInterface.open_scene_from_path(source)
		if not check(await wait_for(func():return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().scene_file_path==source),"open actual editor Extras preview "+str(custom)):return
		var preview: Node=EditorInterface.get_edited_scene_root()
		check(await wait_for(func():return is_instance_valid(preview.ui) and is_instance_valid(preview.ui.get_node_or_null("GodotExtrasPreview"))),"editor displays sample Extras panel without a native viewer "+str(custom))
		check(preview.bound_world==null and preview._session==null and preview._performance_source==null and not preview.is_processing_input() and not preview.ui.controls.visible,"Extras preview starts no world, sampler, native renderer or runtime Window "+str(custom))
		if custom:check(preview.ui.get_node("@Window@24/@ScrollContainer@27/@VBoxContainer@28/RendererSection").text=="Custom renderer tools" and preview.ui.theme==preview.ui_theme,"Extras inherited widget text and Theme remain authored")
		for unused in 10:await plugin.get_tree().process_frame
		var sample_panel: Control=preview.ui.get_node("GodotExtrasPreview")
		var sample_buttons := sample_panel.find_children("*","Button",true,false)
		var visible_tools := false
		for button in sample_buttons:
			if button.get_meta("viewer_section",{}).get("name","")=="Renderer":
				var clip: Control=button.get_parent().get_parent()
				visible_tools=button.is_visible_in_tree() and button.size.x>20 and button.size.y>10 and clip.size.y>50 and clip.get_global_rect().has_point(button.get_global_rect().get_center())
		check(visible_tools,"Extras preview contains visible tool controls inside its scrolling viewport "+str(custom))
		var marker: Control=preview.ui.get_node("PreviewData")
		check(not marker.get_global_rect().intersects(preview.ui.hud.get_global_rect()) and not sample_panel.get_global_rect().intersects(preview.ui.hud.get_global_rect()),"Extras sample title, FPS and tools do not overlap "+str(custom))
		await RenderingServer.frame_post_draw
		check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor-extras-custom.png" if custom else "editor-extras-default.png"))==OK,"capture standalone Extras editor preview "+str(custom))
		var packed := PackedScene.new();packed.pack(preview)
		check(packed.get_state().get_node_count()==1,"Extras editor preview does not serialize generated sample children "+str(custom))
func preset_editor_ready() -> void:
	EditorInterface.open_scene_from_path("res://Main.tscn")
	check(await wait_for(func():return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().scene_file_path=="res://Main.tscn"),"startup main scene settles before preset authoring")
	for unused in 10:await plugin.get_tree().process_frame
func component_preset() -> void:
	await preset_editor_ready()
	var authored := Node3D.new()
	authored.name = "PresetAcceptance"
	var world := preload("res://addons/godot_mujoco/model/runtime_world.gd").new()
	world.name = "Runtime"
	authored.add_child(world); world.owner = authored
	var host := preload("res://addons/godot_mujoco/model/environment_host.gd").new()
	host.name = "EnvironmentHost"
	authored.add_child(host); host.owner = authored
	var instance_root := Node3D.new(); instance_root.name = "Instance"
	var instance_world := preload("res://addons/godot_mujoco/model/runtime_world.gd").new()
	instance_world.name = "NestedRuntime"
	instance_root.add_child(instance_world); instance_world.owner = instance_root
	var instance_scene := PackedScene.new(); instance_scene.pack(instance_root)
	ResourceSaver.save(instance_scene, "res://PresetInstance.tscn"); instance_root.free()
	var instance: Node = load("res://PresetInstance.tscn").instantiate()
	authored.add_child(instance); instance.owner = authored
	var packed := PackedScene.new(); packed.pack(authored)
	check(ResourceSaver.save(packed, "res://PresetAcceptance.tscn") == OK, "save independent preset authoring fixture")
	authored.free()
	EditorInterface.open_scene_from_path("res://PresetAcceptance.tscn")
	if not check(await wait_for(func(): return EditorInterface.get_edited_scene_root() != null and EditorInterface.get_edited_scene_root().scene_file_path == "res://PresetAcceptance.tscn"), "actual editor opens preset fixture"): return
	var root := EditorInterface.get_edited_scene_root()
	var preset: Control = plugin.view_controls.runtime_panel_preset
	plugin.reveal_scope(0)
	EditorInterface.get_selection().clear(); preset.refresh()
	check(preset.add_button.disabled and "请选择" in preset.target_note.text, "preset is visible but explains missing explicit selection")
	check(preset.add_button.is_visible_in_tree() and preset.add_button.text == "添加 MuJoCo 运行面板", "right dock contains original-panel preset button")
	check(not "暂不支持" in plugin.view_controls.renderer_choice.tooltip_text, "renderer tooltip describes shared native interaction")
	EditorInterface.get_selection().add_node(root); preset.refresh()
	check(preset.add_button.disabled and "不是" in preset.target_note.text, "ordinary node selection cannot implicitly choose a World")
	EditorInterface.get_selection().clear()
	var nested := root.get_node("Instance/NestedRuntime")
	EditorInterface.get_selection().add_node(nested); preset.refresh()
	check(preset.add_button.disabled and "不可编辑" in preset.target_note.text, "uneditable instance target is rejected with reason")
	var before := root.get_child_count()
	preset.add_selected()
	check(root.get_child_count() == before and nested.get_parent().get_child_count() == 1, "invalid preset never adds component or modifies instance")
	root.set_editable_instance(root.get_node("Instance"), true); preset.refresh()
	check(not preset.add_button.disabled, "explicit editable instance enables its target")
	root.set_editable_instance(root.get_node("Instance"), false)
	for target_name in ["Runtime", "EnvironmentHost"]:
		var target := root.get_node(target_name)
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(target); preset.refresh()
		check(not preset.add_button.disabled and target_name in preset.target_note.text, "explicit editable target enables preset " + target_name)
		var count := root.get_child_count()
		preset.add_button.pressed.emit()
		var selected := EditorInterface.get_selection().get_selected_nodes()
		var viewer: Node = selected[0] if selected.size() == 1 else null
		if not check(viewer is MjRuntimeViewer, "preset selects newly created original panel " + target_name): return
		check(viewer.owner == root and viewer.get_parent() == target.get_parent() and viewer.enabled, "preset creates enabled saved sibling " + target_name)
		check((viewer.world == target and viewer.environment_host == null) if target is MjRuntimeWorld else (viewer.environment_host == target and viewer.world == null), "preset binds exactly selected World or Host " + target_name)
		check(root.get_child_count() == count + 1, "preset adds only original component, no Extras/provider/model " + target_name)
		var undo := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
		undo.undo()
		check(viewer.get_parent() == null and root.get_child_count() == count and viewer.world == null and viewer.environment_host == null, "Undo removes panel and binding " + target_name)
		undo.redo()
		check(viewer.get_parent() == root and viewer.owner == root and (viewer.world == target if target is MjRuntimeWorld else viewer.environment_host == target), "Redo restores same component ownership and binding " + target_name)
		EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(target)
		preset.add_button.pressed.emit()
		check(root.get_child_count() == count + 1 and EditorInterface.get_selection().get_selected_nodes() == [viewer], "duplicate preset selects existing same-target panel " + target_name)
	await add_child_dialog_checks(root)
	check(EditorInterface.save_scene() == OK, "editor saves preset-authored scene")
	# A root World has no persistent sibling location: reject rather than reroot it.
	var root_world := preload("res://addons/godot_mujoco/model/runtime_world.gd").new()
	root_world.name = "RootRuntime"
	var root_packed := PackedScene.new(); root_packed.pack(root_world)
	ResourceSaver.save(root_packed, "res://RootRuntime.tscn"); root_world.free()
	EditorInterface.open_scene_from_path("res://RootRuntime.tscn")
	await wait_for(func(): return EditorInterface.get_edited_scene_root().scene_file_path == "res://RootRuntime.tscn")
	root = EditorInterface.get_edited_scene_root()
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(root); preset.refresh()
	check(preset.add_button.disabled and "普通场景根节点" in preset.target_note.text, "root target explains required sibling parent")
	preset.add_selected()
	check(EditorInterface.get_edited_scene_root() == root and root.get_child_count() == 0, "root rejection never silently restructures scene")
	await RenderingServer.frame_post_draw
	check(EditorInterface.get_edited_scene_root()==root,"root rejection capture remains the edited root target")
	check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor-runtime-panel-root-reason.png")) == OK, "capture actual editor preset and root-target reason")

func editor_key(code: Key, control := false) -> void:
	var event := InputEventKey.new();event.keycode=code;event.ctrl_pressed=control;event.pressed=true
	Input.parse_input_event(event);await plugin.get_tree().process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await plugin.get_tree().process_frame
func find_editor_class(node: Node, type_name: String) -> Node:
	if node.get_class()==type_name:return node
	for child in node.get_children(true):
		var found := find_editor_class(child,type_name)
		if found:return found
	return null
func find_type_item(item: TreeItem, type_name: String) -> TreeItem:
	if item==null:return null
	if item.get_text(0)==type_name:return item
	var child := item.get_first_child()
	while child:
		var found := find_type_item(child,type_name)
		if found:return found
		child=child.get_next()
	return null
func tree_type_labels(item: TreeItem) -> Array:
	var labels := []
	if item==null:return labels
	labels.append(item.get_text(0))
	var child := item.get_first_child()
	while child:
		labels.append_array(tree_type_labels(child));child=child.get_next()
	return labels
func add_child_dialog_checks(root: Node) -> void:
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(root)
	var dock := find_editor_class(plugin.get_tree().root,"SceneTreeDock")
	if not check(is_instance_valid(dock),"actual editor contains built-in SceneTreeDock"):return
	var trees := dock.find_children("*","Tree",true,false)
	if not check(not trees.is_empty(),"actual scene tree can receive Add Child Node shortcut"):return
	trees[0].grab_focus()
	await editor_key(KEY_A,true)
	var dialog: ConfirmationDialog=find_editor_class(dock,"CreateDialog")
	if not check(await wait_for(func():return is_instance_valid(dialog) and dialog.visible,10),"Ctrl+A opens built-in Add Child Node dialog"):return
	var searches := dialog.find_children("*","LineEdit",true,false)
	var search: LineEdit
	for candidate in searches:
		if candidate.is_visible_in_tree():search=candidate;break
	if not check(is_instance_valid(search),"built-in CreateDialog exposes its search field"):dialog.hide();return
	var icons := {}
	var selected_tree: Tree
	for type_name in ["MjRuntimeUiClient","MjRuntimeViewer","MjViewerExtensionBinding","MjGodotExtras"]:
		# Drive the real editor search field and inspect its native result Tree,
		# rather than treating the global script-class cache as menu evidence.
		search.text=type_name;search.text_changed.emit(type_name)
		var item: TreeItem
		for unused in 12:
			await plugin.get_tree().process_frame
			for tree in dialog.find_children("*","Tree",true,false):
				item=find_type_item(tree.get_root(),type_name)
				if item:selected_tree=tree;break
			if item:break
		if type_name=="MjRuntimeUiClient":
			check(item==null or not item.is_selectable(0),"internal abstract runtime client is not creatable from Add Child Node")
			continue
		if not check(item!=null and item.is_selectable(0),"actual Add Child Node search lists selectable "+type_name):
			print("CREATE_DIALOG_SEARCH ",search.get_path()," ",search.text)
			for tree in dialog.find_children("*","Tree",true,false):print("CREATE_DIALOG_TREE ",tree.get_path()," ",JSON.stringify(tree_type_labels(tree.get_root())))
			await RenderingServer.frame_post_draw
			dialog.get_viewport().get_texture().get_image().save_png(output.path_join("failed-create-dialog.png"))
			dialog.hide();return
		item.select(0);selected_tree.item_selected.emit()
		check(not dialog.get_ok_button().disabled,"built-in create action accepts "+type_name)
		var icon: Texture2D=item.get_icon(0)
		check(icon!=null and not icon.get_image().is_empty(),"actual type result has an icon "+type_name)
		if icon:
			var digest := HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(icon.get_image().get_data());icons[type_name]=digest.finish().hex_encode()
		await RenderingServer.frame_post_draw
		check(dialog.get_viewport().get_texture().get_image().save_png(output.path_join("editor-add-node-"+type_name+".png"))==OK,"capture built-in Add Child Node result "+type_name)
	check(icons.size()==3 and icons.values()[0]!=icons.values()[1] and icons.values()[0]!=icons.values()[2] and icons.values()[1]!=icons.values()[2],"original viewer, Extras and Binding menu icons are distinct")
	var count := root.get_child_count()
	dialog.get_ok_button().pressed.emit()
	if not check(await wait_for(func():return root.get_child_count()==count+1),"actual CreateDialog creates selected MjGodotExtras"):return
	var selected := EditorInterface.get_selection().get_selected_nodes()
	var extras: Node=selected[0] if selected.size()==1 else null
	if not check(extras is MjGodotExtras and extras.owner==root and extras.get_parent()==root,"dialog-authored Extras has saved root ownership and is selected"):return
	var undo := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
	undo.undo()
	check(extras.get_parent()==null and root.get_child_count()==count,"built-in Add Node Undo removes Extras")
	undo.redo()
	check(extras.get_parent()==root and extras.owner==root,"built-in Add Node Redo restores Extras ownership")
	extras.world=root.get_node("Runtime")
	EditorInterface.mark_scene_as_unsaved()

func component_preset_reopen() -> void:
	await preset_editor_ready()
	EditorInterface.open_scene_from_path("res://PresetAcceptance.tscn")
	if not check(await wait_for(func(): return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().scene_file_path=="res://PresetAcceptance.tscn"), "fresh editor reopens preset-authored scene from disk"): return
	var root := EditorInterface.get_edited_scene_root()
	var viewers := root.get_children().filter(func(node): return node is MjRuntimeViewer)
	check(viewers.size()==2 and viewers.all(func(node): return node.owner==root and ((node.world==root.get_node("Runtime") and node.environment_host==null) or (node.environment_host==root.get_node("EnvironmentHost") and node.world==null))), "fresh editor retains both independently saved World and Host bindings")
	var extras_nodes := root.get_children().filter(func(node):return node is MjGodotExtras)
	check(extras_nodes.size()==1 and extras_nodes[0].owner==root and extras_nodes[0].world==root.get_node("Runtime"),"fresh editor retains CreateDialog-authored Extras and explicit target")
	EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(root.get_node("Runtime"))
	plugin.reveal_scope(0);plugin.view_controls.runtime_panel_preset.refresh()
	for unused in 10:await plugin.get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(EditorInterface.get_edited_scene_root()==root and EditorInterface.get_selection().get_selected_nodes()==[root.get_node("Runtime")] and not plugin.view_controls.runtime_panel_preset.add_button.disabled,"captured preset remains bound to actual reopened selected target")
	check(EditorInterface.get_base_control().get_viewport().get_texture().get_image().save_png(output.path_join("editor-runtime-panel-preset.png"))==OK,"capture reopened actual preset with editable target")

func scenario() -> void:
	EditorInterface.open_scene_from_path("res://Main.tscn")
	if not check(await wait_for(func():return EditorInterface.get_edited_scene_root()!=null and EditorInterface.get_edited_scene_root().get_node_or_null("Runtime") is MjRuntimeWorld),"actual gallery scene opens"): return
	var root: Node = EditorInterface.get_edited_scene_root()
	plugin.reveal_scope(0)
	var probe := Node.new();probe.name="F5RenderProbe";probe.set_script(load("res://runtime_probe.gd"))
	probe.output=output;root.get_node("Runtime").add_child(probe);probe.owner=root
	root.get_node("Runtime").start_paused=true
	var choice: OptionButton = plugin.view_controls.renderer_choice
	check(choice.item_count==2 and choice.get_item_text(0)=="Godot" and choice.get_item_text(1)=="MuJoCo 原生","visible F5 renderer selector has both choices")
	check(choice.is_visible_in_tree(),"renderer selector visible in dock")
	check(plugin.view_controls.menu.get_popup().get_item_index(11)>=0,"viewport display menu also offers native F5 choice")
	if without_native:
		if not check(not Settings.unavailable_reason().is_empty() and choice.is_item_disabled(1),"GL-OFF editor explains unavailable native capability and disables its choice"):return
	else:
		if not check(Settings.unavailable_reason().is_empty(),"official X11/OpenGL editor loads native capability: "+Settings.unavailable_reason()): return
	for mode in ([Settings.GODOT,Settings.MUJOCO] if without_native else [Settings.MUJOCO,Settings.GODOT]):
		var fallback_request: bool=without_native and mode==Settings.MUJOCO
		run_id=("native-request-fallback" if fallback_request else "native" if mode==Settings.MUJOCO else "godot")+"-"+str(Time.get_ticks_usec())
		probe.run_id=run_id
		# Deliberately set the opposite legacy flag: the saved project choice wins.
		root.get_node("Runtime").native_view_experimental=mode==Settings.GODOT
		if fallback_request:
			# A project saved by an ON build can request native after installing OFF.
			ProjectSettings.set_setting(Settings.MODE,mode)
			check(ProjectSettings.save()==OK,"persist a native request made by a previously enabled build")
		else:choice.select(mode);choice.item_selected.emit(mode)
		var config := ConfigFile.new()
		check(config.load("res://project.godot")==OK and config.get_value("rendering","mujoco_native_view/renderer",-1)==mode,"toolbar selection is persisted to project.godot")
		var packed := PackedScene.new();packed.pack(root)
		check(ResourceSaver.save(packed,"res://Main.tscn")==OK,"save test gallery before F5")
		var model: Node = root.get_node("Runtime/Model")
		plugin._apply_changes()
		if not check(await wait_for(func():return model.design.validated_revision==model.design.revision and model.design.validated_context==model.compilation_signature() and model.design.validation_error.is_empty() and model.author_scene.due_ms==0 and model.author_scene.pending_transforms.is_empty() and (not is_instance_valid(model.author_scene.compiler) or not model.author_scene.compiler.busy())) and plugin._build(),"gallery author data validates for F5"): return
		EditorInterface.play_main_scene()
		if not check(await wait_for(func():return state().get("ready",false) and (not state().get("native",true) and state().get("godot_region_rendering",false) and not state().get("error","").is_empty() if fallback_request else state().get("native",false) if mode==Settings.MUJOCO else state().get("world_visible",false))),"F5 launches explicit Godot fallback" if fallback_request else "F5 launches requested renderer"): return
		if not check(await wait_for(func():return FileAccess.file_exists(output.path_join(run_id+".png"))),"actual F5 viewport captured"): return
		var snapshot := state();snapshot["case"]="native-request-fallback" if fallback_request else "native" if mode==Settings.MUJOCO else "godot";samples.append(snapshot)
		check(snapshot.left_panel and snapshot.right_panel and not snapshot.native_info,"F5 shows original sidebars with native overlays initially closed")
		check(snapshot.renderer_fps>0 and snapshot.host_fps>0,"F5 screenshot waits for actual renderer and host FPS samples")
		check(snapshot.native_groups.size()==12 and not "Simulation" in snapshot.extras_groups,"F5 native menus are independent of Godot F11 extras")
		if mode==Settings.MUJOCO and not fallback_request:
			check(snapshot.texture and snapshot.native_frame>0 and snapshot.native_geoms>0,"MuJoCo render produces real shared texture frames")
			check(snapshot.disable_3d and snapshot.world_visible and not snapshot.godot_region_rendering and snapshot.native_step_calls==0 and snapshot.gl_errors==0,"native view replaces only target Godot 3D without hiding the world or stepping")
			check(snapshot.shared_controls and snapshot.control_window_closed and snapshot.native_scene,"native picture uses shared controls and authoritative CPU scene")
			check("MuJoCo 原生" in snapshot.ui_status,"runtime status identifies actual native renderer")
		else:
			check(not snapshot.native and snapshot.godot_region_rendering and snapshot.world_visible,"Godot choice renders its actual reserved 3D target instead of the native backend")
			check(snapshot.shared_controls and snapshot.control_window_closed and "Godot" in snapshot.ui_status,"shared Godot controls and renderer status restored")
			if fallback_request:check(not snapshot.error.is_empty() and "原生回退" in snapshot.status,"saved native request reports actual Godot fallback rather than native success")
		command("step")
		check(await wait_for(func():return float(state().get("time",0))>0 and (is_equal_approx(float(state().get("native_time",-1)),float(state().get("time",0))) if mode==Settings.MUJOCO and not fallback_request else true)),"same authoritative simulation steps in selected renderer")
		command("quit")
		if not check(await wait_for(func():return not EditorInterface.is_playing_scene() and plugin.author_debugger.worlds.is_empty()),"F5 game stops cooperatively and debugger disconnects"): return
	if without_native:
		ProjectSettings.set_setting(Settings.MODE,Settings.MUJOCO)
		check(ProjectSettings.save()==OK,"retain saved native request for OFF editor reopen validation")
	else:choice.select(Settings.MUJOCO);choice.item_selected.emit(Settings.MUJOCO)
func finish() -> void:
	if EditorInterface.is_playing_scene():
		command("quit")
		if not await wait_for(func():return not EditorInterface.is_playing_scene(),10): EditorInterface.stop_playing_scene()
	var failed := checks.filter(func(row):return not row.passed).size()
	var result := {"checks":checks,"passed":checks.size()-failed,"failed":failed,"samples":samples}
	var name := "preset-reopen.json" if "--component-preset-reopen" in OS.get_cmdline_user_args() else "preset.json" if "--component-preset" in OS.get_cmdline_user_args() else "preview.json" if "--component-preview" in OS.get_cmdline_user_args() else "reopen.json" if "--reopen" in OS.get_cmdline_user_args() else "results.json"
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("F5_RENDERER_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed}))
	plugin.get_tree().quit(0 if failed==0 else 1)
