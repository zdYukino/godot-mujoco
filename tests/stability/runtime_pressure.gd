extends SceneTree
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
var checks := 0
var failures := []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr("FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world=load("res://RuntimeScene.tscn").instantiate()
	world.start_paused=true;root.add_child(world)
	var robot=world.get_node("Model")
	var second=world.get_node("SecondModel")
	check(robot.model_rid.is_valid() and second.model_rid.is_valid(),"initial models loaded")
	if not robot.model_rid.is_valid():quit(1);return
	var resource=robot.model
	var relative:String=resource.dependencies.keys()[0]
	var path:String=resource.resource_path.get_base_dir().path_join(relative)
	for cycle in range(30):
		var target:=.45+.1*float(cycle%4)
		check(robot.set_control("left_elbow_joint_position",target),"control "+str(cycle))
		world.set_paused(false)
		for frame in range(8):await physics_frame
		world.set_paused(true)
		var before:Dictionary=robot.state()
		var other_before:Dictionary=second.state()
		var revision:int=world.info().revision
		check(DirAccess.rename_absolute(path,path+".temporarily_missing")==OK,"hide dependency "+str(cycle))
		var missing=Instance.new();missing.model=resource;world.add_child(missing)
		check(not missing.model_rid.is_valid() and missing.last_error.contains("Missing"),"missing dependency refused "+str(cycle))
		check(robot.state()==before and second.state()==other_before and world.info().revision==revision,"rejection preserves world "+str(cycle))
		check(DirAccess.rename_absolute(path+".temporarily_missing",path)==OK,"restore dependency "+str(cycle))
		missing.position=Vector3(-2,1.1,0)
		check(missing.load_model(),"same failed instance recovers "+str(cycle))
		check(robot.state().joints==before.joints and robot.state().controls==before.controls,"insertion preserves state "+str(cycle))
		check(second.state().joints==other_before.joints and second.state().controls==other_before.controls,"second model independent "+str(cycle))
		var removed:RID=missing.model_rid
		missing.free()
		check(PhysicsServer3D.call("scene_state",world.space,removed).is_empty(),"removed RID absent "+str(cycle))
		check(robot.state().joints==before.joints and robot.state().controls==before.controls,"removal preserves state "+str(cycle))
		check(world.info().warning_count==0,"no MuJoCo warnings "+str(cycle))
		if cycle%3==2:
			var basis:Basis=world.get_node("Obstacle").basis
			check((basis.get_scale()-Vector3.ONE).length()<.000002 and abs(basis.determinant()-1.0)<.000002,"ordinary rigid body stays unscaled "+str(cycle))
			var old:RID=robot.model_rid
			root.remove_child(world)
			await process_frame
			root.add_child(world)
			check(world.ready_for_models and world.info().paused,"world reentry configured "+str(cycle))
			check(robot.model_rid.is_valid() and robot.model_rid!=old,"fresh instance RID on reentry "+str(cycle))
			check(abs(robot.state().joints.left_elbow_joint.qpos[0]-.4)<1e-8,"reentry restores authored state "+str(cycle))
	world.free()
	await process_frame
	print("PRESSURE_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"topology_cycles":30,"world_reentries":10}))
	quit(0 if failures.is_empty() else 1)
