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
	var low: Dictionary = await contact_trial(doc,0.001,false)
	var high: Dictionary = await contact_trial(doc,1.0,false)
	check(low.travel > high.travel + .05,"G1 low friction slides further than high friction: " + str([low.travel,high.travel]))
	await contact_trial(doc,.001,true)
	var failed := checks.filter(func(c):return not c.passed).size()
	print("FREEBASE_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)

func add_box(world: Node, size: Vector3, position: Vector3, friction: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position=position
	body.collision_layer=1
	body.collision_mask=3
	var material := PhysicsMaterial.new()
	material.friction=friction
	body.physics_material_override=material
	var shape := BoxShape3D.new()
	shape.size=size
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	world.add_child(body)
	return body

func contact_trial(source: RefCounted, friction: float, obstacle: bool) -> Dictionary:
	var candidate: Dictionary = source.snapshot().duplicate(true)
	var regex := RegEx.new()
	regex.compile(' friction="[^"]*"')
	candidate.xml=regex.sub(candidate.xml,"",true).replace("<worldbody>",'<default><geom friction="%s .005 .0001"/></default><worldbody>' % friction)
	candidate.state.erase("integration")
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(doc.restore(candidate),"derive friction fixture without changing upstream")
	var collisions := {}
	for entity in doc.inspect().entities:
		if entity.kind=="geom" and entity.properties.contype!=0: collisions[entity.name]=entity.parent
	var lowest := INF
	for geom in doc.geometry():
		if collisions.get(geom.name,"").contains("ankle_roll") and geom.type==2:
			lowest=minf(lowest,geom.transform.origin.y-geom.size.x)
	check(is_finite(lowest),"locate original G1 sole collision spheres")
	candidate=doc.snapshot()
	candidate.state.erase("integration")
	candidate.state.qpos[2]=.001-lowest
	candidate.state.qvel[0]=1.5
	check(doc.restore(candidate),"author sole height and initial horizontal velocity")
	var package: Dictionary = Builder.pack(doc,"res://models","contact")
	check(package.error.is_empty(),"pack friction contact trial")
	var resource=load(package.path)
	var world=World.new()
	world.world_model=resource
	world.start_paused=true
	var robot=Instance.new()
	robot.model=resource
	world.add_child(robot)
	add_box(world,Vector3(20,.1,20),Vector3(0,-.05,0),friction)
	var barrier: StaticBody3D
	if obstacle: barrier=add_box(world,Vector3(.1,2,4),Vector3(.55,1,0),friction)
	root.add_child(world)
	await ticks(2)
	var start: float=robot.state().joints.floating_base.qpos[0]
	var sole_contact := false
	var obstacle_contact := false
	var finite := true
	var depth := 0.0
	world.set_paused(false)
	for frame in 120:
		await ticks(1)
		var state: Dictionary=robot.state()
		for joint in state.joints.values():
			for value in joint.qpos: finite=finite and is_finite(value)
			for value in joint.qvel: finite=finite and is_finite(value)
		for contact in world.info().contact_details:
			depth=minf(depth,contact.distance)
			if frame<15:
				for body in contact.bodies:
					if body.contains("ankle_roll"): sole_contact=true
		if obstacle:
			for pair in world.info().contacts:
				if pair.has(barrier.get_rid()) and pair.has(robot.model_rid): obstacle_contact=true
	world.set_paused(true)
	var travel: float=robot.state().joints.floating_base.qpos[0]-start
	check(sole_contact,"initial soles establish physical ground contact " + str(friction))
	check(finite and world.info().warning_count==0,"finite G1 contact simulation without MuJoCo warnings")
	check(depth>-.04,"contact penetration under 4 cm bound: " + str(depth))
	if obstacle: check(obstacle_contact,"G1 collides with ordinary Godot obstacle")
	world.queue_free()
	await ticks(3)
	return {"travel":travel,"deepest_contact":depth}
