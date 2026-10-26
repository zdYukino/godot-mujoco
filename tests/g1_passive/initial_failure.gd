extends SceneTree
var passed:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=load("res://G1.tscn").instantiate()
	var robot=world.get_node("G1_1")
	# Save the manifest at an intentionally wrong base path: its mesh dependencies
	# do not exist there. The real immutable package is left untouched.
	ResourceSaver.save(robot.model.duplicate(true),"res://missing_g1_assets.tres")
	robot.model=ResourceLoader.load("res://missing_g1_assets.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	root.add_child(world)
	for i in 12: await physics_frame; await process_frame
	var controls=world.get_node("DisplayControls")
	check(not robot.model_rid.is_valid() and robot.last_error.contains("Missing packaged dependency"),"initial bad asset base path fails clearly")
	check(controls.robots.is_empty() and controls.robot_overlays.is_empty(),"failed initial robot never enters active render/state lists")
	check(controls.add_button.disabled and controls.add_status.text.contains(robot.last_error),"initial last_error is displayed and unsafe adding disabled")
	var time_before: float=world.info().time
	var count_before: int=world.info().objects.size()
	controls.request_add()
	var result: Dictionary=controls.add_robot(controls.robot_model)
	check(not controls.busy and not result.success and world.info().objects.size()==count_before,"UI and direct hot-add calls reject absent initial native state")
	for visual in [true,false]:
		for collision in [true,false]:
			controls.entities.set_pressed_no_signal(visual); controls.collisions.set_pressed_no_signal(collision); controls.apply_display()
	for i in 30: await physics_frame; await process_frame
	check(world.info().objects.size()==1 and controls.model.model_rid.is_valid() and world.info().time>time_before,"floor world stays usable and advances after initial robot failure")
	world.free(); await process_frame
	print("G1_INITIAL_FAILURE_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(0 if failed==0 else 1)
