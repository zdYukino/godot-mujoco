class_name MjSimulationControls
extends VBoxContainer
## Place outside MjEnvironmentHost so game UI and clock survive simulation resets/rebuilds.
@export var environment_host: MjEnvironmentHost
@export var runtime_world: MjRuntimeWorld
var game_elapsed := 0.0
var status: Label
var count: SpinBox
var feedback := ""

func add_button(label: String, action: Callable) -> void:
	var button := Button.new()
	button.text=label
	button.pressed.connect(action)
	add_child(button)

func target() -> MjRuntimeWorld:
	return environment_host.world if is_instance_valid(environment_host) else runtime_world

func command(method: String, argument: Variant = null) -> void:
	var world := target()
	if not is_instance_valid(world): feedback="No configured world";return
	var accepted: bool=world.call(method) if argument==null else world.call(method,argument)
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
	add_button("重建已保存环境：丢弃运行时增删",func():
		if not is_instance_valid(environment_host): feedback="Use MjEnvironmentHost to rebuild a saved environment";return
		feedback="Environment rebuild requested" if environment_host.request_rebuild_environment(true) else environment_host.last_error)

func _process(delta: float) -> void:
	game_elapsed+=delta
	var world := target()
	if not is_instance_valid(world): status.text="Game %.3f s — no world\n%s" % [game_elapsed,feedback];return
	var info := world.info()
	status.text="Game %.3f s | Simulation %.3f s | %s\n%s\n%s" % [game_elapsed,info.get("time",0.0),"Paused" if info.get("paused",true) else "Running",feedback,world.last_error]
