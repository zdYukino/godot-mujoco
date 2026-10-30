extends MjRuntimeWorld
## Physics and visible body hierarchy share the editable author scene.
@onready var status_label: Label = $UI/Status
func _ready() -> void:
	super._ready()
	$UI.visible=false
	call_deferred("register_viewer_help")

func _physics_process(_delta: float) -> void:
	if not author_started: return
	status_label.text = "MuJoCo %s · 混沌双摆 · %.3f s" % [info().get("version", ""),info().time]

func register_viewer_help() -> void:
	if not is_instance_valid(runtime_viewer): return
	var note := Label.new(); note.text="混沌双摆"
	runtime_viewer.register_extension("pendulum","混沌双摆",note,"MuJoCo 混沌双摆；初值差异随时间放大。")
