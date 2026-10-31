extends Camera3D
## A real gameplay camera, deliberately independent of the viewer component.
var ticks := 0
var keypresses := 0
var elapsed := 0.0
var base_position := Vector3.ZERO
func _ready() -> void:
	base_position=position
func _process(delta: float) -> void:
	if not is_current(): return
	elapsed+=delta; ticks+=1
	position=base_position+Vector3(.7*sin(elapsed*2.),0,0)
	if projection==PROJECTION_PERSPECTIVE: fov=48.+5.*sin(elapsed)
func _input(event: InputEvent) -> void:
	if is_current() and event is InputEventKey and event.pressed: keypresses+=1
