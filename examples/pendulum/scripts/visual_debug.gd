extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false
	call_deferred("register_viewer_help")
	$MjDebugDraw.world = self
	$MjDebugDraw.set_process(false)
	$MjDebugDraw.visible=false

func _physics_process(_delta: float) -> void:
	if not author_started: return
	status_label.text = "MuJoCo %s · 接触 / 力 / 坐标系 / 关节 / 质心 · %.3f s" % [info().get("version", ""),info().time]

func register_viewer_help() -> void:
	if not is_instance_valid(runtime_viewer): return
	var note := Label.new(); note.text="可视化诊断"
	runtime_viewer.register_extension("pendulum","可视化诊断",note,"在原版左面板 Rendering 中启用接触、力、坐标系、关节与质心诊断；Tab 开关左面板，F11 仅为 Godot 附加功能。")
