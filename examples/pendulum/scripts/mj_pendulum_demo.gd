extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false
	call_deferred("register_viewer_help")

func _physics_process(_delta: float) -> void:
	if not author_started: return
	$Model.set_control("hinge_motor", .25 * sin(float(info().time) * 2.0))
	status_label.text = "MuJoCo %s · 单摆 · %.3f s" % [info().get("version", ""),info().time]

func register_viewer_help() -> void:
	if not is_instance_valid(runtime_viewer): return
	var note := Label.new(); note.text="单摆"
	runtime_viewer.register_extension("pendulum","单摆",note,"MuJoCo 单摆与周期驱动。")
