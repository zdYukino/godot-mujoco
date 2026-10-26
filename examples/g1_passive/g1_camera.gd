extends Camera3D
## Example-only framing; no robot transforms or simulation state are changed.
var target:=Vector3(-1.8,.45,0)
var distance:=3.2
var robot_count:=1
const PITCH:=.65
func _ready() -> void:
	frame_for_count(1)
func frame_for_count(count: int) -> void:
	robot_count=clampi(count,1,2)
	target=Vector3(-1.8,.45,0) if robot_count==1 else Vector3(0,.45,0)
	distance=3.2 if robot_count==1 else 4.8
	update_pose()
func update_pose() -> void:
	var offset:=Vector3(0,sin(PITCH),cos(PITCH))*distance
	transform=Transform3D(Basis.looking_at(-offset,Vector3.UP),target+offset)
func zoom(factor: float) -> void:
	distance=clampf(distance*factor,2.0 if robot_count==1 else 4.2,9.0)
	update_pose()
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP: zoom(.9)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom(1.0/.9)
		else: return
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F and not event.ctrl_pressed and not event.alt_pressed:
		frame_for_count(robot_count)
		get_viewport().set_input_as_handled()
