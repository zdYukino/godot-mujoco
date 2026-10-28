@tool
extends EditorDebuggerPlugin
const Layout = preload("res://addons/godot_mujoco/model/world_layout.gd")
var plugin: EditorPlugin
var worlds := {}
var sessions: Array[int] = []
var tick := 0.0
var epoch := 0

func _has_capture(capture: String) -> bool:
	return capture == "mujoco_author"

func _setup_session(session_id: int) -> void:
	sessions.append(session_id)
	var session := get_session(session_id)
	session.stopped.connect(stopped.bind(session_id))

func stopped(session_id: int) -> void:
	for key in worlds.keys():
		if worlds[key].session == session_id: worlds.erase(key)

func editor_world(info: Dictionary) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path != info.scene: return null
	return root.get_node_or_null(info.path)

func send(info: Dictionary, operation: String, payload: Dictionary) -> void:
	var session := get_session(info.session)
	if not session.is_active(): return
	payload.id = info.id
	session.send_message("mujoco_author:" + operation, [payload])

func _capture(message: String, data: Array, session_id: int) -> bool:
	if data.size() != 1: return false
	if message == "mujoco_author:removed": worlds.erase(str(session_id) + ":" + str(data[0])); return true
	if not data[0] is Dictionary: return false
	var value: Dictionary = data[0]
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
			value.signature = signature(Layout.capture(node))
			value.sent_signature = value.signature
		worlds[key] = value
		if node: send(value, "hello", {})
		return true
	if not worlds.has(key): return true
	var info: Dictionary = worlds[key]
	if message == "mujoco_author:paused":
		info.ack_epoch = int(value.epoch)
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
	var copy := layout.duplicate(true)
	for model in copy.get("models", []):
		for key in ["cache_path", "compiled_snapshot", "cached_entities", "cached_geometry", "collision_geometry"]: model.erase(key)
	return str(hash(var_to_bytes(copy)))

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
		if node.design.validated_revision != node.design.revision or not node.design.validation_error.is_empty(): return false
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
		if (info.sent_signature == current and int(info.sent_epoch) == int(info.request_epoch)) or int(info.ack_epoch) != int(info.request_epoch) or not models_valid(world): continue
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
