extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = load("res://EditorCreatedScene.tscn").instantiate()
	world.start_paused=true
	root.add_child(world)
	var robot=world.get_node("Model")
	if not robot.model_rid.is_valid() or robot.state().actuator_parameters.left_elbow_joint_position.gain != 126:
		printerr("Editor-authored drive did not survive restart");quit(1);return
	if not robot.set_control("left_elbow_joint_position",.75):quit(1);return
	world.set_paused(false)
	for i in range(120):await physics_frame
	world.set_paused(true)
	var angle:float=robot.state().joints.left_elbow_joint.qpos[0]
	if abs(angle-.75)>.03:printerr("Editor scene drive failed ",angle);quit(1);return
	world.free()
	print("EDITOR_SCENE_RESTART_PASS saved kp=126, actual angle=",angle)
	quit(0)
