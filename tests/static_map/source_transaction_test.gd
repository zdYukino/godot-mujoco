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
	# Hash/parse races remain meaningful for source archives; the retired
	# mutable MJCF document panel is no longer part of the map workflow.
	write("res://fixtures/include.xml",'<mujoco><geom name="floor" type="box" size="3 3 .1"/></mujoco>')
	var raced: Dictionary = preload("res://addons/godot_mujoco/map/source_watch.gd").import_verified("res://fixtures/main.xml",func(): write("res://fixtures/include.xml",'<mujoco><geom name="floor" type="box" size="5 3 .1"/></mujoco>'))
	check(not raced.error.is_empty(),"source mutation between hash and parse is rejected")
	var height_session = preload("res://addons/godot_mujoco/map/session.gd").new()
	var contract_path := "res://fixtures/ramp.height.json"
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(contract_path))
	check(height_session.import_height("res://fixtures/ramp.raw",contract,contract_path),"P0 height contract file tracked")
	contract.unit = "cm"; write(contract_path,JSON.stringify(contract))
	check(contract_path in height_session.watch.inspect(false).changes,"P0 height contract-only unit change detected")
	height_session.close()
	print("SOURCE_TRANSACTION_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	return {"passed":passed,"failed":failed}
