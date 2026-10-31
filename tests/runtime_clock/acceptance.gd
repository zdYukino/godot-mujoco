extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Host = preload("res://addons/godot_mujoco/model/environment_host.gd")
const Viewer = preload("res://addons/godot_mujoco/viewer/runtime_viewer.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func ticks(n: int) -> void:
	for unused in n:
		await physics_frame
		await process_frame
func host_ready(host: Node) -> void:
	var deadline := Time.get_ticks_msec()+125000
	while host.rebuilding and Time.get_ticks_msec()<deadline: await process_frame
	check(not host.rebuilding and host.last_error.is_empty(), "environment composition completed: " + host.last_error)
func world_ready(world: Node) -> void:
	var deadline := Time.get_ticks_msec()+125000
	await ticks(2)
	while world.info().get("compile_status") not in ["ready","failed"] and Time.get_ticks_msec()<deadline: await process_frame
	check(world.info().get("compile_status")=="ready", "world compile completed")
func done(world: Node) -> void:
	for unused in 120:
		if world.command_request==0: return
		await ticks(1)
	check(false,"simulation command completes within 120 frames")
func call_command(world: Node, method: String, argument: Variant = null) -> void:
	check(world.call(method) if argument==null else world.call(method,argument),"accept " + method)
	await done(world)
	check(world.last_error.is_empty(),"complete " + method + ": " + world.last_error)
func instance(resource: Resource, name: String, position: Vector3) -> Node:
	var node=Instance.new();node.design=resource;node.name=name;node.position=position;return node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":root.size=Vector2i(1100,760)
	var file:=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
	file.store_string('<mujoco><option timestep=".002"/><worldbody><body name="ball" pos="0 0 2"><freejoint name="root"/><geom name="ball_geom" type="sphere" size=".2" mass="2"/></body><body name="arm" pos="1 0 2"><joint name="hinge" range="-1 1"/><geom type="capsule" size=".1 .3" mass="1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="10"/><general name="filtered" joint="hinge" dyntype="filter" dynprm=".1"/></actuator></mujoco>')
	file.close()
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file("res://fixture.xml"),"create clock fixture")
	var package: Dictionary=await Builder.save_document(doc,"res://models","clock")
	check(package.error.is_empty(),"save clock design")
	var resource=load(package.path)
	var environment=World.new();environment.name="Environment";environment.world_design=resource.fork();environment.start_paused=true
	var robot=instance(resource,"Robot",Vector3.ZERO);environment.add_child(robot);robot.owner=environment
	var body:=RigidBody3D.new();body.name="Ordinary";body.position=Vector3(3,3,0)
	var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.2;shape.shape=sphere
	body.add_child(shape);environment.add_child(body);body.owner=environment;shape.owner=environment
	var scene:=PackedScene.new();check(scene.pack(environment)==OK and ResourceSaver.save(scene,"res://Environment.tscn")==OK,"save authored environment")
	environment.free()
	var host=Host.new();host.environment_scene=load("res://Environment.tscn");root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await host_ready(host)
	var world=host.world
	check(is_instance_valid(world) and world.ready_for_models,"host configures independent world")
	if not is_instance_valid(world): quit(1);return
	await done(world)
	robot=world.get_node("Robot");body=world.get_node("Ordinary")
	var controls=Viewer.new();controls.environment_host=host;root.add_child(controls)
	var extras=preload("res://addons/godot_mujoco/viewer/godot_extras.gd").new();extras.environment_host=host;root.add_child(extras)
	var component_id: int=controls.get_instance_id()
	for unused in 5: await process_frame
	var start: Dictionary=robot.state()
	var time: float=world.info().time
	var game: float=world.game_elapsed
	await ticks(10)
	check(world.info().time==time and world.game_elapsed>game,"UI game clock advances while simulation stays paused")
	for n in [1,5,1,10]:
		time=world.info().time
		await call_command(world,"step_simulation",n)
		check(abs(world.info().time-time-n*.002)<1e-10 and world.info().paused,"exact N native steps while remaining paused")
	check(world.step_simulation(0),"invalid step is queued for boundary validation")
	await done(world)
	check(not world.last_command_result.success and world.info().paused,"invalid step rolls back")
	for trial in 3:
		await call_command(world,"request_pause",false)
		await ticks(3)
		await call_command(world,"request_pause",true)
		var paused_time: float=world.info().time
		await ticks(5)
		check(world.info().time==paused_time,"repeated pause freezes simulation")
		check(world.reset_simulation(),"request reset")
		check(not world.reset_simulation(),"repeated reset while pending rejected")
		await done(world)
		await ticks(1)
		check(world.info().time==0 and robot.state().joints.root==start.joints.root,"reset restores time qpos qvel")
		check(body.position.is_equal_approx(Vector3(3,3,0)) and body.linear_velocity.is_zero_approx(),"reset synchronizes ordinary Godot body cache")
	robot.set_control("drive",.5)
	robot.set_control("filtered",1.0)
	body.constant_force=Vector3(100,0,0)
	await call_command(world,"step_simulation",3)
	check(robot.state().actuator_parameters.filtered.activation[0]>0,"filtered actuator stores dynamic activation")
	await call_command(world,"reset_simulation")
	await ticks(1)
	check(robot.state().actuator_parameters.filtered.activation[0]==0 and world.info().applied_force_norm==0 and world.info().warmstart_norm==0,"reset clears activation forces and warm-start history")
	check(robot.state().controls.drive==start.controls.drive and body.constant_force==Vector3.ZERO,"reset restores controls and clears ordinary constant force")
	for trial in 3:
		var added=instance(resource,"Added",Vector3(5,0,0));world.add_child(added)
		await world_ready(world)
		await call_command(world,"step_simulation",2)
		await call_command(world,"reset_simulation")
		check(is_instance_valid(added) and added.model_rid.is_valid() and added.state().joints.root.qvel==PackedFloat64Array([0,0,0,0,0,0]),"reset retains and initializes runtime addition")
		added.queue_free();await world_ready(world)
	# Exercise the same source staging transaction used by the connected author editor.
	var geom_id := ""
	for entity in robot.design.entities():
		if entity.kind=="geom" and entity.name=="ball_geom": geom_id=entity.id
	var command := preload("res://addons/godot_mujoco/model/author_commands.gd").execute(robot.design,{"op":"set","id":geom_id,"values":{"mass":3.0}})
	check(command.get("error", "").is_empty(),"author mass edit while paused")
	var paused_time: float=world.info().time
	robot.design.restore_author(command.after)
	PhysicsServer3D.call("scene_stage_author_model",world.space,robot.model_rid,robot.author_definition())
	await world_ready(world)
	check(robot.state().bodies.ball.mass==3 and world.info().time==paused_time,"paused source transaction preserves simulation clock")
	await call_command(world,"reset_simulation")
	check(robot.state().bodies.ball.mass==3,"state reset keeps committed design changes")
	var second_host=Host.new();second_host.environment_scene=load("res://Environment.tscn");root.add_child(second_host);second_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await host_ready(second_host);await done(second_host.world)
	await call_command(world,"step_simulation",7)
	check(second_host.world.info().time==0,"independent World3D clock remains unchanged")
	await call_command(world,"capture_snapshot")
	time=world.info().time
	await call_command(world,"step_simulation",2)
	await call_command(world,"reset_simulation")
	check(world.info().time==time,"explicit checkpoint preserves captured time")
	check(not host.request_rebuild_environment(false),"rebuild requires explicit discard policy")
	var saved=host.environment_scene
	var invalid:=PackedScene.new();var empty:=Node.new();invalid.pack(empty);empty.free();host.environment_scene=invalid
	check(host.request_rebuild_environment(true),"invalid environment candidate queued")
	await ticks(2)
	check(host.world==world and world.info().time==time and not host.last_error.is_empty(),"failed environment candidate preserves original world and state")
	host.environment_scene=saved
	world.add_child(instance(resource,"DiscardedAddition",Vector3(7,0,0)))
	await world_ready(world)
	for trial in 3:
		check(host.request_rebuild_environment(true),"request environment rebuild")
		check(not host.request_rebuild_environment(true),"repeated environment rebuild rejected")
		await host_ready(host);await done(host.world)
		world=host.world
		check(world.info().time==0 and world.info().paused and not world.has_node("DiscardedAddition"),"environment reload restores saved design and discards runtime additions")
	check(controls.get_instance_id()==component_id and controls.bound_world==world,"scene-owned viewer survives all resets and rebuilds")
	extras.show_extras(true)
	extras.ui.fields.step_count.get_line_edit().text="4"
	extras.ui.fields.step_count.apply()
	extras.ui.fields.step_button.pressed.emit()
	check(await wait_for(func():return abs(world.info().time-.008)<1e-10),"actual Step N component control routes to native clock")
	controls.ui.get_action_control("reset_initial").pressed.emit()
	check(await wait_for(func():return world.info().time==0),"actual initial reset control restores state")
	check(await preload("res://addons/godot_mujoco/model/scene_builder.gd").save_playground(resource,"res://GeneratedPlayground.tscn")==OK,"editor playground builder saves controls and environment")
	var generated=load("res://GeneratedPlayground.tscn").instantiate()
	root.add_child(generated);generated.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await host_ready(generated.get_node("EnvironmentHost"))
	check(generated.get_node("EnvironmentHost").world.ready_for_models and generated.get_node("RuntimeViewer").bound_world==generated.get_node("EnvironmentHost").world,"saved playground reopens with explicit connected component")
	generated.queue_free();await ticks(2)
	await rebuild_feedback_regression(controls,host,second_host)
	controls.queue_free();extras.queue_free();host.queue_free();second_host.queue_free();await ticks(3)
	var failed:=checks.filter(func(c):return not c.passed).size()
	print("CLOCK_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)

func wait_for(predicate: Callable, seconds := 20.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call(): return true
		await process_frame
	return false

func viewer_action(controls: Node, action: String) -> Dictionary:
	var request: int=controls.execute(action)
	check(request>0,"accept component "+action)
	if request==0: return {}
	check(await wait_for(func():return not controls.action_result(request).is_empty(),125),"component action reaches terminal result "+action)
	return controls.action_result(request)

func rebuild_feedback_regression(controls: Node, host: Node, other_host: Node) -> void:
	var saved=host.environment_scene
	var original=host.world
	var state: Dictionary=original.get_node("Robot").state()
	var time: float=original.info().time
	var invalid:=PackedScene.new()
	var empty:=Node.new();invalid.pack(empty);empty.free()
	host.environment_scene=invalid
	var failed: Dictionary=await viewer_action(controls,"reload")
	check(not failed.get("success",true) and not host.last_error.is_empty(),"component reload reports actual candidate failure")
	check(host.world==original and original.info().time==time and original.get_node("Robot").state()==state,"failed component reload preserves original world and state")
	check(controls.ui.feedback.contains(host.last_error) or controls.last_error.contains(host.last_error),"reload failure has component feedback independent of retained-world error")
	host.environment_scene=saved
	var original_id: int=original.get_instance_id()
	var completed: Dictionary=await viewer_action(controls,"reload")
	check(completed.get("success",false) and host.world.get_instance_id()!=original_id and controls.bound_world==host.world,"successful component retry binds the committed replacement world")
	controls.environment_host=other_host
	check(await wait_for(func():return controls.bound_world==other_host.world),"explicit host reassignment binds the new committed target")
	host.rebuild_finished.emit(false,"stale host error")
	await ticks(2)
	check(controls.bound_world==other_host.world and not controls.ui.feedback.contains("stale host error"),"old host completion cannot overwrite component feedback")
	controls.enabled=false
	check(not controls.execute("step",{"count":1}),"disabled component no longer routes simulation input")
	controls.enabled=true
	check(await wait_for(func():return controls.bound_world==other_host.world),"component re-enable restores only the explicit target")
	var temporary=Host.new();temporary.environment_scene=saved;root.add_child(temporary);temporary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);await host_ready(temporary)
	controls.environment_host=temporary
	check(await wait_for(func():return controls.bound_world==temporary.world),"component can bind a newly created host")
	temporary.queue_free();await ticks(5)
	check(not is_instance_valid(controls.bound_world),"host destruction detaches component safely")
	controls.environment_host=host
	check(await wait_for(func():return controls.bound_world==host.world),"component can recover to an explicitly assigned surviving host")
