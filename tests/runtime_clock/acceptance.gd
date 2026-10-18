extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Host = preload("res://addons/godot_mujoco/model/environment_host.gd")
const Controls = preload("res://addons/godot_mujoco/model/simulation_controls.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func ticks(n: int) -> void:
	for unused in n:
		await physics_frame
		await process_frame
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
	var node=Instance.new();node.model=resource;node.name=name;node.position=position;return node
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var file:=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
	file.store_string('<mujoco><option timestep=".002"/><worldbody><body name="ball" pos="0 0 2"><freejoint name="root"/><geom name="ball_geom" type="sphere" size=".2" mass="2"/></body><body name="arm" pos="1 0 2"><joint name="hinge" range="-1 1"/><geom type="capsule" size=".1 .3" mass="1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="10"/><general name="filtered" joint="hinge" dyntype="filter" dynprm=".1"/></actuator></mujoco>')
	file.close()
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file("res://fixture.xml"),"create clock fixture")
	var package: Dictionary=Builder.pack(doc,"res://models","clock")
	check(package.error.is_empty(),"save clock design")
	var resource=load(package.path)
	var environment=World.new();environment.name="Environment";environment.world_model=resource;environment.start_paused=true
	var robot=instance(resource,"Robot",Vector3.ZERO);environment.add_child(robot);robot.owner=environment
	var body:=RigidBody3D.new();body.name="Ordinary";body.position=Vector3(3,3,0)
	var shape:=CollisionShape3D.new();var sphere:=SphereShape3D.new();sphere.radius=.2;shape.shape=sphere
	body.add_child(shape);environment.add_child(body);body.owner=environment;shape.owner=environment
	var scene:=PackedScene.new();check(scene.pack(environment)==OK and ResourceSaver.save(scene,"res://Environment.tscn")==OK,"save authored environment")
	environment.free()
	var host=Host.new();host.environment_scene=load("res://Environment.tscn");root.add_child(host)
	await ticks(3)
	var world=host.world
	check(is_instance_valid(world) and world.ready_for_models,"host configures independent world")
	if not is_instance_valid(world): quit(1);return
	await done(world)
	robot=world.get_node("Robot");body=world.get_node("Ordinary")
	var controls=Controls.new();controls.environment_host=host;root.add_child(controls)
	var start: Dictionary=robot.state()
	var time: float=world.info().time
	var game: float=controls.game_elapsed
	await ticks(10)
	check(world.info().time==time and controls.game_elapsed>game,"UI game clock advances while simulation stays paused")
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
		await ticks(1)
		await call_command(world,"step_simulation",2)
		await call_command(world,"reset_simulation")
		check(is_instance_valid(added) and added.model_rid.is_valid() and added.state().joints.root.qvel==PackedFloat64Array([0,0,0,0,0,0]),"reset retains and initializes runtime addition")
		added.queue_free();await ticks(2)
	var edit_doc: RefCounted=resource.open_document().document
	check(edit_doc.edit({"op":"set","kind":"body","name":"ball","values":{"mass":3.0}}),"author inertia edit while world paused")
	var edited_package: Dictionary=Builder.pack(edit_doc,"res://models","edited")
	var paused_time: float=world.info().time
	check(robot.request_model_edit(load(edited_package.path)),"queue paused runtime model edit")
	for unused in 120:
		if robot.edit_request==0: break
		await ticks(1)
	check(robot.property_revision==1 and robot.state().bodies.ball.mass==3 and world.info().time==paused_time,"paused model transaction preserves simulation clock")
	await call_command(world,"reset_simulation")
	check(robot.state().bodies.ball.mass==3,"state reset keeps committed design changes")
	var second_host=Host.new();second_host.environment_scene=load("res://Environment.tscn");root.add_child(second_host);await ticks(3);await done(second_host.world)
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
	for trial in 3:
		check(host.request_rebuild_environment(true),"request environment rebuild")
		check(not host.request_rebuild_environment(true),"repeated environment rebuild rejected")
		await ticks(3);await done(host.world)
		world=host.world
		check(world.info().time==0 and world.info().paused and not world.has_node("DiscardedAddition"),"environment reload restores saved design and discards runtime additions")
	check(controls.game_elapsed>game,"game UI survives all resets and rebuilds")
	var button: Button
	for child in controls.get_children():
		if child is Button and child.text.begins_with("单步"): button=child
	controls.count.get_line_edit().text="4"
	button.pressed.emit()
	await done(world)
	check(abs(world.info().time-.008)<1e-10,"actual Step N control routes to native clock")
	for child in controls.get_children():
		if child is Button and child.text.begins_with("重置仿真"): child.pressed.emit()
	await done(world)
	check(world.info().time==0,"actual reset control restores state")
	check(preload("res://addons/godot_mujoco/model/scene_builder.gd").save_playground(resource,"res://GeneratedPlayground.tscn")==OK,"editor playground builder saves controls and environment")
	var generated=load("res://GeneratedPlayground.tscn").instantiate()
	root.add_child(generated);await ticks(3)
	check(generated.get_node("EnvironmentHost").world.ready_for_models and generated.get_node("SimulationControls").target()==generated.get_node("EnvironmentHost").world,"saved playground reopens with connected controls")
	generated.queue_free();await ticks(2)
	await rebuild_feedback_regression(controls,host,second_host)
	controls.queue_free();host.queue_free();second_host.queue_free();await ticks(3)
	var failed:=checks.filter(func(c):return not c.passed).size()
	print("CLOCK_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)

func rebuild_feedback_regression(controls: Node, host: Node, other_host: Node) -> void:
	var button: Button
	for child in controls.get_children():
		if child is Button and child.text.begins_with("重建已保存环境"): button=child
	var saved=host.environment_scene
	var original=host.world
	var state: Dictionary=original.get_node("Robot").state()
	var time: float=original.info().time
	var invalid:=PackedScene.new()
	var empty:=Node.new();invalid.pack(empty);empty.free()
	host.environment_scene=invalid
	button.pressed.emit()
	check(controls.feedback=="Environment rebuild requested","actual rebuild button displays queued state")
	button.pressed.emit()
	await ticks(3)
	check(controls.feedback.contains("Environment rebuild failed") and controls.status.text.contains(host.last_error) and not host.last_error.is_empty(),"actual rebuild failure displays host error in visible status")
	check(host.world==original and original.info().time==time and original.get_node("Robot").state()==state,"failed button rebuild preserves original world and state")
	check(original.last_error.is_empty(),"host error remains visible even when retained world error is empty")
	host.environment_scene=saved
	var original_id: int=original.get_instance_id()
	button.pressed.emit();await ticks(3);await done(host.world);await ticks(1)
	check(controls.feedback.contains("Environment rebuild succeeded") and controls.status.text.contains("Environment rebuild succeeded") and not controls.feedback.contains("failed"),"successful button retry replaces failure with visible completion")
	check(host.world.get_instance_id()!=original_id and controls.bound_world==host.world,"world replacement rebinds command completion signal")
	check(host.world.command_finished.is_connected(controls.on_command_finished),"new world command signal connected")
	controls.environment_host=other_host
	check(not host.rebuild_finished.is_connected(controls.on_rebuild_finished) and other_host.rebuild_finished.is_connected(controls.on_rebuild_finished),"host reassignment disconnects old and connects new immediately")
	var feedback: String=controls.feedback
	host.rebuild_finished.emit(false,"stale host error")
	check(controls.feedback==feedback,"old host completion cannot overwrite feedback")
	for unused in 5: controls.sync_targets()
	var connections:=0
	for connection in other_host.rebuild_finished.get_connections():
		if connection.callable==Callable(controls,"on_rebuild_finished"): connections+=1
	check(connections==1,"repeated target refresh does not duplicate connection")
	root.remove_child(controls)
	check(not other_host.rebuild_finished.is_connected(controls.on_rebuild_finished) and not other_host.world.command_finished.is_connected(controls.on_command_finished),"controls exit disconnects host and world signals")
	root.add_child(controls)
	check(other_host.rebuild_finished.is_connected(controls.on_rebuild_finished) and other_host.world.command_finished.is_connected(controls.on_command_finished),"same controls reentry restores single signal subscriptions")
	var temporary=Host.new();temporary.environment_scene=saved;root.add_child(temporary);await ticks(3)
	controls.environment_host=temporary
	temporary.queue_free();await ticks(3)
	check(not is_instance_valid(controls.bound_host) and not is_instance_valid(controls.bound_world) and controls.status.text.contains("no world"),"host destruction detaches signals and shows no world safely")
	controls.environment_host=host
	check(controls.bound_host==host and controls.bound_world==host.world,"controls can recover to surviving host after destruction")

	other_host.environment_scene=invalid
	check(other_host.request_rebuild_environment(true),"detached host can complete failed rebuild")
	await ticks(3)
	controls.environment_host=other_host
	await ticks(1)
	check(controls.status.text.contains(other_host.last_error) and controls.feedback.contains("Environment rebuild failed"),"late host binding displays existing failure without requiring a new signal")
	controls.environment_host=host
	check(not controls.feedback.contains(other_host.last_error),"switching host clears previous host failure")
