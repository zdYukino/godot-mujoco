@tool
extends RefCounted
var passed := 0
var failed := 0
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func write(path: String, text: String):
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string(text); file.close()
func tracking(panel) -> Dictionary:
	return {"source":panel.source_watch.source,"hashes":panel.source_watch.hashes.duplicate(true)}
func run(plugin) -> Dictionary:
	var panel = plugin.panel; var state = plugin.state
	panel.pending = false; state.dirty = false
	write("res://fixtures/include.xml",'<mujoco><geom name="floor" type="box" size="3 3 .1"/></mujoco>')
	check(panel.import_mjcf("res://fixtures/main.xml"),"P0 source transaction baseline")
	check(panel.execute({"op":"set","kind":"geom","name":"floor","values":{"friction":[.3,.005,.0001]}}),"P0 applied unsaved edit fixture")
	var edited: Dictionary = state.document.snapshot(); var tracked := tracking(panel)
	check(not panel.import_mjcf("res://fixtures/main.xml") and state.dirty and state.document.snapshot()==edited and tracking(panel)==tracked,"P0 ordinary Import protects dirty applied edits")
	# Independently reproduce the direct dedicated reload bypass, regardless of prior failure.
	state.dirty = true
	edited = state.document.snapshot(); tracked = tracking(panel)
	check(not panel.reimport_source() and state.dirty and state.document.snapshot()==edited and tracking(panel)==tracked,"P0 dedicated reload protects dirty edits without confirmation")
	for entry in ["import", "reload"]:
		state.dirty = false; panel.pending = true
		edited = state.document.snapshot(); tracked = tracking(panel)
		var result: bool = panel.import_mjcf("res://fixtures/main.xml") if entry=="import" else panel.reimport_source()
		check(not result and panel.pending and state.document.snapshot()==edited and tracking(panel)==tracked,"P0 pending draft protected at "+entry)
	panel.pending = false; state.dirty = false
	check(panel.import_mjcf("res://fixtures/main.xml"),"P0 reset clean source")
	var old_document: Dictionary = state.document.snapshot(); var old_tracking := tracking(panel)
	write("res://fixtures/include.xml",'<mujoco><geom name="floor" type="box" size="4 3 .1"/></mujoco>')
	check(panel.reimport_source(),"P0 clean explicit reload changed include")
	var new_document: Dictionary = state.document.snapshot(); var new_tracking := tracking(panel)
	var history = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(state))
	history.undo()
	check(state.document.snapshot()==old_document and tracking(panel)==old_tracking,"P0 reload Undo restores model and old source hash together")
	check(panel.source_watch.inspect(state.dirty).state=="冲突","P0 undone old document cannot display aligned with new source")
	check(panel.save_document("res://undo-source.gmj.json") and panel.source_watch.inspect(false).state=="源已变","P0 saving undone model does not falsely align new source")
	history.redo()
	check(state.document.snapshot()==new_document and tracking(panel)==new_tracking,"P0 reload Redo restores model and new source hash together")
	# Ordinary Import changes source identity; Undo must restore identity as well as hashes.
	state.dirty = false
	write("res://fixtures/second.xml",'<mujoco><worldbody><geom name="second" type="box" size="1 2 3"/></worldbody></mujoco>')
	old_document = state.document.snapshot(); old_tracking = tracking(panel)
	check(panel.import_mjcf("res://fixtures/second.xml"),"P0 clean ordinary Import changes source identity")
	new_document = state.document.snapshot(); new_tracking = tracking(panel)
	history.undo()
	check(state.document.snapshot()==old_document and tracking(panel)==old_tracking,"P0 ordinary Import Undo restores source identity and hashes")
	history.redo()
	check(state.document.snapshot()==new_document and tracking(panel)==new_tracking,"P0 ordinary Import Redo restores source identity and hashes")
	# Confirmation is the only opt-in override for both dirty and pending.
	state.dirty = true; panel.pending = true
	check(panel.reimport_source(true) and not panel.pending and not state.dirty,"P0 confirmed reload explicitly discards dirty/pending")
	var retained: Dictionary = state.document.snapshot(); var retained_tracking := tracking(panel)
	var raced: Dictionary = preload("res://addons/godot_mujoco/map/source_watch.gd").import_verified("res://fixtures/main.xml",func(): write("res://fixtures/include.xml",'<mujoco><geom name="floor" type="box" size="5 3 .1"/></mujoco>'))
	check(not raced.error.is_empty() and state.document.snapshot()==retained and tracking(panel)==retained_tracking,"P0 mutation between dependency hash and parse rejected")
	state.dirty = true; panel.pending = true
	write("res://fixtures/second.xml",'<mujoco><worldbody><geom type="invalid"/></worldbody></mujoco>')
	check(not panel.reimport_source(true) and panel.pending and state.dirty and state.document.snapshot()==retained and tracking(panel)==retained_tracking,"P0 confirmed invalid reload retains dirty/pending and provenance")
	panel.pending = false; state.dirty = false
	var height_session = preload("res://addons/godot_mujoco/map/session.gd").new()
	var contract_path := "res://fixtures/ramp.height.json"
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(contract_path))
	check(height_session.import_height("res://fixtures/ramp.raw",contract,contract_path),"P0 height contract file tracked")
	contract.unit = "cm"; write(contract_path,JSON.stringify(contract))
	check(contract_path in height_session.watch.inspect(false).changes,"P0 height contract-only unit change detected")
	height_session.close()
	print("SOURCE_TRANSACTION_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	return {"passed":passed,"failed":failed}
