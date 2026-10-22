@tool
extends EditorDebuggerPlugin
signal changed
var instances := {}
var outcomes := {}

func _has_capture(capture: String) -> bool:
	return capture == "mujoco_heightfield"

var session_ids: Array[int] = []

func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	session_ids.append(session_id)
	session.started.connect(session_started.bind(session_id))
	session.stopped.connect(session_stopped.bind(session_id))
	if session.is_active(): session.send_message("mujoco_heightfield:list", [])

func session_started(session_id: int) -> void:
	get_session(session_id).send_message("mujoco_heightfield:list", [])

func session_stopped(session_id: int) -> void:
	for key in outcomes.keys():
		if key.begins_with(str(session_id)+":"): outcomes.erase(key)
	for key in instances.keys():
		if instances[key].session == session_id: instances.erase(key)
	changed.emit()

func shutdown() -> void:
	for id in session_ids:
		var session := get_session(id)
		if session.started.is_connected(session_started.bind(id)): session.started.disconnect(session_started.bind(id))
		if session.stopped.is_connected(session_stopped.bind(id)): session.stopped.disconnect(session_stopped.bind(id))
	session_ids.clear()
	instances.clear();outcomes.clear()

func _capture(message: String, data: Array, session_id: int) -> bool:
	if data.size() != 1: return false
	if message == "mujoco_heightfield:finished" and data[0] is Dictionary:
		outcomes[str(session_id)+":"+str(data[0].id)]=data[0].duplicate(true)
		changed.emit();return true
	if message == "mujoco_heightfield:instance" and data[0] is Dictionary:
		var info: Dictionary = data[0].duplicate(true)
		info.session = session_id
		instances[str(session_id) + ":" + str(info.id)] = info
		changed.emit()
		return true
	if message == "mujoco_heightfield:removed":
		instances.erase(str(session_id) + ":" + str(data[0]))
		changed.emit()
		return true
	return false

func send(key: String, operation: String, payload: Dictionary) -> bool:
	if not instances.has(key): return false
	var info: Dictionary = instances[key]
	if info.pending: return false
	var session := get_session(info.session)
	if not session.is_active(): return false
	payload = payload.duplicate(true)
	payload.id = info.id
	payload.revision = info.revision
	# Immediately lock this target against repeated clicks until runtime acknowledges.
	outcomes.erase(key)
	info.pending = true
	session.send_message("mujoco_heightfield:" + operation, [payload])
	changed.emit()
	return true
