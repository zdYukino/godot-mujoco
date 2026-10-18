extends SceneTree
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func ticks(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame
func finished(robot: Node) -> void:
	for unused in 120:
		if robot.edit_request == 0: return
		await ticks(1)
	check(false,"request completes within 120 physics frames")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://RuntimeScene.tscn").instantiate()
	world.start_paused = true
	root.add_child(world)
	await ticks(2)
	var robot = world.get_node("Model")
	var second = world.get_node("SecondModel")
	var original = robot.model
	var result: Dictionary = original.open_document()
	check(result.error.is_empty(),"open design model")
	if not result.error.is_empty(): quit(1); return
	var doc: RefCounted = result.document
	check(doc.edit({"op":"set","kind":"body","name":"left_elbow_link","values":{"mass":1.2}}),"author inertial edit")
	check(doc.edit({"op":"set","kind":"joint","name":"left_elbow_joint","values":{"damping":.2,"frictionloss":.03}}),"author joint edit")
	var packed := Builder.pack(doc,"res://live_models","edited",original.provenance,original.resource_path.get_base_dir())
	check(packed.error.is_empty(),"save immutable edited design")
	if not packed.error.is_empty(): printerr(packed.error);quit(1);return
	var edited = ResourceLoader.load(packed.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	robot.set_control("left_elbow_joint_position",.7)
	var prior: Dictionary = robot.state()
	var other: Dictionary = second.state()
	var rid: RID = robot.model_rid
	var time: float = world.info().time
	check(robot.request_model_edit(edited),"request accepted without direct mutation")
	check(robot.state().bodies.left_elbow_link.mass == prior.bodies.left_elbow_link.mass,"request leaves active model unchanged before boundary")
	check(not robot.request_model_edit(edited),"repeated click rejected while pending")
	await finished(robot)
	check(robot.last_error.is_empty() and robot.property_revision==1,"commit reports revision")
	check(robot.model_rid==rid and abs(robot.state().bodies.left_elbow_link.mass-1.2)<1e-9,"same instance RID applies inertia")
	check(robot.state().joints==prior.joints and robot.state().controls==prior.controls,"paused compatible state and controls exactly preserved")
	check(world.info().paused and world.info().time==time,"paused state and clock restored")
	check(second.state().joints==other.joints and second.state().bodies==other.bodies and second.property_revision==0,"other instance isolated")
	check(robot.model.snapshot==edited.snapshot and robot.state().controls.left_elbow_joint_position==.7,"design snapshot is not overwritten by simulation")
	check(robot.request_model_edit(original,0),"stale revision request queues")
	await finished(robot)
	check(not robot.last_error.is_empty() and robot.property_revision==1 and robot.state().joints==prior.joints,"stale revision rolls back without state loss")
	var bad = edited.duplicate(true)
	bad.snapshot.xml = str(edited.snapshot.xml).replace("<worldbody>","<worldbody><body name='invalid'><joint/><geom size='-1'/></body>")
	var bad_path: String = edited.resource_path.get_base_dir().path_join("invalid-live.tres")
	check(ResourceSaver.save(bad,bad_path)==OK,"stage invalid saved candidate")
	bad = ResourceLoader.load(bad_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(robot.request_model_edit(bad),"invalid candidate queues for boundary compile")
	await finished(robot)
	check(not robot.last_error.is_empty() and robot.property_revision==1 and robot.model_rid==rid,"candidate compile failure retains original instance")
	check(robot.state().joints==prior.joints and world.info().paused,"failure preserves state and pause")
	var conflicts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://conflict-resources.json"))
	for key in conflicts:
		check(robot.request_model_edit(load(conflicts[key])),"queue conflicting options " + key)
		await finished(robot)
		check(robot.last_error.contains(key) and robot.property_revision==1 and robot.state().joints==prior.joints,"conflicting option rollback " + key)
	var incompatible = edited.duplicate(true)
	incompatible.snapshot.xml = str(edited.snapshot.xml).replace('<joint name="left_elbow_joint"','<joint type="slide" name="left_elbow_joint"')
	var incompatible_path: String = edited.resource_path.get_base_dir().path_join("incompatible-live.tres")
	check(ResourceSaver.save(incompatible,incompatible_path)==OK,"stage incompatible joint design")
	check(robot.request_model_edit(load(incompatible_path)),"queue incompatible named joint")
	await finished(robot)
	check(robot.last_error.contains("Incompatible joint type") and robot.property_revision==1 and robot.state().joints==prior.joints,"same-name joint type change rejected without state corruption")
	check(robot.request_model_edit(original),"retry after failure")
	await finished(robot)
	check(robot.last_error.is_empty() and robot.property_revision==2 and abs(robot.state().bodies.left_elbow_link.mass-.8)<1e-9,"retry restores previous design with live state")
	check(doc.edit({"op":"add","shape":"box","name":"live_extra"}),"author internal topology insertion")
	var topology_pack := Builder.pack(doc,"res://live_models","topology",original.provenance,original.resource_path.get_base_dir())
	check(topology_pack.error.is_empty(),"publish topology revision")
	check(robot.request_model_edit(load(topology_pack.path)),"queue internal topology insertion")
	await finished(robot)
	check(robot.last_error.is_empty() and robot.state().joints.size()==30 and robot.state().joints.left_elbow_joint==prior.joints.left_elbow_joint,"new free root initialized and existing joint retained")
	check(robot.request_model_edit(edited),"queue internal topology deletion")
	await finished(robot)
	check(robot.last_error.is_empty() and robot.state().joints.size()==29 and second.state().joints.size()==29,"internal topology removal keeps both robot states")
	world.set_paused(false)
	await ticks(12)
	time = world.info().time
	check(robot.request_model_edit(edited),"running edit queues")
	await finished(robot)
	check(not world.info().paused and world.info().time>=time and robot.last_error.is_empty(),"running edit resumes clock")
	world.set_paused(true)
	for cycle in range(12):
		var added = Instance.new()
		added.model = original
		added.position = Vector3(4,1.1,0)
		world.add_child(added)
		check(added.model_rid.is_valid(),"repeated instance add "+str(cycle)+": "+added.last_error)
		check(added.request_model_edit(edited),"repeated instance edit "+str(cycle))
		if cycle % 2 == 0:
			added.queue_free()
			await ticks(2)
		else:
			await finished(added)
			check(added.last_error.is_empty(),"repeated edit completes "+str(cycle))
			if cycle == 1:
				var previous_id: String = added.live_id
				added.unload_model()
				check(added.load_model() and added.live_id!=previous_id,"same node reload gets a new generation ID")
			added.queue_free()
			await ticks(2)
		check(world.info().objects.size()==2 and robot.model_rid==rid,"delete pending/completed edit preserves peers "+str(cycle))
	# Save the design reference, never export the current native qpos/velocity into it.
	var saved := PackedScene.new()
	check(saved.pack(world)==OK and ResourceSaver.save(saved,"res://LiveEditedScene.tscn")==OK,"save updated design reference")
	world.free()
	await ticks(2)
	var restarted = load("res://LiveEditedScene.tscn").instantiate()
	restarted.start_paused = true
	root.add_child(restarted)
	await ticks(2)
	check(abs(restarted.get_node("Model").state().bodies.left_elbow_link.mass-1.2)<1e-9,"restart keeps saved design revision")
	check(abs(restarted.get_node("Model").state().joints.left_elbow_joint.qpos[0]-.4)<1e-9,"restart uses authored initial pose instead of last simulation pose")
	restarted.free()
	await ticks(2)
	var failed := checks.filter(func(c):return not c.passed).size()
	print("LIVE_EDIT_RESULT ",JSON.stringify({"checks":checks,"failed":failed,"passed":checks.size()-failed}))
	quit(0 if failed==0 else 1)
