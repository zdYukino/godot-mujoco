class_name MjSimulationControls
extends VBoxContainer
## Place outside MjEnvironmentHost so game UI and clock survive simulation resets/rebuilds.
@export var environment_host: MjEnvironmentHost:
	set(value):
		environment_host=value
		if is_inside_tree(): sync_targets()
@export var runtime_world: MjRuntimeWorld:
	set(value):
		runtime_world=value
		if is_inside_tree(): sync_targets()
var game_elapsed := 0.0
var status: Label
var count: SpinBox
var feedback := ""
var bound_host: MjEnvironmentHost
var bound_world: MjRuntimeWorld
var pending_command := 0

func add_button(label: String, action: Callable) -> void:
	var button := Button.new()
	button.text=label
	button.pressed.connect(action)
	add_child(button)

func target() -> MjRuntimeWorld:
	if is_instance_valid(environment_host) and environment_host.is_inside_tree():
		return environment_host.world if is_instance_valid(environment_host.world) and environment_host.world.is_inside_tree() else null
	return runtime_world if is_instance_valid(runtime_world) and runtime_world.is_inside_tree() else null

func disconnect_host() -> void:
	if is_instance_valid(bound_host):
		if bound_host.rebuild_finished.is_connected(on_rebuild_finished): bound_host.rebuild_finished.disconnect(on_rebuild_finished)
		if bound_host.tree_exiting.is_connected(on_host_exiting): bound_host.tree_exiting.disconnect(on_host_exiting)
	bound_host=null

func disconnect_world() -> void:
	if is_instance_valid(bound_world):
		if bound_world.command_finished.is_connected(on_command_finished): bound_world.command_finished.disconnect(on_command_finished)
		if bound_world.tree_exiting.is_connected(on_world_exiting): bound_world.tree_exiting.disconnect(on_world_exiting)
	bound_world=null
	pending_command=0

func sync_targets() -> void:
	var host: MjEnvironmentHost=environment_host if is_instance_valid(environment_host) and environment_host.is_inside_tree() else null
	if bound_host!=host:
		disconnect_host()
		bound_host=host
		feedback=""
		if bound_host:
			bound_host.rebuild_finished.connect(on_rebuild_finished)
			bound_host.tree_exiting.connect(on_host_exiting)
			if bound_host.rebuilding: feedback="Environment rebuild requested"
			elif not bound_host.last_error.is_empty(): feedback="环境重建失败 / Environment rebuild failed: " + bound_host.last_error
	var world := target()
	if bound_world!=world:
		disconnect_world()
		bound_world=world
		if bound_world:
			bound_world.command_finished.connect(on_command_finished)
			bound_world.tree_exiting.connect(on_world_exiting)

func on_host_exiting() -> void:
	disconnect_host()
	disconnect_world()

func on_world_exiting() -> void:
	disconnect_world()

func on_rebuild_finished(success: bool, error: String) -> void:
	sync_targets()
	feedback="环境重建成功 / Environment rebuild succeeded" if success else "环境重建失败 / Environment rebuild failed: " + error

func on_command_finished(result: Dictionary) -> void:
	if result.get("request",0)!=pending_command or pending_command==0: return
	pending_command=0
	feedback="Completed: " + str(result.command) if result.success else "Failed: " + str(result.error)

func request_rebuild() -> void:
	sync_targets()
	if not is_instance_valid(bound_host): feedback="Use MjEnvironmentHost to rebuild a saved environment";return
	feedback="Environment rebuild requested" if bound_host.request_rebuild_environment(true) else "Environment rebuild rejected: " + bound_host.last_error

func _exit_tree() -> void:
	disconnect_host()
	disconnect_world()

func _enter_tree() -> void:
	sync_targets()

func command(method: String, argument: Variant = null) -> void:
	sync_targets()
	var world := target()
	if not is_instance_valid(world): feedback="No configured world";return
	var accepted: bool=world.call(method) if argument==null else world.call(method,argument)
	if accepted: pending_command=world.command_request
	feedback="Requested: " + method if accepted else world.last_error

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	status=Label.new()
	add_child(status)
	add_button("暂停仿真 / Pause",func():command("request_pause",true))
	add_button("恢复仿真 / Resume",func():command("request_pause",false))
	count=SpinBox.new()
	count.min_value=1;count.max_value=1000;count.value=1;count.step=1
	count.update_on_text_changed=true
	add_child(count)
	add_button("单步 N 次 / Step N",func():
		count.apply()
		command("step_simulation",int(count.value)))
	add_button("记录仿真快照 / Capture",func():command("capture_snapshot"))
	add_button("重置仿真：保留增删 / Reset state",func():command("reset_simulation"))
	add_button("重建已保存环境：丢弃运行时增删",request_rebuild)

func _process(delta: float) -> void:
	game_elapsed+=delta
	sync_targets()
	var world := target()
	if not is_instance_valid(world): status.text="Game %.3f s — no world\n%s" % [game_elapsed,feedback];return
	var info := world.info()
	status.text="Game %.3f s | Simulation %.3f s | %s\n%s\n%s" % [game_elapsed,info.get("time",0.0),"Paused" if info.get("paused",true) else "Running",feedback,world.last_error]
