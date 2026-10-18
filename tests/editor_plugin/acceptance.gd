@tool
extends RefCounted
var checks := []
var failed := 0
func check(ok: bool, label: String) -> void:
	checks.append({"name":label, "passed":ok})
	if not ok:
		failed += 1
		printerr("FAIL: " + label)
func entity(doc: RefCounted, kind: String, n: String) -> Dictionary:
	for e in doc.inspect().entities:
		if e.kind == kind and e.name == n:
			return e.properties
	return {}
func same_snapshot(a: Dictionary, b: Dictionary) -> bool:
	if a.xml != b.xml or a.source != b.source:
		return false
	for key in a.state:
		if a.state[key] is Array:
			if a.state[key].size() != b.state[key].size():
				return false
			for i in a.state[key].size():
				if abs(float(a.state[key][i])-float(b.state[key][i])) > 1e-12:
					return false
		elif abs(float(a.state[key])-float(b.state[key])) > 1e-12:
			return false
	return true
func capture(plugin: EditorPlugin, filename: String) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var folder := arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(folder)
			EditorInterface.set_main_screen_editor("MuJoCo")
			for i in range(5):
				await plugin.get_tree().process_frame
			await RenderingServer.frame_post_draw
			check(plugin.get_viewport().get_texture().get_image().save_png(folder.path_join(filename)) == OK, "real editor screenshot " + filename)
func form_button(panel: Control, text: String) -> Button:
	for child in panel.fields.get_children():
		if child is Button and child.text == text:
			return child
	return null

func button_regression(panel: Control, doc: RefCounted, undo: UndoRedo) -> void:
	for trial in [
		["joint", "hinge", "set_qpos", "0.25"],
		["actuator", "position_drive", "kp", "95.0"],
		["actuator", "position_drive", "kv", "9.0"],
		["body", "box", "pos", "[-0.8, 0.1, 2.0]"]
	]:
		panel.select_entity(trial[0], trial[1])
		var key: String = trial[2]
		panel.inputs[key].text = trial[3]
		panel.inputs[key].text_changed.emit(trial[3])
		var apply := form_button(panel, "Apply to physics")
		check(apply != null, "Apply button exists " + key)
		if apply == null:
			return
		var input_count: int = panel.inputs.size()
		apply.pressed.emit()
		var revision: int = doc.inspect().revision
		apply.pressed.emit()
		check(doc.inspect().revision == revision, "retired Apply ignores repeated signal " + key)
		await panel.get_tree().process_frame
		check(panel.inputs.size() == input_count and panel.inputs.has(key) and is_instance_valid(panel.inputs[key]) and panel.inputs[key].is_inside_tree(), "pressed Apply retains fields " + key)
		var actual: Dictionary = entity(doc, trial[0], trial[1])
		var expected: Variant = JSON.parse_string(trial[3])
		var value: Variant = actual.qpos[0] if key == "set_qpos" else actual[key]
		check(is_equal_approx(float(value),float(expected)) if not value is Array else value == expected, "pressed Apply writes physics " + key)
		check(undo.undo(), "undo after pressed Apply " + key)
		check(undo.redo(), "redo after pressed Apply " + key)
		await panel.get_tree().process_frame
		check(panel.inputs.has(key) and is_instance_valid(panel.inputs[key]), "undo redo retains form " + key)
		if not panel.inputs.has(key):
			return
		panel.inputs[key].text = "invalid pending value"
		panel.inputs[key].text_changed.emit(panel.inputs[key].text)
		var invalid_apply := form_button(panel, "Apply to physics")
		var before_invalid: Dictionary = doc.snapshot()
		invalid_apply.pressed.emit()
		check(panel.pending and doc.snapshot() == before_invalid and panel.inputs.size() == input_count, "pressed invalid Apply preserves draft " + key)
		var discard := form_button(panel, "Discard pending fields")
		discard.pressed.emit()
		await panel.get_tree().process_frame
		check(not panel.pending and panel.inputs.has(key) and panel.inputs[key].text != "invalid pending value", "pressed Discard restores fields " + key)

