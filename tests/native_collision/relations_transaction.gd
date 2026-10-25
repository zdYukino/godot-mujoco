extends SceneTree
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var passed := 0
var failed := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func run():
	for relation in ["pairs","excludes"]:
		var session:=Session.new()
		check(session.import_file("res://fixtures/box.obj","m","Y_UP"),relation+" input")
		var mesh: MeshInstance3D=session.meshes()[0]; var path:=str(session.visual.get_path_to(mesh))
		var other: MeshInstance3D=mesh.duplicate(); other.name="Other"; other.position.x=.6; mesh.get_parent().add_child(other)
		var other_path:=str(session.visual.get_path_to(other))
		check(session.configure(path,{"kind":"sphere","native_contact":true}) and session.configure(other_path,{"kind":"sphere","native_contact":true}),relation+" endpoints")
		check(session.configure_relations({relation:[{"first":path,"second":other_path}]}),relation+" relation")
		for proposal in [{"kind":"visual"},{"kind":"sphere","native_contact":false}]:
			var saved:=Package.pack(session,"res://relation_transaction_packages"); check(saved.error.is_empty(),relation+" prior save")
			var old_specs: Dictionary=session.specs; var old_relations: Dictionary=session.contact_relations
			var old_terrain: Array=session.terrains; var old_version: int=session.history.get_version(); var old_dirty: bool=session.dirty
			var old_mesh:=mesh.mesh; var old_export: String=session.watch.exported_hash
			var old_manifest_hash:=FileAccess.get_sha256(saved.path.path_join("manifest.json"))
			var accepted: bool=session.configure(path,proposal)
			check(not accepted,relation+" endpoint removal rejected "+str(proposal))
			check(not session.error.is_empty() and session.last_collision_attempt.actual_mode=="disabled",relation+" rejection diagnosed")
			check(is_same(session.specs,old_specs) and is_same(session.contact_relations,old_relations) and is_same(session.terrains,old_terrain) and mesh.mesh==old_mesh,relation+" config/resource identities unchanged")
			check(session.history.get_version()==old_version and session.dirty==old_dirty and session.watch.exported_hash==old_export,relation+" Undo/dirty/export unchanged")
			# Restore only after recording a regression, so all scenarios can report.
			if accepted: session.history.undo()
			var built:=session.build_scene(); check(built.error.is_empty(),relation+" previous map remains buildable")
			if built.error.is_empty(): built.scene.free()
			var repacked:=Package.pack(session,"res://relation_transaction_packages"); check(repacked.error.is_empty() and Package.validate(saved.path).is_empty() and FileAccess.get_sha256(saved.path.path_join("manifest.json"))==old_manifest_hash,relation+" previous package intact and map can resave")
		var original:=session.specs.duplicate(true)
		check(session.configure(path,{"kind":"box","native_contact":true}),relation+" valid representation edit allowed")
		var built:=session.build_scene(); check(built.error.is_empty(),relation+" valid edit builds")
		if built.error.is_empty(): built.scene.free()
		session.history.undo(); check(session.specs==original,relation+" valid edit Undo")
		# Heightfield endpoints share the same relation invariant.
		var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/ramp.height.json"))
		check(session.import_height("res://fixtures/ramp.raw",contract),relation+" height input")
		var name: String=session.terrains[0].name
		check(session.configure_terrain_native(name,{}),relation+" native height endpoint")
		check(session.configure_relations({relation:[{"first":path,"second":name}]}),relation+" height relation")
		var terrain_ref: Array=session.terrains; var version: int=session.history.get_version()
		var accepted: bool=session.configure_terrain_native(name,null)
		check(not accepted and is_same(session.terrains,terrain_ref) and session.history.get_version()==version,relation+" height native cancellation atomic")
		if accepted: session.history.undo()
		if relation=="pairs":
			var previous_specs: Dictionary=session.specs; var old_version: int=session.history.get_version()
			check(not session.configure(path,{"kind":"plane"}) and is_same(session.specs,previous_specs) and session.history.get_version()==old_version,"representation change cannot invalidate existing sphere-hfield pair")
		session.close()
	var session:=Session.new(); check(session.import_file("res://fixtures/box.obj","m","Y_UP"),"unsupported pair input")
	var mesh: MeshInstance3D=session.meshes()[0]; var plane1:=str(session.visual.get_path_to(mesh))
	var other: MeshInstance3D=mesh.duplicate(); other.name="Other"; mesh.get_parent().add_child(other); var plane2:=str(session.visual.get_path_to(other))
	check(session.configure(plane1,{"kind":"plane"}) and session.configure(plane2,{"kind":"plane"}),"two plane endpoints")
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/ramp.height.json"))
	check(session.import_height("res://fixtures/ramp.raw",contract) and session.import_height("res://fixtures/ramp.raw",contract),"two height inputs")
	var h1: String=session.terrains[0].name; var h2: String=session.terrains[1].name
	check(session.configure_terrain_native(h1,{}) and session.configure_terrain_native(h2,{}),"native height endpoints")
	check(session.configure_relations({"excludes":[{"first":plane1,"second":h1}]}),"retain valid exclude baseline")
	for endpoints in [[plane1,plane2],[plane1,h1],[h1,h2]]:
		var old_specs: Dictionary=session.specs; var old_relations: Dictionary=session.contact_relations; var version: int=session.history.get_version()
		var old_dirty: bool=session.dirty
		check(not session.configure_relations({"pairs":[{"first":endpoints[0],"second":endpoints[1]}]}) and "无碰撞分发函数" in session.error,"unsupported pair diagnosed "+str(endpoints))
		check(is_same(session.specs,old_specs) and is_same(session.contact_relations,old_relations) and session.history.get_version()==version and session.dirty==old_dirty,"unsupported pair preserves previous transaction")
		var built:=session.build_scene(); check(built.error.is_empty(),"previous exclude scene still builds")
		if built.error.is_empty(): built.scene.free()
	var prior_specs: Dictionary=session.specs; var prior_version: int=session.history.get_version()
	check(not session.configure(plane1,{"kind":"compound_boxes","native_contact":true,"contact":{"friction":[1.6,.01,.001]},"parts":[{"center":Vector3.ZERO,"size":Vector3.ONE}]}) and is_same(session.specs,prior_specs) and session.history.get_version()==prior_version and session.last_collision_attempt.actual_mode=="disabled","compound native request explicitly rejected atomically")
	session.specs=session.specs.duplicate(true); session.specs[plane1]={"kind":"compound_boxes","native_contact":true}
	var invalid_scene:=session.build_scene(); check(not invalid_scene.error.is_empty() and "compound_boxes" in invalid_scene.error,"persisted unsupported native compound request cannot silently build")
	session.specs=prior_specs
	session.close()
	var panel:=preload("res://addons/mujoco_editor/map_panel.gd").new(); root.add_child(panel)
	panel.strategy.select(5); panel.strategy.item_selected.emit(5)
	check(panel.native_contact.disabled and not panel.native_contact.button_pressed and not panel.advanced.editable and "尚未接入" in panel.native_contact.tooltip_text,"compound UI disables unsupported native controls")
	panel.strategy.select(2); panel.strategy.item_selected.emit(2); panel.native_contact.button_pressed=true
	check(not panel.native_contact.disabled and panel.native_contact.button_pressed and panel.advanced.editable,"supported primitive native controls remain available")
	panel.shutdown(); panel.free()
	print("NATIVE_RELATION_TRANSACTION_RESULT ",JSON.stringify({"passed":passed,"failed":failed})); quit(0 if failed==0 else 1)
