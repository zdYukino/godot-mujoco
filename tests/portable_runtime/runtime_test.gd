extends SceneTree
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var packed: PackedScene = load("res://RuntimeScene.tscn")
	var world = packed.instantiate()
	world.start_paused = true
	root.add_child(world)
	await process_frame
	var robot = world.get_node("Model")
	var second = world.get_node("SecondModel")
	var obstacle: RigidBody3D = world.get_node("Obstacle")
	check(world.ready_for_models,"configured runtime world")
	check(robot.model_rid.is_valid() and second.model_rid.is_valid(),"saved scene loads two instances")
	if not robot.model_rid.is_valid():printerr(robot.last_error);quit(1);return
	check(robot.space==obstacle.get_world_3d().space and robot.space==second.space,"ordinary bodies and models share space")
	check(robot.model_rid != second.model_rid,"independent model RIDs")
	check(robot.state().joints.size()==29,"G1 29 authored joints")
	check(abs(robot.state().joints.left_elbow_joint.qpos[0]-.4)<1e-8,"authored angle retained")
	check(abs(robot.state().bodies.left_elbow_link.mass-.8)<1e-8,"authored body mass retained")
	var gains: Dictionary = robot.state().actuator_parameters.left_elbow_joint_position
	check(gains.gain==120 and gains.position_bias==-120 and gains.velocity_bias==-12,"PD writes in compiled shared model")
	check(robot.set_control("left_elbow_joint_position",.8),"GDScript control entry")
	check(second.state().controls.left_elbow_joint_position==.4,"controls not shared")
	var contact := false
	world.set_paused(false)
	for i in range(240):
		await physics_frame
		for pair in world.info().contacts:
			if pair.has(robot.model_rid) and pair.has(obstacle.get_rid()):contact=true
	world.set_paused(true)
	check(contact,"real model and ordinary RigidBody contact")
	check(world.info().warning_count==0,"finite shared simulation without MuJoCo warnings")
	check(abs(robot.state().joints.left_elbow_joint.qpos[0]-.8)<.03,"controlled joint actually moves")
	check(abs(second.state().joints.left_elbow_joint.qpos[0]-.4)<.03,"second joint independent")
	check(is_equal_approx(world.info().options.timestep,.002),"authored timestep retained")
	var before: Dictionary = robot.state()
	var duplicate = Instance.new();duplicate.name="SameModel";duplicate.model=robot.model;duplicate.position.x=-2
	world.add_child(duplicate)
	check(duplicate.model_rid.is_valid(),"third instance loads")
	check(robot.state().joints==before.joints and robot.state().controls==before.controls,"insertion preserves compatible state")
	var stale: RID = duplicate.model_rid
	duplicate.free()
	check(PhysicsServer3D.call("scene_state",world.space,stale).is_empty(),"destruction frees model RID")
	var multi = load(FileAccess.get_file_as_string("res://multi-resource-path.txt"))
	var incompatible = Instance.new();incompatible.model=multi;world.add_child(incompatible)
	check(not incompatible.model_rid.is_valid() and incompatible.last_error.contains("conflict"),"global option conflict rejected")
	check(robot.state().joints==before.joints,"failed composition preserves existing state")
	incompatible.free()
	var conflicts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://conflict-resources.json"))
	for key in conflicts:
		var rejected = Instance.new();rejected.model=load(conflicts[key]);world.add_child(rejected)
		check(not rejected.model_rid.is_valid() and rejected.last_error.contains(key), "explicit option conflict " + key)
		rejected.free()
	var original_model = robot.model
	robot.model = multi
	check(robot.model == original_model and robot.model_rid.is_valid(),"active resource replacement has explicit boundary")
	var released = Instance.new();released.model=original_model;released.position.x=-2;world.add_child(released)
	var callback_rid: RID = released.model_rid
	var weak_instance = weakref(released)
	PhysicsServer3D.body_set_state_sync_callback(obstacle.get_rid(),func(_state):
		var target = weak_instance.get_ref()
		if target: target.free())
	world.set_paused(false)
	await physics_frame
	await physics_frame
	world.set_paused(true)
	PhysicsServer3D.body_set_state_sync_callback(obstacle.get_rid(),Callable())
	check(PhysicsServer3D.call("scene_state",world.space,callback_rid).is_empty(),"instance release deferred safely from physics callback")
	var model_resource = robot.model
	world.free()
	await process_frame
	var other = World.new();other.world_model=multi;other.start_paused=true
	var instance = Instance.new();instance.model=multi;other.add_child(instance)
	root.add_child(other)
	check(instance.model_rid.is_valid(),"multi-root model accepted")
	if not instance.model_rid.is_valid(): printerr(instance.last_error);quit(1);return
	check(instance.state().joints.size()==2,"both free roots retained")
	check(PhysicsServer3D.call("scene_geometry",other.space,instance.model_rid).size()==3,"world geometry and both roots retained")
	other.free()
	await process_frame
	var again = World.new();again.world_model=model_resource;again.start_paused=true
	root.add_child(again)
	check(again.ready_for_models,"world lifecycle can reconfigure after disposal")
	again.free()
	var failed := 0
	for c in checks:if not c.passed:failed+=1
	print("RUNTIME_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed,"checks":checks}))
	quit(0 if failed==0 else 1)
