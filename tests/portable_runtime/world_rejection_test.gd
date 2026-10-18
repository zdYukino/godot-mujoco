extends SceneTree
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const ERRORS := {
	"missing_model":"Assign a world_model resource to define all global MuJoCo options",
	"ownership":"Only one MjRuntimeWorld may own a World3D; use a separate SubViewport for another world"
}
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1 or not ERRORS.has(args[0]): quit(2);return
	var case: String = args[0]
	var resource = load(FileAccess.get_file_as_string("res://g1-resource-path.txt").strip_edges())
	var world = World.new()
	world.start_paused = case == "ownership"
	if case == "ownership": world.world_model=resource
	root.add_child(world)
	if case == "missing_model":
		check(not world.ready_for_models and not world.space.is_valid(),"rejected before space configuration")
		check(world.last_error==ERRORS[case],"exact structured diagnostic")
		check(not world.get_world_3d().has_meta("mj_runtime_owner"),"failed entry does not claim ownership")
		root.remove_child(world)
		world.world_model=resource
		root.add_child(world)
		check(world.ready_for_models and not world.info().paused and world.last_error.is_empty(),"corrected entry recovers original start mode")
	else:
		var robot = Instance.new();robot.model=resource;world.add_child(robot)
		check(robot.model_rid.is_valid(),"live owner fixture loaded")
		var before: Dictionary = robot.state()
		var info: Dictionary = world.info()
		var rejected = World.new();rejected.world_model=resource;rejected.start_paused=false
		root.add_child(rejected)
		check(not rejected.ready_for_models and not rejected.space.is_valid(),"second owner rejected before configuration")
		check(rejected.last_error==ERRORS[case],"exact structured diagnostic")
		check(world.get_world_3d().get_meta("mj_runtime_owner").get_ref()==world and robot.state()==before and world.info()==info,"rejection preserves owner model state revision and pause")
		root.remove_child(rejected)
		check(world.get_world_3d().get_meta("mj_runtime_owner").get_ref()==world and robot.state()==before and world.info()==info,"failed owner exit preserves live world")
		world.free()
		world=rejected
		root.add_child(world)
		check(world.ready_for_models and not world.info().paused and world.last_error.is_empty(),"conflict recovers after owner disposal")
	var recovered = Instance.new();recovered.model=resource;world.add_child(recovered)
	check(recovered.model_rid.is_valid() and recovered.state().joints.size()==29,"recovered world loads complete robot")
	world.free()
	await process_frame
	check(not root.get_world_3d().has_meta("mj_runtime_owner"),"cleanup releases ownership")
	var failed := checks.filter(func(c):return not c.passed).size()
	print("WORLD_REJECTION_RESULT ",JSON.stringify({"case":case,"checks":checks,"failed":failed}))
	quit(0 if failed==0 else 1)
