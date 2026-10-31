@tool
extends EditorPlugin
var failed:=0
var passed:=0
func _enter_tree() -> void:
	if "--grid-editor-test" in OS.get_cmdline_user_args(): call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	EditorInterface.open_scene_from_path("res://Main.tscn")
	for i in 20: await get_tree().process_frame
	var scene:=EditorInterface.get_edited_scene_root()
	var controls=scene.get_node("Runtime/DisplayControls")
	var model=scene.get_node("Runtime/Model")
	var material=controls.grid_material
	check(material is ShaderMaterial and scene.get_node("RuntimeViewer").bound_world==null,"editor has grid without runtime viewer")
	var viewer: Node=scene.get_node("RuntimeViewer")
	check(is_instance_valid(viewer.ui) and is_instance_valid(viewer.ui.get_node_or_null("PreviewData")) and viewer.ui.get_node("PreviewData").text.contains("预览数据"),"editor component exposes labeled placeholder UI data")
	check(viewer._session==null and scene.get_node("GodotExtras")._performance_source==null and scene.get_node("Runtime")._view_session==null and not viewer.is_processing_input(),"editor preview creates no session, native bridge, system sampler or input ownership")
	check(viewer.ui.details.get("joints",[]).any(func(row):return str(row.name).contains("Preview")),"default editor preview includes dynamic joint placeholders")
	var preview := preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd").new()
	preview.name="CustomPreview";preview.ui_scene=load("res://custom_ui.tscn")
	var theme := Theme.new();theme.set_color("font_color","Label",Color(.1,.9,.8));preview.ui_theme=theme
	scene.add_child(preview)
	for unused in 4:await get_tree().process_frame
	check(preview.bound_world==null and preview._session==null and preview.ui.theme==theme,"custom editor UI uses its authored Theme without runtime services")
	check(preview.ui.get_node("MainLayout/MuJoCoLeftPanel/@MarginContainer@6/@VBoxContainer@7/OptionSection/@Label@9").text=="Custom options","inherited custom editor UI preserves authored widget text")
	var packed := PackedScene.new();packed.pack(scene)
	var snapshot := packed.get_state();var internal_packed := false
	for index in snapshot.get_node_count():
		if str(snapshot.get_node_path(index)).contains("ViewerUI") or str(snapshot.get_node_path(index)).contains("PreviewData"):internal_packed=true
	check(not internal_packed,"saving the authored scene excludes internal preview/runtime UI children")
	preview.queue_free()
	check(model.visuals.values().filter(func(mesh): return mesh.material_override==material).size()==1,"editor grid affects only existing floor mesh")
	model.show_editor_preview()
	for i in 5: await get_tree().process_frame
	check(controls.grid_material==material and model.visuals.values().filter(func(mesh): return mesh.material_override==material).size()==1,"editor visual rebuild reuses original grid material")
	check(is_equal_approx(material.get_shader_parameter("spacing_m"),1.0),"saved editor grid retains metre spacing")
	print("GALLERY_EDITOR_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	get_tree().quit(0 if failed==0 else 1)
