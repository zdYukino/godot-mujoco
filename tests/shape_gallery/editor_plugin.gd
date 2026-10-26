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
	var controls=scene.get_node("DisplayControls")
	var model=scene.get_node("Model")
	var material=controls.grid_material
	check(material is ShaderMaterial and controls.help_panel==null,"editor has grid without runtime help or control overlay")
	check(model.visuals.values().filter(func(mesh): return mesh.material_override==material).size()==1,"editor grid affects only existing floor mesh")
	model.show_editor_preview()
	for i in 5: await get_tree().process_frame
	check(controls.grid_material==material and model.visuals.values().filter(func(mesh): return mesh.material_override==material).size()==1,"editor visual rebuild reuses original grid material")
	check(is_equal_approx(material.get_shader_parameter("spacing_m"),1.0),"saved editor grid retains metre spacing")
	print("GALLERY_EDITOR_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	get_tree().quit(0 if failed==0 else 1)
