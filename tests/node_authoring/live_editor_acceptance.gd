@tool
extends RefCounted
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
var plugin: EditorPlugin
var checks := 0
var failures := []
var run_id := ""
var channel := ""
var scene_path := ""
var saved_path := ""
var command_seq := 0
var acknowledgements: Array = []
var failure_states: Array = []
var duplicate_history: Array = []
var duplicate_sample_ms := 0
var duplicate_last_evaluation: Dictionary = {}
var abort_requested := false
var stale := {}
var cleanup_result := {}
func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures.append(label); print("FAIL ",label)
		var detail=diagnostic_snapshot(state());detail["label"]=label;detail["duplicate_history"]=duplicate_history.duplicate(true)
		detail["duplicate_last_evaluation"]=duplicate_last_evaluation.duplicate(true)
		failure_states.append(detail)
		FileAccess.open("res://live-failure-states.json",FileAccess.WRITE).store_string(JSON.stringify(failure_states,"  "))
		abort_requested = true
	return ok
func wait_for(condition: Callable, seconds := 30.0, during_cleanup := false) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if abort_requested and not during_cleanup: return false
		if condition.call(): return true
		await plugin.get_tree().process_frame
	return false
func state() -> Dictionary:
	var path := channel.path_join("state.json")
	if not FileAccess.file_exists(path): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary and value.get("run_id", "") == run_id else {}
func settled() -> bool:
	var current := state()
	var info: Dictionary = current.get("info",{})
	return current.get("ready",false) and info.get("compile_status")=="ready" and not info.get("design_pending",true)
func game(command: Dictionary) -> bool:
	if abort_requested: return false
	command_seq += 1
	var packet := {"run_id":run_id,"sequence":command_seq,"command":command}
	var target := channel.path_join("command-%06d.json"%command_seq)
	var output := FileAccess.open(target+".tmp",FileAccess.WRITE); output.store_string(JSON.stringify(packet)); output.close()
	if DirAccess.rename_absolute(target+".tmp",target)!=OK: return false
	var completed := await wait_for(func():return state().get("acks",{}).get(str(command_seq),{}).get("completed",false))
	var ack: Dictionary=state().get("acks",{}).get(str(command_seq),{}).duplicate(true)
	ack["sequence"]=command_seq;ack["op"]=command.get("op","");acknowledgements.append(ack)
	print("LIVE_ACK ",JSON.stringify(ack))
	return completed and ack.get("accepted",false) and ack.get("success",false)
func run(editor: EditorPlugin) -> void:
	plugin = editor
	await run_scenario()
	# The scenario coroutine has returned: release its PackedScene/Image/Node refs
	# before stopping the game and allowing the editor to shut down.
	await finalize_run()