func run(plugin: EditorPlugin) -> void:
	var panel = plugin.panel
	var doc: RefCounted = plugin.state.document
	plugin._make_visible(true)
	check(panel.import_mjcf("res://fixtures/pendulum.xml"), "editor imports actual MJCF")
	await capture(plugin, "01-imported-mjcf.png")
	check(doc.inspect().version == "3.16.0", "runtime version pinned")
	check(entity(doc, "joint", "hinge").type == "hinge", "joint type and name")
	check(entity(doc, "body", "arm").mass == 2, "compiled body mass")
	check(entity(doc, "actuator", "position_drive").kp == 20, "position gain read")
	check(entity(doc, "actuator", "velocity_drive").kp == "N/A", "velocity kp not applicable")
	check(entity(doc, "actuator", "motor_drive").kv == "N/A", "motor not misclassified PD")
	check(panel.execute({"op":"set", "kind":"actuator", "name":"position_drive", "values":{"kp":80,"kv":8}}), "PD transaction")
	check(entity(doc, "actuator", "position_drive").kp == 80 and entity(doc, "actuator", "position_drive").kv == 8, "PD gains in compiled model")
	check(panel.execute({"op":"control", "name":"position_drive", "value":0.5}), "live control")
	doc.set_paused(false)
	for i in range(100):
		doc.advance(.01)
	doc.set_paused(true)
	check(abs(entity(doc,"joint","hinge").qpos[0]) > .1, "real physics updates joint display")
	var before: Dictionary = doc.snapshot()
	var revision: int = doc.inspect().revision
	check(not doc.edit({"op":"set", "kind":"actuator", "name":"motor_drive", "values":{"kp":10}}), "non-PD edit rejected")
	check(doc.snapshot() == before and doc.inspect().revision == revision, "invalid edit rolls back")
	check(not doc.import_file("res://fixtures/missing.xml"), "missing import rejected")
	check(doc.snapshot() == before, "failed import keeps document")
	check(not doc.edit({"op":"set", "kind":"body", "name":"arm", "values":{"mass":1e-30}}), "candidate compile failure")
	check(doc.snapshot() == before, "compile failure preserves full state")
	for shape in ["box", "sphere", "cylinder"]:
		check(panel.execute({"op":"add","shape":shape,"name":shape}), "create " + shape)
		check(panel.execute({"op":"set","kind":"geom","name":shape+"_geom","values":{"size":([.3,0,0] if shape=="sphere" else [.3,.4,0] if shape=="cylinder" else [.3,.4,.5]),"density":500,"friction":[.7,.01,.001]}}), "edit geometry " + shape)
		var mass: float = entity(doc,"body",shape).mass
		var expected := .6*.8*1.0*500 if shape=="box" else 4.0/3.0*PI*pow(.3,3)*500 if shape=="sphere" else PI*pow(.3,2)*.8*500
		check(abs(mass-expected) < .001, "real density and dimensions " + shape)
		check(panel.execute({"op":"set","kind":"body","name":shape,"values":{"mass":3.0,"pos":[-1 if shape=="box" else 0 if shape=="sphere" else 1,0,2]}}), "body mass pose " + shape)
		check(abs(entity(doc,"body",shape).mass-3)<.001, "compiled mass " + shape)
	check(entity(doc,"geom","cylinder_geom").type == 5, "true MuJoCo cylinder")
	check(panel.meshes.cylinder_geom.mesh is CylinderMesh, "matching cylinder visual")
	check(abs(panel.meshes.cylinder_geom.mesh.height-.8)<.001, "matching cylinder height")
	check(not doc.edit({"op":"set","kind":"geom","name":"box_geom","values":{"density":200}}), "explicit inertia density ambiguity diagnosed")
	panel.frame_all()
	await capture(plugin, "02-three-primitives.png")
	var joint_before: Array = entity(doc,"joint","hinge").qpos
	check(panel.execute({"op":"delete","kind":"body","name":"sphere"}), "delete primitive")
	check(entity(doc,"body","sphere").is_empty(), "deleted body absent")
	check(entity(doc,"joint","hinge").qpos == joint_before, "structural edit preserves compatible state")
	var history: EditorUndoRedoManager = plugin.get_undo_redo()
	check(history.get_object_history_id(plugin.state) == 0, "document uses global editor history")
	var undo: UndoRedo = history.get_history_undo_redo(history.get_object_history_id(plugin.state))
	check(undo.undo(), "Godot editor undo")
	check(not entity(doc,"body","sphere").is_empty(), "undo restores body")
	check(undo.redo(), "Godot editor redo")
	check(entity(doc,"body","sphere").is_empty(), "redo deletes body")
	await button_regression(panel, doc, undo)
	panel.select_entity("actuator","position_drive")
	panel.inputs.control.text = "0.8"
	check(panel.apply_fields(), "actual property form apply")
	check(entity(doc,"actuator","position_drive").control == .8, "form writes real control")
	panel.select_entity("geom","cylinder_geom")
	panel.inputs.size.text = "[-1, 0.4, 0]"
	panel.pending = true
	check(not panel.apply_fields() and panel.pending, "invalid UI retains pending edits")
	check(not panel.import_mjcf("res://fixtures/pendulum.xml"), "pending edits block replacement")
	panel.pending = false
	panel.refresh()
	var saved: Dictionary = doc.snapshot()
	check(panel.save_document("user://acceptance.gmj.json"), "atomic document save")
	check(panel.execute({"op":"delete","kind":"body","name":"cylinder"}), "change after save")
	check(panel.open_document("user://acceptance.gmj.json"), "reopen document")
	check(same_snapshot(doc.snapshot(), saved), "persistence restores full model control and state")
	check(not panel.save_document("res://fixtures/pendulum.xml"), "source XML overwrite rejected")
	for i in range(3):
		plugin.state.deactivate()
		check(plugin.state.document == null, "native preview released " + str(i))
		plugin.state.activate()
		doc = plugin.state.document
		check(same_snapshot(doc.snapshot(), saved), "session reactivate " + str(i))
	var retained: Dictionary = doc.snapshot()
	check(panel.import_mjcf("res://fixtures/external/model.xml"), "relative include plus external OBJ")
	check(panel.meshes.tetra_geom.mesh is ArrayMesh, "imported mesh actual triangles")
	check(panel.save_document("user://external.gmj.json"), "save external asset document")
	check(panel.open_document("user://external.gmj.json"), "reopen resolved external asset paths")
	var external: Dictionary = doc.snapshot()
	check(not doc.import_file("res://fixtures/unsupported.xml"), "unsupported heightfield diagnosed")
	check(doc.snapshot() == external, "unsupported import rollback")
	check(doc.restore(retained), "restore prior document")
	panel.refresh()
	panel.select_entity("geom", "cylinder_geom")
	panel.inputs.size.text = "[0.4, 0.6, 0]"
	panel.pending = true
	panel.save_recovery()
	panel.pending = false
	check(panel.open_document(panel.recovery_path), "recovery document opens")
	check(panel.pending and panel.inputs.size.text == "[0.4, 0.6, 0]", "unapplied draft survives recovery")
	panel.pending = false
	panel.refresh()
	EditorInterface.open_scene_from_path("res://fixtures/other.tscn")
	await plugin.get_tree().process_frame
	check(not entity(doc, "body", "cylinder").is_empty(), "scene switch retains independent document")
	panel.frame_all()
	for i in range(4):
		await plugin.get_tree().process_frame
	panel.select_entity("geom", "cylinder_geom")
	await capture(plugin, "02-edited-cylinder.png")
	var fall: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(fall.edit({"op":"add","shape":"cylinder","name":"falling"}), "isolated cylinder created")
	check(not fall.edit({"op":"add","shape":"cylinder","name":"falling"}), "duplicate click name rejected")
	fall.set_paused(false)
	check(not fall.edit({"op":"add","shape":"box","name":"unsafe"}), "running topology rejected")
	for i in range(300):
		fall.advance(.01)
	var cylinder_y := 0.0
	for geom in fall.geometry():
		if geom.name == "falling_geom":
			cylinder_y = geom.transform.origin.y
	check(abs(cylinder_y-.25) < .03 and fall.inspect().contacts > 0, "cylinder real gravity floor contact")
	fall = null
	var constrained: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(constrained.import_file("res://fixtures/framed.xml"), "framed and fromto MJCF retained")
	check(not constrained.edit({"op":"set","kind":"body","name":"framed","values":{"pos":[0,0,0]}}), "ambiguous source frame pose diagnosed")
	check(not constrained.edit({"op":"set","kind":"geom","name":"fromto_geom","values":{"size":[.2,.4,0]}}), "fromto-derived size diagnosed")
	constrained = null
	advanced_properties(panel, doc)
	var root := plugin.get_tree().root
	var remembered: RefCounted = plugin.state
	for i in range(2):
		EditorInterface.set_plugin_enabled("mujoco_editor", false)
		await root.get_tree().process_frame
		check(remembered.document == null, "disable plugin releases native model " + str(i))
		EditorInterface.set_plugin_enabled("mujoco_editor", true)
		await root.get_tree().process_frame
		check(remembered.document != null and not entity(remembered.document, "body", "cylinder").is_empty(), "enable plugin restores document " + str(i))
	# Do not dereference the disposed plugin instance. The test runner is independent.
	remembered.dirty = false
	var result := {"passed":checks.size()-failed,"failed":failed,"checks":checks}
	var out := "user://editor-results.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			out=arg.trim_prefix("--report=")
	var file := FileAccess.open(out,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("EDITOR_RESULT "+JSON.stringify(result))
	root.get_tree().quit(0 if failed==0 else 1)

func advanced_properties(panel: Control, doc: RefCounted) -> void:
	var isolated: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(isolated.import_file("res://fixtures/pendulum.xml"), "advanced fixture")
	var changes := {"limited":true,"range":[-.7,.9],"damping":.25,"frictionloss":.1}
	check(isolated.edit({"op":"set","kind":"joint","name":"hinge","values":changes}), "joint limits damping friction transaction")
	var joint := entity(isolated,"joint","hinge")
	check(joint.range == changes.range and joint.damping == .25 and joint.frictionloss == .1, "compiled joint parameters match")
	var before: Dictionary = isolated.snapshot()
	for values in [{"range":[1,-1]}, {"damping":-.1}, {"frictionloss":-.1}, {"limited":1}]:
		check(not isolated.edit({"op":"set","kind":"joint","name":"hinge","values":values}) and same_snapshot(before,isolated.snapshot()), "invalid joint rollback " + str(values))
	check(isolated.edit({"op":"set","kind":"body","name":"arm","values":{"mass":3.0,"inertia":[.2,.3,.4],"ipos":[0,0,-.3],"iquat":[1,0,0,0]}}), "manual inertia and mass atomic edit")
	var body := entity(isolated,"body","arm")
	check(body.mass == 3.0 and body.inertia == [.2,.3,.4] and body.inertia_mode == "manual", "manual inertia overrides geometry")
	before = isolated.snapshot()
	for values in [{"inertia":[1,.1,.1]}, {"inertia":[0,.1,.1]}, {"inertia_mode":"automatic","mass":2}]:
		check(not isolated.edit({"op":"set","kind":"body","name":"arm","values":values}) and same_snapshot(before,isolated.snapshot()), "invalid inertia rollback " + str(values))
	check(not isolated.edit({"op":"set","kind":"geom","name":"arm_geom","values":{"density":20}}), "manual inertia rejects ignored density")
	check(isolated.edit({"op":"set","kind":"body","name":"arm","values":{"inertia_mode":"automatic"}}), "return to inferred inertia: " + isolated.get_error())
	check(abs(entity(isolated,"body","arm").mass-2)<1e-8, "geom explicit mass takes priority over density")
	check(isolated.edit({"op":"set","kind":"geom","name":"arm_geom","values":{"density":100}}), "density explicitly replaces geom mass")
	check(abs(entity(isolated,"body","arm").mass-3.2)<1e-8, "density changes inferred body mass")
	var restored: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(restored.restore(isolated.snapshot()) and same_snapshot(restored.snapshot(),isolated.snapshot()), "new parameters save restore")
	check(isolated.edit({"op":"add","shape":"sphere","name":"round"}), "sphere created for dimensions")
	before = isolated.snapshot()
	check(not isolated.edit({"op":"set","kind":"geom","name":"round_geom","values":{"size":[.3,.4,.5]}}) and same_snapshot(before,isolated.snapshot()), "sphere rejects ellipsoid-like dimensions")
	panel.select_entity("geom","cylinder_geom")
	before = doc.snapshot()
	check(panel.transform_selection("move",1), "viewport operation moves selection")
	var undo: UndoRedo = panel.plugin.get_undo_redo().get_history_undo_redo(panel.plugin.get_undo_redo().get_object_history_id(panel.state))
	undo.undo()
	check(same_snapshot(before,doc.snapshot()), "viewport move undo")
	undo.redo()
	check(panel.transform_selection("rotate",1), "viewport operation rotates selection")
	check(panel.transform_selection("size",1), "viewport operation resizes physics geometry")
	panel.pending = true
	before = doc.snapshot()
	check(not panel.transform_selection("move",1) and same_snapshot(before,doc.snapshot()), "viewport operation cannot discard draft")
	panel.pending = false
	panel.frame_all()
	var point: Vector2 = panel.camera.unproject_position(panel.meshes.cylinder_geom.global_position)
	check(panel.pick_geometry(point) == "cylinder_geom", "actual viewport triangle picking selects cylinder")
