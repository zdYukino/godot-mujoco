extends RefCounted
const Trace = preload("author_trace.gd")
const Author = preload("author_resource.gd")
const Xml = preload("author_xml.gd")
static var worlds := {}
static var next_request := 0
static var receive_depth := 0

static func attach(world: Node) -> void:
	world.author_live_id = str(world.get_path()) + "#" + str(world.get_instance_id()) + "#" + Crypto.new().generate_random_bytes(8).hex_encode()
	worlds[world.author_live_id] = weakref(world)
	if EngineDebugger.is_active():
		if not EngineDebugger.has_capture("mujoco_author"): EngineDebugger.register_message_capture("mujoco_author", receive)
		publish(world)

static func detach(world: Node) -> void:
	worlds.erase(world.author_live_id)
	if EngineDebugger.is_active():
		EngineDebugger.send_message("mujoco_author:removed", [world.author_live_id])
		if worlds.is_empty() and EngineDebugger.has_capture("mujoco_author"): EngineDebugger.unregister_message_capture("mujoco_author")

static func publish(world: Node) -> void:
	if not EngineDebugger.is_active(): return
	var source: Node = world
	while source.owner: source = source.owner
	var path := str(source.get_path_to(world))
	EngineDebugger.send_message("mujoco_author:world", [{"id":world.author_live_id, "scene":source.scene_file_path, "path":path, "status":world.info().get("compile_status", ""), "revision":world.info().get("design_revision", 0), "source_signature":preload("world_layout.gd").signature(world.source_layout)}])

static func publish_instances(world: Node) -> void:
	if not world or not EngineDebugger.is_active(): return
	var instances := []
	for node in preload("world_layout.gd").nodes(world):
		if not node is MjModelInstance or not node.model_rid.is_valid(): continue
		var outcome: Dictionary = node.last_preset_result.duplicate(true)
		outcome.erase("state")
		instances.append({"id":node.live_id, "instance_id":node.design_instance_id, "label":str(node.get_path()), "revision":node.state().get("property_revision", 0), "pending":node.edit_request!=0, "error":node.last_error, "preset":outcome})
	EngineDebugger.send_message("mujoco_author:instances", [{"id":world.author_live_id, "instances":instances}])

static func request(world: Node, command: Dictionary) -> int:
	if not world or not world.editor_connected: return 0
	if Trace.enabled(): Trace.event("game_request_before", {"command":command,"info":world.info()})
	next_request += 1
	PhysicsServer3D.call("scene_pause_for_author", world.space)
	EngineDebugger.send_message("mujoco_author:request", [{"id":world.author_live_id, "request":next_request, "command":command.duplicate(true)}])
	if Trace.enabled(): Trace.event("game_request_sent", {"request":next_request,"info":world.info()})
	return next_request

static func receive(message: String, data: Array) -> bool:
	if data.size() != 1 or not data[0] is Dictionary: return false
	var value: Dictionary = data[0]
	var reference: WeakRef = worlds.get(value.get("id"), weakref(null))
	var world: Node = reference.get_ref()
	if not world: return true
	receive_depth+=1
	if Trace.enabled(): Trace.event("game_receive_before", {"depth":receive_depth,"world":world.author_live_id,"trace":value.get("_gmj_trace",{}),"message":message,"epoch":value.get("epoch",-1),"request":value.get("request",-1),"info":world.info()})
	match message:
		"preset", "cancel_preset", "control":
			for node in preload("world_layout.gd").nodes(world):
				if not node is MjModelInstance or node.live_id != value.get("instance", ""): continue
				if message == "preset": node.request_control_preset(value.get("preset", {}), int(value.get("revision", -1)))
				elif message == "cancel_preset": node.cancel_control_preset()
				else: node.set_control(value.get("actuator", ""), value.get("value", NAN))
		"hello":
			publish_instances(world)
			world.editor_connected = true
			world.editor_connection_changed.emit(true)
		"pause":
			world.manual_resume_required = true
			world.resume_after_capture = false
			var paused: bool=PhysicsServer3D.call("scene_pause_for_author", world.space)
			if Trace.enabled():Trace.event("game_pause_result",{"depth":receive_depth,"world":world.author_live_id,"epoch":value.epoch,"success":paused,"trace":value.get("_gmj_trace",{}),"revision":world.info().get("design_revision")})
			if paused:
				var ack={"id":world.author_live_id,"epoch":value.epoch}
				if value.has("_gmj_trace"):ack["_gmj_trace"]=value._gmj_trace
				if Trace.enabled():Trace.event("game_ack_attempt",{"depth":receive_depth,"ack":ack,"debugger_active":EngineDebugger.is_active()})
				EngineDebugger.send_message("mujoco_author:paused", [ack])
		"patch":
			world.stage_editor_layout(value.layout)
		"cancel":
			world.cancel_author_compile()
		"reply":
			world.design_request_finished.emit(value)
		"disconnect":
			world.editor_connected = false
			world.editor_connection_changed.emit(false)
		_:
			receive_depth-=1
			return false
	if Trace.enabled(): Trace.event("game_receive_after", {"depth":receive_depth,"world":world.author_live_id,"trace":value.get("_gmj_trace",{}),"message":message,"epoch":value.get("epoch",-1),"info":world.info()})
	receive_depth-=1
	return true
