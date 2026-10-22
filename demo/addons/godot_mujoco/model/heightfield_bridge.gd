extends RefCounted
static var nodes := {}
static func attach(node: Node) -> void:
	nodes[node.live_id]=weakref(node)
	if EngineDebugger.is_active():
		if not EngineDebugger.has_capture("mujoco_heightfield"): EngineDebugger.register_message_capture("mujoco_heightfield",receive)
		publish(node)
static func detach(node: Node) -> void:
	nodes.erase(node.live_id)
	if EngineDebugger.is_active(): EngineDebugger.send_message("mujoco_heightfield:removed",[node.live_id])
	if nodes.is_empty() and EngineDebugger.has_capture("mujoco_heightfield"): EngineDebugger.unregister_message_capture("mujoco_heightfield")
static func publish(node: Node) -> void:
	if EngineDebugger.is_active(): EngineDebugger.send_message("mujoco_heightfield:instance",[{"id":node.live_id,"path":str(node.get_path()),"revision":node.revision,"pending":node.pending_request!=0,"error":node.last_error,"active":node.body_rid.is_valid()}])
static func receive(message: String,data: Array) -> bool:
	if message=="list":
		for ref in nodes.values():
			var node=ref.get_ref()
			if node: publish(node)
		return true
	if message not in ["apply","remove"] or data.size()!=1 or not data[0] is Dictionary: return false
	var payload:Dictionary=data[0]
	var node:Node=nodes.get(payload.get("id"),weakref(null)).get_ref()
	if not node: return true
	if message=="apply": node.request_snapshot(payload.get("snapshot",{}),int(payload.get("revision",-2)))
	elif int(payload.get("revision",-2))!=node.revision: node.last_error="Stale heightfield revision"
	else: node.request_remove()
	publish(node)
	return true
