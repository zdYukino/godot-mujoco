extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
var checks := []
var contact_trials := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func ticks(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame
func committed(world: Node,robot: Node) -> bool:
	var deadline := Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		var info: Dictionary=world.info()
		var state: Dictionary=robot.state()
		if world.author_started and not info.get("design_pending",true) and state.get("joints",{}).has("floating_base"):return true
		if info.get("compile_status","")=="failed":break
		await ticks(1)
	check(false,"free-base composition commits before reading model state: "+str(world.info()))
	return false
func finish() -> void:
	var failed := checks.filter(func(c):return not c.passed).size()
	print("FREEBASE_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	FileAccess.open("res://freebase-contact-trials.json",FileAccess.WRITE).store_string(JSON.stringify(contact_trials,"  "))
	quit(0 if failed==0 else 1)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(doc.import_g1("res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf",true,true),"import explicit free-base relaxed G1")
	if not checks[-1].passed: printerr(doc.get_error());quit(1);return
	var packed: Dictionary = await Builder.save_document(doc,"res://models","free_g1")
	check(packed.error.is_empty(),"portable derived model preserves source assets")
	if not packed.error.is_empty(): printerr(packed.error);quit(1);return
	var resource = load(packed.path)
	var world = World.new()
	world.world_design = resource
	world.start_paused = true
	var robot = Instance.new()
	robot.design = resource
	robot.position.y = 4
	world.add_child(robot)
	root.add_child(world)
	if not await committed(world,robot):finish();return
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
	var pelvis: Node3D
	for entity in robot.design.entities():
		if entity.kind=="body" and entity.name=="pelvis":pelvis=robot.author_scene.nodes.get(entity.id)
	check(is_instance_valid(pelvis) and pelvis.global_transform.is_equal_approx(after.bodies.pelvis.transform),"authored body Node3D follows the physical pelvis")
	check(is_instance_valid(pelvis) and abs(pelvis.global_position.y-after.joints.floating_base.qpos[2])<.001,"MuJoCo Z maps to authored body Godot Y")
	check(robot.position.is_equal_approx(Vector3(0,4,0)),"model container keeps its authored placement while body nodes move")
	for trial in 3:
		robot.unload_model()
		check(robot.position.is_equal_approx(Vector3(0,4,0)),"free-root unload restores authored placement")
		check(robot.load_model(),"same free-root instance reloads")
		if not await committed(world,robot):finish();return
		check(robot.state().joints.floating_base.qpos==initial.joints.floating_base.qpos,"free-root reload does not compound physical pose")
		world.remove_child(robot)
		world.add_child(robot)
		if not await committed(world,robot):finish();return
		check(robot.state().joints.floating_base.qpos==initial.joints.floating_base.qpos,"same free-root node reentry preserves authored placement")
	world.queue_free()
	await ticks(3)
	var low: Dictionary = await contact_trial(doc,0.001,false)
	var high: Dictionary = await contact_trial(doc,1.0,false)
	check(absf(low.elapsed-high.elapsed)<.02,"friction fixtures use the same committed integration window")
	check(low.sole_friction_max<high.sole_friction_min,"distinct authored friction reaches the actual G1 sole-ground solver contacts")
	await contact_trial(doc,.001,true)
	finish()

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

func model_center_of_mass(state: Dictionary) -> Vector3:
	var total := 0.0
	var weighted := Vector3.ZERO
	for body in state.bodies.values():
		total+=body.mass
		weighted+=body.center_of_mass*body.mass
	return weighted/total

func contact_trial(source: RefCounted, friction: float, obstacle: bool) -> Dictionary:
	var candidate: Dictionary = source.snapshot().duplicate(true)
	var regex := RegEx.new()
	regex.compile(' friction="[^"]*"')
	candidate.xml=regex.sub(candidate.xml,"",true).replace("<worldbody>",'<default><geom friction="%s .005 .0001"/></default><worldbody>' % friction)
	# Author resources persist design poses/controls, not transient qvel. Apply
	# the same saved horizontal gravity to both trials rather than assuming an
	# editor-document velocity survives portable design conversion.
	var fixture: Resource=Author.from_xml(candidate.xml).design
	var option := Xml.section(fixture.tree,"option")
	if option.is_empty():
		option={"tag":"option","attrs":{},"children":[]}
		fixture.tree.children.push_front(option)
	option.attrs.gravity="2 0 -9.8"
	candidate.xml=fixture.xml()
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
	check(doc.restore(candidate),"author sole height with a shared horizontal gravity stimulus")
	var package: Dictionary = await Builder.save_document(doc,"res://models","contact")
	check(package.error.is_empty(),"pack friction contact trial")
	var resource=load(package.path)
	var world=World.new()
	world.world_design=resource
	world.start_paused=true
	var robot=Instance.new()
	robot.design=resource
	world.add_child(robot)
	var ground := add_box(world,Vector3(20,.1,20),Vector3(0,-.05,0),friction)
	var barrier: StaticBody3D
	if obstacle: barrier=add_box(world,Vector3(.1,2,4),Vector3(.55,1,0),friction)
	root.add_child(world)
	if not await committed(world,robot):
		world.queue_free()
		await ticks(3)
		return {"travel":0.0,"deepest_contact":0.0,"elapsed":0.0,"sole_friction_min":0.0,"sole_friction_max":0.0}
	var start: float=model_center_of_mass(robot.state()).x
	var pelvis_start: float=robot.state().joints.floating_base.qpos[0]
	var initial_velocity: PackedFloat64Array=robot.state().joints.floating_base.qvel
	check(initial_velocity==PackedFloat64Array([0,0,0,0,0,0]),"friction fixture starts with the actual zero free-base velocity")
	var start_time: float=world.info().time
	var sole_contact := false
	var obstacle_contact := false
	var finite := true
	var depth := 0.0
	var sole_friction_min := INF
	var sole_friction_max := -INF
	var trajectory := []
	world.set_paused(false)
	# Compare friction during the initial 0.5 s of sole contact. The separate
	# obstacle trial retains its full 120-frame collision/stability window.
	for frame in (120 if obstacle else 30):
		await ticks(1)
		var state: Dictionary=robot.state()
		var info: Dictionary=world.info()
		var center := model_center_of_mass(state)
		trajectory.append({"time":info.time,"center_of_mass":[center.x,center.y,center.z],"pelvis_x":state.joints.floating_base.qpos[0]})
		for joint in state.joints.values():
			for value in joint.qpos: finite=finite and is_finite(value)
			for value in joint.qvel: finite=finite and is_finite(value)
		for index in info.contact_details.size():
			var contact: Dictionary=info.contact_details[index]
			var pair: Array=info.contacts[index]
			depth=minf(depth,contact.distance)
			if pair.has(ground.get_rid()) and pair.has(robot.model_rid):
				for body in contact.bodies:
					if body.contains("ankle_roll"):
						if frame<15:sole_contact=true
						sole_friction_min=minf(sole_friction_min,contact.friction)
						sole_friction_max=maxf(sole_friction_max,contact.friction)
		if obstacle:
			for pair in world.info().contacts:
				if pair.has(barrier.get_rid()) and pair.has(robot.model_rid): obstacle_contact=true
	world.set_paused(true)
	var travel: float=model_center_of_mass(robot.state()).x-start
	var pelvis_travel: float=robot.state().joints.floating_base.qpos[0]-pelvis_start
	var elapsed: float=world.info().time-start_time
	check(sole_contact,"initial soles establish physical ground contact " + str(friction))
	check(is_equal_approx(sole_friction_min,friction) and is_equal_approx(sole_friction_max,friction),"actual G1 sole-ground solver friction matches the authored material "+str(friction))
	check(finite and world.info().warning_count==0,"finite G1 contact simulation without MuJoCo warnings")
	check(depth>-.04,"contact penetration under 4 cm bound: " + str(depth))
	if obstacle: check(obstacle_contact,"G1 collides with ordinary Godot obstacle")
	# Passive articulated tipping does not imply monotonic horizontal travel as
	# friction changes. Retain trajectories and assert real contact coefficients.
	contact_trials.append({"friction":friction,"gravity_m_s2":[2,0,-9.8],"initial_qvel":Array(initial_velocity),"elapsed":elapsed,"travel":travel,"travel_measurement":"model-only mass-weighted center of mass","pelvis_travel":pelvis_travel,"deepest_contact":depth,"obstacle":obstacle,"sole_friction_min":sole_friction_min,"sole_friction_max":sole_friction_max,"trajectory":trajectory})
	world.queue_free()
	await ticks(3)
	return {"travel":travel,"deepest_contact":depth,"elapsed":elapsed,"sole_friction_min":sole_friction_min,"sole_friction_max":sole_friction_max}
