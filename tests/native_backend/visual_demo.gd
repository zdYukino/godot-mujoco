extends Node3D
## Optional visual inspection; quantitative assertions live in acceptance.gd.
@onready var falling: RigidBody3D = $FallingBox

func _ready() -> void:
	$Camera3D.look_at(Vector3(0, 1, 0))
	print("Native visual demo backend: ", PhysicsServer3D.get_class())
	if PhysicsServer3D.get_class() != "MjPhysicsServer3D":
		push_error("Visual demo requires the MuJoCo backend; refusing silent fallback.")
		get_tree().quit(1)

func _process(_delta: float) -> void:
	$CanvasLayer/Status.text = "Backend: %s\nOrdinary RigidBody3D → StaticBody3D\nBox Y: %.4f m (rest target: 0.5 m)\nSpeed: %.4f m/s\nPress R to drop again" % [PhysicsServer3D.get_class(), falling.position.y, falling.linear_velocity.length()]

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		falling.transform = Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))
		falling.linear_velocity = Vector3.ZERO
		falling.angular_velocity = Vector3.ZERO
		falling.sleeping = false
