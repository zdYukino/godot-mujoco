extends SceneTree
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: call_deferred("run")
func settled(world: Node) -> bool:
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		if world.author_started and world.command_request == 0: return true
		if world.info().get("compile_status") == "failed": return false
		await process_frame
	return false
func run() -> void:
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "MuJoCo","project selects MuJoCo")
	check(not ProjectSettings.get_setting("physics/3d/run_on_separate_thread",false),"main-thread physics")
	check("res://addons/mujoco_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled",PackedStringArray()),"editor plugin enabled")
	var paths := [str(ProjectSettings.get_setting("application/run/main_scene"))]
	if ProjectSettings.get_setting("application/config/name") == "MuJoCo Editable Pendulum": paths = ["res://Main.tscn","res://ChaosPendulum.tscn","res://VisualDebug.tscn"]
	for path in paths:
		var packed := load(path) as PackedScene
		check(packed != null,"saved scene opens: "+path)
		if not packed: continue
		var scene: Node = packed.instantiate(); root.add_child(scene)
		check(scene is MjRuntimeWorld and scene.world_design != null,"scene owns author world")
		if not await settled(scene):
			check(false,"background startup: "+str(scene.info().get("last_error")))
			scene.queue_free(); await process_frame; continue
		check(not scene.editor_connected,"standalone has no design editor")
		check(scene.request_editor_design({"op":"duplicate_model"}) == 0,"standalone design requests disabled")
		var initial_y := 0.0
		if scene.name == "PassiveG1Gallery":
			initial_y = scene.get_node("G1_1").state().bodies.pelvis.transform.origin.y
		check(scene.set_paused(false),"simulation can start after compilation")
		for frame in 360: await physics_frame; await process_frame
		var info: Dictionary = scene.info()
		check(info.time>1.0,"real shared simulation advances")
		check(info.warning_count==0,"no native warnings")
		var models := []
		for node in preload("res://addons/godot_mujoco/model/world_layout.gd").nodes(scene):
			if node is MjModelInstance: models.append(node)
		for model in models:
			check(model.model==null and model.design!=null,"formal author source replaces packaged runtime model")
			check(not model.author_scene.nodes.is_empty(),"semantic body/geom/joint hierarchy")
			check(model.visuals.size()==model.design.cached_geometry.size(),"all persisted visual meshes loaded")
		match String(scene.name):
			"ShapeGallery":
				check(scene.get_node("Model").state().joints.size()==7,"seven freejoint shapes")
				check(info.ncon>0,"shapes contact floor")
			"PassiveG1Gallery":
				var robot = scene.get_node("G1_1")
				check(robot.state().joints.size()==30 and info.nu==0,"one free base and 29 passive hinges")
				check(robot.state().bodies.pelvis.transform.origin.y<initial_y-.3,"single G1 falls under gravity")
				check(scene.get_node("DisplayControls").robots.size()==1,"single G1 default; double hot-add is diagnostic only")
				check(scene.get_node("DisplayControls").add_button.disabled,"standalone G1 design button disabled")
				check(scene.get_node("Heightfield").get_child_count()>0,"saved extra terrain retained")
			"SdfTerrainWorld":
				var map = scene.get_node("Map")
				check(map.native_rids.size()==3 and map.last_error.is_empty(),"three saved SDF chunks")
				for rid in map.native_rids:
					var geometry: Array = PhysicsServer3D.call("scene_geometry",scene.space,rid)
					check(not geometry.is_empty() and geometry.all(func(g):return g.type==8),"actual native SDF")
				check(absf(map.get_node("PitBall").position.y+.23)<.04,"concave pit contacts preserved")
			"Main":
				if path.ends_with("ChaosPendulum.tscn"):
					check(models[0].state().joints.size()==2,"chaotic double pendulum in shared world")
				elif path.ends_with("VisualDebug.tscn"):
					check(models[0].state().joints.size()==4 and info.ncon>0,"four balls contact floor")
					check(not info.contact_details.is_empty() and info.contact_details[0].force is Vector3,"debug contact world force available")
				elif not models.is_empty():
					check(absf(models[0].state().joints.hinge.qpos[0])>.00001,"motor-driven pendulum moves")
					check(models[0].state().joints.hinge.anchor is Vector3,"world joint anchor and axis available")
				else: check(scene.get_node("Ball").position.y<1.,"template ball contacts native floor")
		scene.queue_free(); await process_frame; await process_frame
	print("EXAMPLE_PROJECT_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(1 if failed else 0)
