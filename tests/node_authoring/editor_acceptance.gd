extends RefCounted
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
var checks := 0
var failures: Array[String] = []
var plugin: EditorPlugin

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); print("FAIL ", message)

func wait_valid(model: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if model.design.validated_revision == model.design.revision and model.author_scene.due_ms == 0 and not model.author_scene.compiler.busy() and model.author_scene.geometry_queue.is_empty(): return
		await plugin.get_tree().process_frame
	check(false, "compiler settled: " + model.last_error)

func appearance_editor(property_name: String) -> EditorProperty:
	for node in plugin.all_nodes(EditorInterface.get_inspector()):
		if node is EditorProperty and node.get_edited_property() == property_name: return node
	return null

func run(editor: EditorPlugin) -> void:
	plugin = editor
	var root := Node3D.new(); root.name = "AuthorTest"
	var model := Model.new(); model.name = "Model"
	model.design = Author.from_xml('<mujoco><compiler angle="radian"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" type="capsule" fromto="0 0 0 0 0 -.6" size=".04"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>').design
	root.add_child(model); model.owner = root
	var scene := PackedScene.new(); scene.pack(root)
	check(ResourceSaver.save(scene, "res://AuthorTest.tscn") == OK, "create fixture scene")
	root.free()
	EditorInterface.open_scene_from_path("res://AuthorTest.tscn")
	for frame in 10: await plugin.get_tree().process_frame
	var edited := EditorInterface.get_edited_scene_root()
	model = edited.get_node("Model")
	await wait_valid(model)
	check(model.author_scene.nodes.size() == 3, "formal body/geom/joint nodes created")
	var arm: Node3D = model.get_node("arm")
	var rod: Node3D = arm.get_node("rod")
	var joint: Node3D = arm.get_node("hinge")
	check(rod.get_node_or_null("_Visual") is MeshInstance3D, "geometry belongs to its body hierarchy")
	check(arm.owner == edited and rod.owner == edited and joint.owner == edited, "nodes owned by edited scene")
	check(joint.get("mjcf/type") == "hinge", "typed Inspector joint properties")
	var undo := plugin.get_undo_redo()
	undo.create_action("Inspector damping", UndoRedo.MERGE_DISABLE, joint)
	undo.add_do_property(joint, "mjcf/damping", .3)
	undo.add_undo_property(joint, "mjcf/damping", 0.0)
	undo.commit_action()
	await wait_valid(model)
	check(is_equal_approx(float(model.design.entity(joint.entity_id).attrs.damping), .3), "Inspector updates physical author field")
	var original: Transform3D = rod.transform
	var moved := original; moved.origin.x += .2
	undo.create_action("Native transform", UndoRedo.MERGE_DISABLE, rod)
	undo.add_do_property(rod, "transform", moved)
	undo.add_undo_property(rod, "transform", original)
	undo.commit_action()
	for frame in 5: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, moved.origin.x), "native transform writes source pose")
	var history := undo.get_history_undo_redo(undo.get_object_history_id(edited))
	history.undo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, original.origin.x), "one native undo restores author pose")
	history.redo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(is_equal_approx(model.design.entity(rod.entity_id).transform.origin.x, moved.origin.x), "redo restores physical author pose")
	var packed := PackedScene.new(); packed.pack(edited)
	check(ResourceSaver.save(packed, "res://Roundtrip.tscn") == OK, "save hierarchical scene")
	var reopened: PackedScene = ResourceLoader.load("res://Roundtrip.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
	var copy: Node = reopened.instantiate()
	check(copy.get_node_or_null("Model/arm/rod/_Visual") != null, "hierarchy and geometry serialize")
	check(copy.get_node("Model").design.document_id == model.design.document_id, "author identity persists")
	copy.free()
	var revision: int = model.design.revision
	var until := Time.get_ticks_msec()+1500
	while Time.get_ticks_msec()<until: await plugin.get_tree().process_frame
	check(model.design.revision==revision,"display refresh cannot generate author edits or compile loops")
	check(plugin._build(), "valid current author version permits F5")
	# Exercise the single creation entry through its actual button handler, then
	# change the physical joint type through the native Inspector/Undo path.
	var created := model.apply_author_command({"op":"add_body"})
	var body_id: String = created.selected
	created = model.apply_author_command({"op":"add_geom","id":body_id,"type":"box"})
	plugin.panel.select(model.author_scene.nodes[created.selected])
	var joint_buttons := []
	for control in plugin.panel.get_children():
		if control is Button and control.text.begins_with("新增 ") and control.text.ends_with("joint"): joint_buttons.append(control)
	check(joint_buttons.size()==1 and joint_buttons[0].text=="新增 joint", "one joint creation entry in the panel")
	joint_buttons[0].pressed.emit()
	await wait_valid(model)
	var added_joint := {}
	for entity in model.design.entities():
		if entity.kind=="joint" and entity.parent_id==body_id: added_joint=entity
	check(not added_joint.is_empty() and added_joint.attrs.type=="free", "joint button creates a free joint on the selected geom's body")
	var added_node: Node = model.author_scene.nodes[added_joint.id]
	check(EditorInterface.get_selection().get_selected_nodes()==[added_node], "new joint is selected for immediate Inspector editing")
	undo.create_action("Inspector joint type",UndoRedo.MERGE_DISABLE,added_node)
	undo.add_do_property(added_node,"mjcf/type","hinge")
	undo.add_undo_property(added_node,"mjcf/type","free")
	undo.commit_action()
	await wait_valid(model)
	check(model.design.entity(added_joint.id).attrs.type=="hinge", "default free joint remains editable through Inspector Type")
	check(appearance_editor("mjcf/axis") != null, "joint type layout changes still add hinge Inspector fields")
	history.undo()
	for frame in 8: await plugin.get_tree().process_frame
	await wait_valid(model)
	check(model.design.entity(added_joint.id).attrs.type=="free", "Inspector type undo restores the default free joint")
	check(appearance_editor("mjcf/axis") == null, "joint type undo removes hinge-only Inspector fields")
	EditorInterface.inspect_object(rod)
	for frame in 12: await plugin.get_tree().process_frame
	check(appearance_editor("mjcf/color") != null and appearance_editor("mjcf/opacity") != null and appearance_editor("mjcf/texture_file") != null, "Visibility exposes native color, opacity and texture property editors")
	check(rod.get_property_list().filter(func(field):return field.name == "mjcf/density").size() == 1, "appearance editor keeps inherited geom properties unique")
	if appearance_editor("mjcf/color"):
		var color_editor := appearance_editor("mjcf/color")
		var original_color: Color = rod.get("mjcf/color")
		var continuous := true
		for point in 8:
			if not is_instance_valid(color_editor): continuous = false; break
			color_editor.emit_changed("mjcf/color", original_color.lerp(Color(.15,.55,.85), float(point + 1) / 8), "", true)
			for frame in 3: await plugin.get_tree().process_frame
		if is_instance_valid(color_editor): color_editor.emit_changed("mjcf/color", Color(.15,.55,.85), "", false)
		await wait_valid(model)
		check(continuous and is_instance_valid(color_editor) and appearance_editor("mjcf/color") == color_editor, "continuous color edits and background compile preserve the active Inspector control")
		check(rod.get_node("_Visual").material_override.albedo_color.is_equal_approx(Color(.15,.55,.85)), "Inspector RGB refresh replaces the previous preview material")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/color").is_equal_approx(original_color), "one Undo restores the color before the continuous gesture")
		history.redo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/color").is_equal_approx(Color(.15,.55,.85)), "one Redo restores the final continuous color")
		appearance_editor("mjcf/opacity").emit_changed("mjcf/opacity", .4)
		await wait_valid(model)
		check(is_equal_approx(rod.get_node("_Visual").material_override.albedo_color.a,.4) and rod.get_node("_Visual").material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Inspector opacity changes MJCF and enables actual transparency")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(is_equal_approx(rod.get("mjcf/opacity"),1.0), "native Inspector undo restores MJCF opacity")
		history.redo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		var texture := Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.9,.2,.1,.8))
		check(texture.save_png("res://inspector-texture.png") == OK, "create Inspector texture fixture")
		appearance_editor("mjcf/texture_file").emit_changed("mjcf/texture_file", "res://inspector-texture.png")
		await wait_valid(model)
		check(rod.get_node("_Visual").material_override.albedo_texture != null, "Inspector file selection displays texture after background compile")
		var appearance_scene := PackedScene.new(); appearance_scene.pack(edited)
		check(ResourceSaver.save(appearance_scene,"res://AppearanceScene.tscn") == OK, "save hierarchical scene with MJCF material and texture")
		var appearance_copy: Node = ResourceLoader.load("res://AppearanceScene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
		check(is_equal_approx(appearance_copy.get_node("Model/arm/rod").get("mjcf/opacity"),.4) and appearance_copy.get_node("Model/arm/rod/_Visual").material_override.albedo_texture != null, "scene reopen retains source opacity and rendered texture")
		appearance_copy.free()
		var exported: String = plugin.export_author(model,"res://appearance-export")
		var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
		check(exported.begins_with("已导出") and document.import_file(ProjectSettings.globalize_path("res://appearance-export/model.xml")), "exported MJCF and texture assets compile independently")
		var rod_geometry: Dictionary = document.geometry().filter(func(geometry):return geometry.name == "rod")[0]
		check(rod_geometry.has("texture_image") and is_equal_approx(rod_geometry.color.a,.4), "export retains physical MJCF appearance rather than only Godot overrides")
		history.undo()
		for frame in 8: await plugin.get_tree().process_frame
		await wait_valid(model)
		check(rod.get("mjcf/texture_file") == "" and rod.get_node("_Visual").material_override.albedo_texture == null, "texture import is undoable through native Inspector history")
	print("NODE_EDITOR_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