func run_scenario() -> void:
	run_id = OS.get_environment("GMJ_TEST_RUN_ID")
	if run_id.is_empty(): run_id=Crypto.new().generate_random_bytes(16).hex_encode()
	channel="user://mj-live-tests/"+run_id
	scene_path="res://LiveWorld-"+run_id+".tscn"
	saved_path="res://LiveSaved-"+run_id+".tscn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(channel))
	stale = {}
	for path in ["res://live-state.json","res://live-command.json","res://live-state.tmp"]:
		if FileAccess.file_exists(path): stale[path]=FileAccess.get_file_as_string(path);DirAccess.remove_absolute(path)
	FileAccess.open("res://live-stale-before.json",FileAccess.WRITE).store_string(JSON.stringify(stale))
	for file in DirAccess.get_files_at(channel): DirAccess.remove_absolute(channel.path_join(file))
	# Deliberately poison a fresh channel once: no reader may accept another run's state.
	FileAccess.open(channel.path_join("state.json"),FileAccess.WRITE).store_string(JSON.stringify({"run_id":"stale-run","connected":true,"ready":true}))
	if not check(state().is_empty(),"prior-run state is rejected"): return
	for frame in 30: await plugin.get_tree().process_frame
	var root: Node = World.new(); root.name = "LiveWorld"; root.start_paused = true
	root.world_design = Author.from_xml('<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody/></mujoco>').design
	var model := Model.new(); model.name = "Model"
	model.design = Author.from_xml('<mujoco><compiler angle="radian"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" size=".1"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>').design
	root.add_child(model); model.owner = root
	var terrain = load("res://addons/godot_mujoco/model/static_heightfield.gd").new(); terrain.name="Terrain"
	terrain.design = load("res://addons/godot_mujoco/model/heightfield_data.gd").new(); terrain.design.heights = PackedFloat32Array([0,0,0,0])
	root.add_child(terrain); terrain.owner=root
	var driver := Node.new(); driver.name="TestDriver"; driver.set_script(load("res://live_driver.gd"));driver.run_id=run_id;root.add_child(driver);driver.owner=root
	var packed := PackedScene.new(); packed.pack(root); ResourceSaver.save(packed,scene_path);root.free()
	EditorInterface.open_scene_from_path(scene_path)
	if not check(await wait_for(func():
		var current=EditorInterface.get_edited_scene_root()
		return current and current.scene_file_path==scene_path and current.get_node("TestDriver").run_id==run_id and str(current.name)=="LiveWorld" and current.get_node("Model").design.validated_revision==current.get_node("Model").design.revision and plugin._build()),"editor validates current version before F5"): return
	root=EditorInterface.get_edited_scene_root(); model=root.get_node("Model")
	packed=PackedScene.new();packed.pack(root);ResourceSaver.save(packed,scene_path)
	EditorInterface.play_custom_scene(scene_path)
	var connected: bool = await wait_for(func(): return state().get("connected",false) and state().get("ready",false) and settled())
	if not check(connected,"actual F5 game connects to source editor"): return
	if connected:
		if not check(await game({"op":"control","value":.2}),"control command acknowledged"): return
		if not check(await game({"op":"resume"}),"initial Continue acknowledged"): return
		if not check(await wait_for(func():return state().get("info",{}).get("time",0)> .05),"game really integrates before source edit"): return
		var body: Node = model.get_node("arm")
		body.set("mjcf/mass",2.0)
		if not check(await wait_for(func():return state().get("info",{}).get("paused",false)),"Inspector source edit auto-pauses actual game"): return
		if not check(await wait_for(func():return settled() and state().models[0].bodies.get("arm",{}).get("mass")==2.0),"current source compiles and commits through debugger"): return
		if not check(state().info.paused,"successful live rebuild remains paused"): return
		var time: float=state().info.time
		for frame in 12: await plugin.get_tree().process_frame
		if not check(is_equal_approx(float(state().info.time),time),"actual MuJoCo time frozen until manual Continue"): return
		var geom: Node = model.get_node("arm/rod")
		geom.set("mjcf/color", Color(.2,.6,.9))
		geom.set("mjcf/opacity", .45)
		var texture := Image.create(4,4,false,Image.FORMAT_RGBA8); texture.fill(Color(.2,.8,.3,1))
		texture.save_png("res://live-texture.png")
		geom.set("mjcf/texture_file", "res://live-texture.png")
		if not check(await wait_for(func():
			var current: Dictionary = state().get("models",[{}])[0].get("appearances",{}).get("rod",{})
			return settled() and current.get("texture",false) and is_equal_approx(float(current.get("color",[0,0,0,0])[3]),.45)), "live game receives MJCF texture and opacity through debugger"): return
		if not check(is_equal_approx(float(state().models[0].appearances.rod.color[0]),.2) and state().info.paused, "live appearance keeps color and stays paused until Continue"): return
		var id: String=model.design_instance_id
		if not check(await game({"op":"duplicate_model","instance_id":id,"name":"Second"}),"duplicate command acknowledged"): return
		if not check(await wait_for(func():return duplicate_is_settled(root)),"game Add command creates persistent editor model and runtime instance"): return
		var second: Node=root.get_node_or_null("Second")
		if not check(second and second.owner==root and second.design.document_id!=model.design.document_id,"game copy owns independent author source"): return
		var undo: UndoRedo=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
		undo.undo()
		if not check(await wait_for(func():return root.get_node_or_null("Second")==null and state().get("models",[]).size()==1 and settled()),"one editor Undo removes game-created model from physics"): return
		undo.redo()
		if not check(await wait_for(func():return state().get("models",[]).size()==2 and settled()),"Redo recompiles game copy"): return
		if not check(await game({"op":"terrain_update","path":"Terrain","index":0,"delta":.1}),"terrain command acknowledged"): return
		if not check(await wait_for(func():return is_equal_approx(root.get_node("Terrain").design.heights[0],.1) and settled() and is_equal_approx(float(state().terrain.committed.get("heights",[0])[0]),.1)),"game terrain button updates editor source and combined physics"): return
		packed=PackedScene.new();packed.pack(root)
		if not check(ResourceSaver.save(packed,saved_path)==OK,"game requested designs serialize without runtime qpos"): return
		var saved: Node=load(saved_path).instantiate()
		var saved_ok: bool=saved.get_node_or_null("Second/arm/rod/_Visual")!=null and is_equal_approx(saved.get_node("Terrain").design.heights[0],.1)
		saved.free()
		if not check(saved_ok,"saved scene retains game model and terrain design"): return
		if not check(await game({"op":"resume"}),"final Continue acknowledged"): return
		if not check(await wait_for(func():return state().info.time>time),"manual Continue resumes latest valid design"): return
