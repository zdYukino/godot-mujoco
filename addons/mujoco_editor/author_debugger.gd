@tool
extends EditorDebuggerPlugin
const Trace = preload("res://addons/godot_mujoco/model/author_trace.gd")
const Layout = preload("res://addons/godot_mujoco/model/world_layout.gd")
var plugin: EditorPlugin
var worlds := {}
var sessions: Array[int] = []
signal instances_changed
var tick := 0.0
var epoch := 0
var trace_send_seq := 0

func _has_capture(capture: String) -> bool:
	return capture == "mujoco_author"

func _setup_session(session_id: int) -> void:
	sessions.append(session_id)
	var session := get_session(session_id)
	session.stopped.connect(stopped.bind(session_id))

func stopped(session_id: int) -> void:
	for key in worlds.keys():
		if worlds[key].session == session_id: worlds.erase(key)
	instances_changed.emit()

func editor_world(info: Dictionary) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path != info.scene: return null
	return root.get_node_or_null(info.path)

func send(info: Dictionary, operation: String, payload: Dictionary) -> void:
	var session := get_session(info.session)
	var active := session.is_active()
	if Trace.enabled():
		trace_send_seq+=1
		payload["_gmj_trace"]={"editor_pid":OS.get_process_id(),"session":info.session,"world":info.id,"send_seq":trace_send_seq,"epoch":payload.get("epoch",-1),"sent_us":Time.get_ticks_usec()}
		Trace.event("editor_send_attempt",{"operation":operation,"active":active,"trace":payload._gmj_trace,"request_epoch":info.get("request_epoch",-1),"ack_epoch":info.get("ack_epoch",-1),"sent_epoch":info.get("sent_epoch",-1)})
	if not active: return
	payload.id = info.id
	session.send_message("mujoco_author:" + operation, [payload])
	if Trace.enabled():Trace.event("editor_send_return",{"operation":operation,"trace":payload._gmj_trace})

func _capture(message: String, data: Array, session_id: int) -> bool:
	if data.size() != 1: return false
	if message == "mujoco_author:removed":
		worlds.erase(str(session_id) + ":" + str(data[0])); instances_changed.emit(); return true
	if not data[0] is Dictionary: return false
	var value: Dictionary = data[0]
	if Trace.enabled() and message in ["mujoco_author:world","mujoco_author:paused","mujoco_author:request"]: Trace.event("editor_receive", {"session":session_id,"message":message,"value":value})
	var key := str(session_id) + ":" + str(value.get("id", ""))
	if message == "mujoco_author:world":
		value.session = session_id
		value.ack_epoch = -1
		value.request_epoch = 0
		value.signature = ""
		value.sent_signature = ""
		value.sent_epoch = 0
		var node := editor_world(value)
		if node:
			value.signature = value.get("source_signature", "")
			value.sent_signature = value.signature
		worlds[key] = value
		if node: send(value, "hello", {})
		return true
	if not worlds.has(key): return true
	var info: Dictionary = worlds[key]
	if message == "mujoco_author:instances":
		info.instances = value.get("instances", []).duplicate(true)
		instances_changed.emit()
		return true
	if message == "mujoco_author:paused":
		if Trace.enabled():Trace.event("editor_ack_before",{"session":session_id,"world":info.id,"old":info.ack_epoch,"incoming":value.epoch,"request":info.request_epoch,"trace":value.get("_gmj_trace",{})})
		info.ack_epoch = int(value.epoch)
		if Trace.enabled():Trace.event("editor_ack_after",{"session":session_id,"world":info.id,"ack":info.ack_epoch,"request":info.request_epoch,"trace":value.get("_gmj_trace",{})})
		return true
	if message == "mujoco_author:request":
		var node := editor_world(info)
		var result: Dictionary = plugin.execute_game_design(node, value.get("command", {})) if node else {"success":false, "error":"请在编辑器打开对应的运行场景。"}
		result.request = value.request
		send(info, "reply", result)
		if node: pause_world(node)
		return true
	return false

