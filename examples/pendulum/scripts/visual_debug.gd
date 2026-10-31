extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false
	$MjDebugDraw.world = self
	$MjDebugDraw.set_process(false)
	$MjDebugDraw.visible=false

func _physics_process(_delta: float) -> void:
	if not author_started: return
	status_label.text = "MuJoCo %s · 接触 / 力 / 坐标系 / 关节 / 质心 · %.3f s" % [info().get("version", ""),info().time]

func get_viewer_help() -> Dictionary:
	return {"key":"pendulum","title":"可视化诊断","text":"在原版左面板 Rendering 中启用接触、力、坐标系、关节与质心诊断；Tab 开关左面板，F11 仅为 Godot 附加功能。"}
func register_extras(extras: Node) -> String:
	var note := Label.new(); note.text="可视化诊断"
	extras.add_extension("pendulum","可视化诊断",note)
	return "pendulum"
