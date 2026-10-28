@tool
extends RefCounted
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
var plugin: EditorPlugin
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ",label)
func wait_for(condition: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call(): return true
		await plugin.get_tree().process_frame
	return false
func state() -> Dictionary:
	if not FileAccess.file_exists("res://live-state.json"): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string("res://live-state.json"))
	return value if value is Dictionary else {}
func settled() -> bool:
	var info: Dictionary = state().get("info",{})
	return info.get("compile_status")=="ready" and not info.get("design_pending",true)
func game(command: Dictionary) -> void:
	var output := FileAccess.open("res://live-command.json",FileAccess.WRITE); output.store_string(JSON.stringify(command)); output.close()
func run(editor: EditorPlugin) -> void:
	plugin = editor
	for frame in 30: await plugin.get_tree().process_frame
	var root: Node = World.new(); root.name = "LiveWorld"; root.start_paused = true
	root.world_design = Author.from_xml('<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody/></mujoco>').design
	var model := Model.new(); model.name = "Model"
	model.design = Author.from_xml('<mujoco><compiler angle="radian"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" size=".1"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>').design
	root.add_child(model); model.owner = root
	var terrain = load("res://addons/godot_mujoco/model/static_heightfield.gd").new(); terrain.name="Terrain"
	terrain.design = load("res://addons/godot_mujoco/model/heightfield_data.gd").new(); terrain.design.heights = PackedFloat32Array([0,0,0,0])
	root.add_child(terrain); terrain.owner=root
	var driver := Node.new(); driver.name="TestDriver"; driver.set_script(load("res://live_driver.gd"));root.add_child(driver);driver.owner=root
	var packed := PackedScene.new(); packed.pack(root); ResourceSaver.save(packed,"res://LiveWorld.tscn");root.free()
	EditorInterface.open_scene_from_path("res://LiveWorld.tscn")
	check(await wait_for(func():
		var current=EditorInterface.get_edited_scene_root()
		return current and str(current.name)=="LiveWorld" and current.get_node("Model").design.validated_revision==current.get_node("Model").design.revision and plugin._build()),"editor validates current version before F5")
	root=EditorInterface.get_edited_scene_root(); model=root.get_node("Model")
	packed=PackedScene.new();packed.pack(root);ResourceSaver.save(packed,"res://LiveWorld.tscn")
	EditorInterface.play_custom_scene("res://LiveWorld.tscn")
	var connected: bool = await wait_for(func(): return state().get("connected",false) and state().get("ready",false) and settled())
	check(connected,"actual F5 game connects to source editor")
	if connected:
		game({"op":"control","value":.2}); game({"op":"resume"})
		check(await wait_for(func():return state().get("info",{}).get("time",0)> .05),"game really integrates before source edit")
		var body: Node = model.get_node("arm")
		body.set("mjcf/mass",2.0)
		check(await wait_for(func():return state().get("info",{}).get("paused",false)),"Inspector source edit auto-pauses actual game")
		check(await wait_for(func():return settled() and state().models[0].bodies.get("arm",{}).get("mass")==2.0),"current source compiles and commits through debugger")
		check(state().info.paused,"successful live rebuild remains paused")
		var time: float=state().info.time
		for frame in 12: await plugin.get_tree().process_frame
		check(is_equal_approx(float(state().info.time),time),"actual MuJoCo time frozen until manual Continue")
		var geom: Node = model.get_node("arm/rod")
		geom.set("mjcf/color", Color(.2,.6,.9))
		geom.set("mjcf/opacity", .45)
		var texture := Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.2,.8,.3,1))
		texture.save_png("res://live-texture.png")
		geom.set("mjcf/texture_file", "res://live-texture.png")
		check(await wait_for(func():
			var current: Dictionary = state().get("models",[{}])[0].get("appearances",{}).get("rod",{})
			return settled() and current.get("texture",false) and is_equal_approx(float(current.get("color",[0,0,0,0])[3]),.45)), "live game receives MJCF texture and opacity through debugger")
		check(is_equal_approx(float(state().models[0].appearances.rod.color[0]),.2) and state().info.paused, "live appearance keeps color and stays paused until Continue")
		var id: String=model.design_instance_id
		game({"op":"duplicate_model","instance_id":id,"name":"Second"})
		check(await wait_for(func():return root.get_node_or_null("Second")!=null and state().get("models",[]).size()==2 and settled()),"game Add command creates persistent editor model and runtime instance")
		var second: Node=root.get_node_or_null("Second")
		check(second and second.owner==root and second.design.document_id!=model.design.document_id,"game copy owns independent author source")
		var undo: UndoRedo=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
		undo.undo()
		check(await wait_for(func():return root.get_node_or_null("Second")==null and state().get("models",[]).size()==1 and settled()),"one editor Undo removes game-created model from physics")
		undo.redo()
		check(await wait_for(func():return state().get("models",[]).size()==2 and settled()),"Redo recompiles game copy")
		game({"op":"terrain_update","path":"Terrain","index":0,"delta":.1})
		check(await wait_for(func():return is_equal_approx(root.get_node("Terrain").design.heights[0],.1) and settled() and is_equal_approx(float(state().terrain.committed.get("heights",[0])[0]),.1)),"game terrain button updates editor source and combined physics")
		packed=PackedScene.new();packed.pack(root)
		check(ResourceSaver.save(packed,"res://LiveSaved.tscn")==OK,"game requested designs serialize without runtime qpos")
		var saved: Node=load("res://LiveSaved.tscn").instantiate()
		check(saved.get_node_or_null("Second/arm/rod/_Visual")!=null and is_equal_approx(saved.get_node("Terrain").design.heights[0],.1),"saved scene retains game model and terrain design")
		saved.free()
		game({"op":"resume"})
		check(await wait_for(func():return state().info.time>time),"manual Continue resumes latest valid design")
	EditorInterface.stop_playing_scene()
	check(await wait_for(func():return plugin.author_debugger.worlds.is_empty()),"debugger disconnect clears runtime target")
	print("NODE_LIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
