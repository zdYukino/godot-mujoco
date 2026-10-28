extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$MjDebugDraw.world = self

func _physics_process(_delta: float) -> void:
	if not author_started: return
	status_label.text = "MuJoCo %s · 接触 / 力 / 坐标系 / 关节 / 质心 · %.3f s" % [info().get("version", ""),info().time]
