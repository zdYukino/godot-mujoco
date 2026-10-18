extends Camera3D
## Camera input remains active while MuJoCo simulation is paused.
var target := Vector3(0,.8,0)
var distance := 4.0
var yaw := .6
var pitch := .25
var dragging := false
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	update_pose()
func update_pose() -> void:
	position=target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	look_at(target)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT: dragging=event.pressed
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(.3,distance*.9)
		if event.pressed and event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(30,distance/ .9)
	if event is InputEventMouseMotion and dragging:
		yaw-=event.relative.x*.01
		pitch=clampf(pitch+event.relative.y*.01,-1.3,1.3)
	update_pose()
