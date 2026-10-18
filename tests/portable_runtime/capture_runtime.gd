extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world = load("res://RuntimeScene.tscn").instantiate()
	root.add_child(world)
	var canvas := CanvasLayer.new()
	world.add_child(canvas)
	var label := Label.new()
	label.position=Vector2(24,24)
	label.add_theme_font_size_override("font_size",24)
	canvas.add_child(label)
	var robot = world.get_node("Model")
	robot.set_control("left_elbow_joint_position",.8)
	for i in range(180): await physics_frame
	world.set_paused(true)
	label.text="Saved project scene · two independent G1 instances\nShared MuJoCo space · native rigid obstacle + floor\nLeft elbow target 0.80 / actual %.3f rad" % robot.state().joints.left_elbow_joint.qpos[0]
	await process_frame
	await RenderingServer.frame_post_draw
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			var result = root.get_texture().get_image().save_png(arg.trim_prefix("--capture="))
			if result != OK: quit(1);return
	world.free()
	print("RUNTIME_CAPTURE_PASS")
	quit(0)
