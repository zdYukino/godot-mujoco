extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false

func _physics_process(_delta: float) -> void:
	if not author_started: return
	status_label.text = "MuJoCo %s · 混沌双摆 · %.3f s" % [info().get("version", ""),info().time]

func get_viewer_help() -> Dictionary:
	return {"key":"pendulum","title":"混沌双摆","text":"MuJoCo 混沌双摆；初值差异随时间放大。"}
func register_extras(extras: Node) -> String:
	var note := Label.new(); note.text="混沌双摆"
	extras.add_extension("pendulum","混沌双摆",note)
	return "pendulum"
