extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func ticks(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(doc.import_g1("res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf",true,true),"import explicit free-base relaxed G1")
	if not checks[-1].passed: printerr(doc.get_error());quit(1);return
	var packed: Dictionary = Builder.pack(doc,"res://models","free_g1")
	check(packed.error.is_empty(),"portable derived model preserves source assets")
	if not packed.error.is_empty(): printerr(packed.error);quit(1);return
	var resource = load(packed.path)
	var world = World.new()
	world.world_model = resource
	world.start_paused = true
	var robot = Instance.new()
	robot.model = resource
	robot.position.y = 4
	world.add_child(robot)
	root.add_child(world)
	await ticks(2)
	var initial: Dictionary = robot.state()
	check(initial.joints.floating_base.qpos.size()==7 and initial.joints.floating_base.qvel.size()==6,"free base qpos7 qvel6")
	check(initial.controls.is_empty(),"relaxed joints have no hidden position drives")
	var mass := 0.0
	var legal := true
	for body in initial.bodies.values():
		mass += body.mass
		legal = legal and body.gravcomp==0 and body.mass>=0 and body.inertia.is_finite()
	check(legal and mass>20 and mass<50,"finite physical inertia and mass, zero gravity compensation")
	var begin: float = world.info().time
	world.set_paused(false)
	await ticks(12)
	world.set_paused(true)
	await ticks(1)
	var elapsed: float = world.info().time-begin
	var after: Dictionary = robot.state()
	check(after.joints.floating_base.qpos[2]<initial.joints.floating_base.qpos[2]-.05,"root physically falls under gravity")
	check(abs(after.joints.floating_base.qvel[2]+9.8*elapsed)<.3,"root vertical velocity follows gravity")
	check(robot.global_transform.is_equal_approx(after.bodies.pelvis.transform),"Node3D follows physical pelvis rather than mesh-only motion")
	check(abs(robot.position.y-after.joints.floating_base.qpos[2])<.001,"MuJoCo Z maps to Godot Y")
	world.queue_free()
	await ticks(3)
	var failed := checks.filter(func(c):return not c.passed).size()
	print("FREEBASE_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)
