extends SceneTree
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func _initialize() -> void: call_deferred("run")
func settled(world: Node) -> bool:
	var until := Time.get_ticks_msec()+120000
	await process_frame;await process_frame
	while Time.get_ticks_msec()<until:
		if world.info().get("compile_status") == "failed": return false
		if world.author_started and world.info().get("compile_status")=="ready" and world.command_request==0:return true
		await process_frame
	return false
func run() -> void:
	var world: Node = load("res://RuntimeScene.tscn").instantiate();world.start_paused=true;root.add_child(world)
	check(await settled(world),"saved author world compiles asynchronously")
	var robot: Node=world.get_node("Model");var second: Node=world.get_node("SecondModel")
	var obstacle: RigidBody3D=world.get_node("Obstacle")
	check(robot.model_rid.is_valid() and second.model_rid.is_valid() and robot.model_rid!=second.model_rid,"independent instance RIDs")
	check(robot.space==obstacle.get_world_3d().space and robot.space==second.space,"ordinary bodies and author models share one space")
	check(robot.state().joints.size()==29 and absf(robot.state().joints.left_elbow_joint.qpos[0]-.4)<1e-8,"G1 authored joints and initial angle survive save/reload")
	check(absf(robot.state().bodies.left_elbow_link.mass-.8)<1e-8,"authored mass retained")
	var gains: Dictionary=robot.state().actuator_parameters.left_elbow_joint_position
	check(gains.gain==120 and gains.velocity_bias==-12,"authored PD gains retained")
	check(robot.set_control("left_elbow_joint_position",.8) and second.state().controls.left_elbow_joint_position==.4,"controls and initial targets are independent")
	var contact := false
	check(world.set_paused(false),"valid compiled world can run")
	for frame in 240:
		await physics_frame;await process_frame
		for pair in world.info().contacts:
			if pair.has(robot.model_rid) and pair.has(obstacle.get_rid()):contact=true
	world.set_paused(true)
	check(contact and world.info().warning_count==0,"model and ordinary body have real stable contact")
	check(absf(robot.state().joints.left_elbow_joint.qpos[0]-.8)<.03 and absf(second.state().joints.left_elbow_joint.qpos[0]-.4)<.03,"both joint targets track independently")
	var before: Dictionary=robot.state()
	var added := Instance.new();added.name="RuntimeAddition";added.design=robot.design;added.position=Vector3(-2,1.1,0);world.add_child(added)
	check(await settled(world),"runtime author addition compiles")
	check(robot.state().joints==before.joints and robot.state().controls==before.controls,"addition preserves compatible live state")
	var stale: RID=added.model_rid;added.queue_free()
	check(await settled(world) and PhysicsServer3D.call("scene_state",world.space,stale).is_empty(),"removal retires the instance handle at commit")
	var conflicts: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://conflict-resources.json"))
	for key in conflicts:
		var rejected := Instance.new();rejected.design=load(conflicts[key]);world.add_child(rejected)
		check(not await settled(world) and world.info().last_error.contains(key),"non-overridden global option conflicts: "+str(key))
		check(robot.state().joints==before.joints and not world.set_paused(false),"failure preserves and pauses the last valid world")
		rejected.queue_free();check(await settled(world),"removing conflicting source recovers")
	world.queue_free();await process_frame;await process_frame
	var multi: Resource=load(FileAccess.get_file_as_string("res://multi-resource-path.txt"))
	var other := World.new();other.world_design=multi.fork();other.start_paused=true
	var instance := Instance.new();instance.design=multi;other.add_child(instance);root.add_child(other)
	check(await settled(other),"two-free-root source compiles")
	check(instance.state().joints.size()==2 and PhysicsServer3D.call("scene_geometry",other.space,instance.model_rid).size()==3,"both free roots and world geom retained")
	var previous: RID=instance.model_rid
	root.remove_child(other);root.add_child(other)
	check(await settled(other) and instance.model_rid!=previous,"same-node world reentry creates a fresh native lifetime")
	other.queue_free();await process_frame;await process_frame
	var failed:=checks.filter(func(item):return not item.passed).size()
	print("RUNTIME_RESULT ",JSON.stringify({"checks":checks,"failed":failed,"passed":checks.size()-failed}));quit(0 if failed==0 else 1)
