extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false

func _physics_process(_delta: float) -> void:
	if not author_started: return
	$Model.set_control("hinge_motor", .25 * sin(float(info().time) * 2.0))
	status_label.text = "MuJoCo %s · 单摆 · %.3f s" % [info().get("version", ""),info().time]

func get_viewer_help() -> Dictionary:
	return {"key":"pendulum","title":"单摆","text":"MuJoCo 单摆与周期驱动。"}
func register_extras(extras: Node) -> String:
	var note := Label.new(); note.text="单摆"
	extras.add_extension("pendulum","单摆",note)
	return "pendulum"
