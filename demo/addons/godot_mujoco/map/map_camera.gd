extends Camera3D
@export var target := Vector3.ZERO
@export var distance := 4.0
@export var yaw := .6
@export var pitch := .35
var orbit := false
var pan := false
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	update_pose()
func update_pose() -> void:
	position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	near = maxf(.00001,distance/10000); far = maxf(100,distance*100)
	look_at(target)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: orbit = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE: pan = event.pressed
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(.001,distance*.85)
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(1e8,distance/.85)
	if event is InputEventMouseMotion:
		if orbit: yaw -= event.relative.x*.008; pitch = clampf(pitch+event.relative.y*.008,-1.5,1.5)
		if pan: target += (-basis.x*event.relative.x+basis.y*event.relative.y)*distance/500
	update_pose()
