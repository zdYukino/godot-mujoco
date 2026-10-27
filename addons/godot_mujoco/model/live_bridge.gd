extends RefCounted
# Editor and runtime exchange requests through Godot's existing debugger session.
# Node references are weak; IDs include the instance generation, not just its path.
static var instances := {}

static func attach(instance: Node) -> void:
	instances[instance.live_id] = weakref(instance)
	if EngineDebugger.is_active():
		if not EngineDebugger.has_capture("mujoco_live"):
			EngineDebugger.register_message_capture("mujoco_live", receive)
		publish(instance)

static func detach(instance: Node) -> void:
	if instance.live_id.is_empty(): return
	instances.erase(instance.live_id)
	if EngineDebugger.is_active(): EngineDebugger.send_message("mujoco_live:removed",[instance.live_id])
	if instances.is_empty() and EngineDebugger.has_capture("mujoco_live"):
		EngineDebugger.unregister_message_capture("mujoco_live")

static func publish(instance: Node) -> void:
	# Transport only serializable completion metadata, not native snapshot RIDs.
	var outcome=instance.last_preset_result.duplicate(true);outcome.erase("state")
	if EngineDebugger.is_active():
		EngineDebugger.send_message("mujoco_live:instance",[{
			"id":instance.live_id,"path":str(instance.get_path()),"revision":instance.property_revision,
			"resource":instance.model.resource_path,"pending":instance.edit_request != 0,"error":instance.last_error,"preset":outcome}])

static func receive(message: String, data: Array) -> bool:
	if message == "list":
		for reference in instances.values():
			var instance = reference.get_ref()
			if instance: publish(instance)
		return true
	if message not in ["apply", "control", "preset", "cancel_preset"] or data.size() != 1 or not data[0] is Dictionary: return false
	var request: Dictionary = data[0]
	var instance: Node = instances.get(request.get("id"), weakref(null)).get_ref()
	if not instance: return true
	if message == "preset":
		if request.get("preset") is Dictionary: instance.request_control_preset(request.preset,int(request.get("revision",-1)))
		else: instance.last_error="Invalid preset payload"
	elif message == "cancel_preset":
		if not instance.cancel_control_preset(): instance.last_error="Preset already executing/completed or no longer pending; refresh result"
	elif message == "apply":
		var path: String = request.get("resource", "")
		if not path.begins_with("res://") or path.get_extension() != "tres":
			instance.last_error = "Live apply requires a saved project model resource"
		else:
			var resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if resource is MjModelResource: instance.request_model_edit(resource,int(request.get("revision",-2)))
			else: instance.last_error = "Invalid model resource"
	else:
		if not instance.set_control(str(request.get("actuator","")),float(request.get("value",NAN))):
			instance.last_error = "Control rejected by instance/actuator limits"
		else: instance.last_error = ""
	publish(instance)
	return true