func finalize_run() -> void:
	var before_stop := state()
	var game_pid := int(before_stop.get("pid",-1))
	EditorInterface.stop_playing_scene()
	var disconnected := await wait_for(func():return plugin.author_debugger.worlds.is_empty(),30.0,true)
	var stopped := await wait_for(func():return not EditorInterface.is_playing_scene(),10.0,true)
	cleanup_result={"game_pid":game_pid,"debugger_disconnected":disconnected,"editor_playing_stopped":stopped,"aborted":abort_requested,"command_seq":command_seq}
	check(disconnected and stopped,"debugger disconnect clears runtime target")
	var protocol := {"checks":checks,"failed":failures.size(),"failures":failures,"cleanup":cleanup_result,"run_id":run_id,"channel":ProjectSettings.globalize_path(channel),"acks":acknowledgements,"last_state":state(),"removed_legacy_files":stale.keys(),"failure_states":failure_states,"duplicate_history":duplicate_history,"duplicate_last_evaluation":duplicate_last_evaluation}
	FileAccess.open("res://live-protocol-result.json",FileAccess.WRITE).store_string(JSON.stringify(protocol,"  "))
	# Finalize both files after every check, including the disconnect check.
	FileAccess.open("res://live-failure-states.json",FileAccess.WRITE).store_string(JSON.stringify(failure_states,"  "))
	print("NODE_LIVE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	preload("res://addons/godot_mujoco/model/author_trace.gd").flush()
	plugin.get_tree().quit(0 if failures.is_empty() else 1)

func compiler_diagnostic(service: Node) -> Dictionary:
	if not is_instance_valid(service): return {}
	var result={"busy":service.busy(),"pid":service.process_id,"serial":service.serial,"session_id":service.session_id,"age_ms":Time.get_ticks_msec()-service.started_ms}
	for field in ["active","queued"]:
		var job: Dictionary=service.get(field)
		var summary: Dictionary={}
		for key in ["job_id","revision","generation","directory"]:
			if job.has(key):summary[key]=job[key]
		result[field]=summary
	return result

func diagnostic_snapshot(game_state: Dictionary) -> Dictionary:
	var current=EditorInterface.get_edited_scene_root()
	var result={"run_id":run_id,"target_scene":scene_path,"sampled_ms":Time.get_ticks_msec(),"game":game_state.duplicate(true),"command_seq":command_seq,"acks":acknowledgements.duplicate(true)}
	if not is_instance_valid(current):return result
	result["editor_scene"]=current.scene_file_path
	result["editor_world"]={"instance_id":current.get_instance_id(),"path":str(current.get_path()),"scene":current.scene_file_path}
	result["editor_pid"]=OS.get_process_id()
	result["editor_children"]=Array(current.get_children()).map(func(n):return str(n.name))
	result["debugger_worlds"]=plugin.author_debugger.worlds.duplicate(true)
	var sessions: Array=[]
	for session_id in plugin.author_debugger.sessions:
		var session=plugin.author_debugger.get_session(session_id)
		sessions.append({"id":session_id,"active":session.is_active()})
	result["debugger_sessions"]=sessions
	var models: Array=[]
	for node in current.get_children():
		if not node is MjModelInstance:continue
		var item={"name":str(node.name),"id":node.design_instance_id,"revision":node.design.revision,"validated_revision":node.design.validated_revision,"validation_error":node.design.validation_error,"validated_context":node.design.validated_context,"compilation_signature":node.compilation_signature(),"instance_id":node.get_instance_id(),"path":str(node.get_path())}
		if node.author_scene:item["due_ms"]=node.author_scene.due_ms;item["compiler"]=compiler_diagnostic(node.author_scene.compiler)
		models.append(item)
	result["editor_models"]=models
	return result
func duplicate_is_settled(source: Node) -> bool:
	var game_state=state()
	var info: Dictionary=game_state.get("info",{})
	var conditions={"editor_second":source.get_node_or_null("Second")!=null,"game_two_models":game_state.get("models",[]).size()==2,"ready":game_state.get("ready",false),"compile_ready":info.get("compile_status")=="ready","design_committed":not info.get("design_pending",true)}
	var now=Time.get_ticks_msec()
	# Editor ticks and game ticks are separate clocks; sequence binds game observations.
	duplicate_last_evaluation={"sampled_ms":now,"sequence":game_state.get("sequence",-1),"game":game_state,"conditions":conditions}
	if now-duplicate_sample_ms>=250:
		duplicate_sample_ms=now
		var sample=diagnostic_snapshot(game_state);sample["conditions"]=conditions
		sample["conditions_sequence"]=game_state.get("sequence",-1)
		duplicate_history.append(sample)
		if duplicate_history.size()>128:duplicate_history.pop_front()
	return conditions.editor_second and conditions.game_two_models and conditions.ready and conditions.compile_ready and conditions.design_committed
