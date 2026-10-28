extends RefCounted
const Author = preload("author_resource.gd")
const Xml = preload("author_xml.gd")
static var worlds := {}
static var next_request := 0

static func attach(world: Node) -> void:
	world.author_live_id = str(world.get_path()) + "#" + str(world.get_instance_id())
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
	EngineDebugger.send_message("mujoco_author:world", [{"id":world.author_live_id, "scene":source.scene_file_path, "path":path, "status":world.info().get("compile_status", ""), "revision":world.info().get("design_revision", 0)}])

static func request(world: Node, command: Dictionary) -> int:
	if not world or not world.editor_connected: return 0
	next_request += 1
	PhysicsServer3D.call("scene_pause_for_author", world.space)
	EngineDebugger.send_message("mujoco_author:request", [{"id":world.author_live_id, "request":next_request, "command":command.duplicate(true)}])
	return next_request

static func receive(message: String, data: Array) -> bool:
	if data.size() != 1 or not data[0] is Dictionary: return false
	var value: Dictionary = data[0]
	var reference: WeakRef = worlds.get(value.get("id"), weakref(null))
	var world: Node = reference.get_ref()
	if not world: return true
	match message:
		"hello":
			world.editor_connected = true
			world.editor_connection_changed.emit(true)
		"pause":
			if PhysicsServer3D.call("scene_pause_for_author", world.space): EngineDebugger.send_message("mujoco_author:paused", [{"id":world.author_live_id, "epoch":value.epoch}])
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
			return false
	return true