func signature(layout: Dictionary) -> String:
	return Layout.signature(layout)

func model_world(model: Node) -> Node:
	var node := model
	while node:
		if node.has_method("poll_author_world"): return node
		node = node.get_parent()
	return null

func pause_model(model: Node) -> void:
	var world := model_world(model)
	if world: pause_world(world)

func cancel_model(model: Node) -> void:
	var world := model_world(model)
	if not world: return
	for info in worlds.values():
		if editor_world(info)==world: send(info,"cancel",{})

func pause_world(world: Node) -> void:
	for info in worlds.values():
		if editor_world(info) != world: continue
		epoch += 1
		info.request_epoch = epoch
		send(info, "pause", {"epoch":epoch})

func apply_model(model: Node, _result: Dictionary) -> void:
	var world := model_world(model)
	if world: synchronize(world)

func models_valid(world: Node) -> bool:
	for node in Layout.nodes(world):
		if not node.has_method("author_definition") or not node.design: continue
		if node.design.validated_revision != node.design.revision or node.design.validated_context != node.compilation_signature() or not node.design.validation_error.is_empty(): return false
		if node.author_scene and (node.author_scene.due_ms > 0 or node.author_scene.compiler.busy()): return false
	return true

func synchronize(world: Node) -> void:
	var layout := Layout.capture(world)
	var current := signature(layout)
	for info in worlds.values():
		if editor_world(info) != world: continue
		if info.signature != current:
			info.signature = current
			pause_world(world)
		var handshake_ready: bool=not (info.sent_signature == current and int(info.sent_epoch) == int(info.request_epoch)) and int(info.ack_epoch) == int(info.request_epoch)
		var valid := false
		if handshake_ready or Trace.enabled(): valid=models_valid(world)
		if Trace.enabled():
			var gate={"id":info.id,"session":info.session,"scene":info.scene,"path":info.path,"current":current,"signature":info.signature,"sent_signature":info.sent_signature,"request_epoch":info.request_epoch,"ack_epoch":info.ack_epoch,"sent_epoch":info.sent_epoch,"valid":valid}
			if info.get("trace_gate",{}) != gate:
				Trace.event("editor_gate",gate);info["trace_gate"]=gate.duplicate(true)
		if not handshake_ready or not valid: continue
		info.sent_signature = current
		info.sent_epoch = info.request_epoch
		send(info, "patch", {"layout":layout})

func poll(delta: float) -> void:
	tick += delta
	if tick < .05: return
	tick = 0
	for info in worlds.values():
		var world := editor_world(info)
		if world: synchronize(world)

func shutdown() -> void:
	for info in worlds.values(): send(info, "disconnect", {})
	for session_id in sessions:
		var session := get_session(session_id)
		if session.stopped.is_connected(stopped.bind(session_id)): session.stopped.disconnect(stopped.bind(session_id))
	worlds.clear()
	sessions.clear()

func runtime_targets() -> Dictionary:
	var result := {}
	for world_key in worlds:
		for item in worlds[world_key].get("instances", []):
			var value: Dictionary = item.duplicate(true)
			value.world = world_key
			result[str(world_key) + "/" + str(item.id)] = value
	return result

func send_preset(target: String, operation: String, payload: Dictionary) -> bool:
	var targets := runtime_targets()
	if not targets.has(target): return false
	var value: Dictionary = targets[target]
	if value.pending and operation != "cancel_preset": return false
	var session := get_session(worlds[value.world].session)
	if not session.is_active(): return false
	payload = payload.duplicate(true)
	payload.instance = value.id
	payload.revision = value.revision
	send(worlds[value.world], operation, payload)
	for item in worlds[value.world].get("instances", []):
		if item.id == value.id: item.pending = true
	instances_changed.emit()
	return true
