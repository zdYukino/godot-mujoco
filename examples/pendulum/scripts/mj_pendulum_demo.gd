extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()

func _physics_process(_delta: float) -> void:
	if not author_started: return
	$Model.set_control("hinge_motor", .25 * sin(float(info().time) * 2.0))
	status_label.text = "MuJoCo %s · 单摆 · %.3f s" % [info().get("version", ""),info().time]
