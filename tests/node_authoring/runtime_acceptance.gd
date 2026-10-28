extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); print("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func settle(world: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if world.info().get("compile_status") in ["ready", "failed"] and not world.author_compiler.busy():
			return world.info().get("compile_status") == "ready"
		await process_frame
	check(false, "async world timeout")
	return false

func stage(model: Node) -> void:
	PhysicsServer3D.call("scene_stage_author_model", model.space, model.model_rid, model.author_definition())

func run() -> void:
	var parsed := Author.from_xml('<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody><geom name="floor" type="plane" size="5 5 .1"/><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" type="capsule" fromto="0 0 0 0 0 -.6" size=".04"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator></mujoco>')
	for entity in parsed.design.entities():
		if entity.kind=="joint": parsed.design.initial_pose[entity.id]=[.2]
	var world := World.new(); world.name = "World"; world.world_design = parsed.design; world.start_paused = true
	var model := Model.new(); model.name = "Model"; model.design = parsed.design.fork()
	world.add_child(model); model.owner = world
	root.add_child(world)
	check(await settle(world), "world assembled by isolated compiler")
	check(model.model_rid.is_valid(), "model handle registered before background compile")
	check(world.info().paused, "initial paused state")
	check(model.state().joints.has("hinge"), "combined model retains joint")
	for frame in 4: await physics_frame
	check(model.set_control("motor", .1), "control input allowed")
	check(world.step_simulation(100), "queue exact physics steps")
	var deadline := Time.get_ticks_msec() + 5000
	while world.command_request != 0 and Time.get_ticks_msec() < deadline: await process_frame
	check(is_equal_approx(world.info().time, .2), "exact step advances authored timestep")
	var before: Dictionary = model.state().joints.hinge
	var time_before: float = world.info().time
	var rod := {}
	var hinge := {}
	for entity in model.design.entities():
		if entity.name == "rod": rod = entity
		if entity.name == "hinge": hinge = entity
	var edited := Commands.execute(model.design, {"op":"set", "id":rod.id, "values":{"density":1200.0}})
	model.design.restore_author(edited.after)
	stage(model)
	check(world.info().paused and world.info().design_pending, "design change immediately pauses native world")
	check(not world.set_paused(false), "resume refused for uncompiled design")
	var frozen: float = world.info().time
	for frame in 6: await physics_frame
	check(is_equal_approx(world.info().time, frozen), "no physical integration during compilation")
	check(await settle(world), "parameter edit compiles asynchronously")
	check(world.info().paused, "successful edit requires manual resume")
	check(is_equal_approx(world.info().time, time_before), "world time retained")
	check(is_equal_approx(model.state().joints.hinge.qpos[0], before.qpos[0]), "compatible joint position retained")
	check(is_equal_approx(model.state().joints.hinge.qvel[0], before.qvel[0]), "compatible joint velocity retained")
	var renamed := Commands.execute(model.design, {"op":"rename", "id":hinge.id, "name":"renamed"})
	model.design.restore_author(renamed.after); stage(model)
	check(await settle(world), "joint rename compiles")
	check(model.state().joints.has("renamed"), "new joint name exported")
	check(is_equal_approx(model.state().joints.renamed.qpos[0], before.qpos[0]), "stable identity preserves renamed joint state")
	var valid: Dictionary = model.design.author_snapshot()
	var invalid := Commands.execute(model.design, {"op":"delete", "id":rod.id, "confirmed":true})
	model.design.restore_author(invalid.after); stage(model)
	check(not await settle(world), "invalid candidate rejected")
	check(world.info().paused, "failure retains paused state")
	check(model.state().joints.has("renamed"), "failed candidate leaves active world intact")
	check(not world.set_paused(false), "failure cannot resume stale active version")
	model.design.restore_author(valid); stage(model)
	check(await settle(world), "restore committed author design recovers")
	check(world.set_paused(false), "manual resume after valid commit")
	for frame in 4: await physics_frame
	check(world.info().time > time_before, "simulation continues after explicit resume")
	check(world.set_paused(true),"pause before joint coordinate edit")
	var axis_edit := Commands.execute(model.design,{"op":"set","id":hinge.id,"values":{"axis":[1.,0.,0.]}})
	model.design.restore_author(axis_edit.after); stage(model)
	check(await settle(world),"joint-axis edit compiles")
	check(is_equal_approx(model.state().joints.renamed.qpos[0],.2) and is_zero_approx(model.state().joints.renamed.qvel[0]),"changed coordinate subtree restores explicit initial qpos and zero velocity")
	var type_edit := Commands.execute(model.design,{"op":"set_joint_type","id":hinge.id,"type":"slide","confirmed":true})
	model.design.restore_author(type_edit.after);stage(model)
	check(await settle(world),"joint type changes with confirmed dependency removal")
	check(world.reset_simulation(),"reset accepted after changed joint type")
	deadline = Time.get_ticks_msec()+5000
	while world.command_request!=0 and Time.get_ticks_msec()<deadline: await process_frame
	check(world.last_command_result.get("success",false),"checkpoint migrated to current names and coordinate types")
	world.cancel_author_compile()
	for frame in 6: await physics_frame;await process_frame
	check(world.info().compile_status=="failed" and world.info().paused and not world.set_paused(false),"cancel invalidates candidates and cannot auto-resume or silently restart")
	stage(model)
	check(await settle(world),"explicit source retry recovers after world cancellation")
	world.queue_free(); await process_frame; await process_frame
	print("NODE_RUNTIME_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
