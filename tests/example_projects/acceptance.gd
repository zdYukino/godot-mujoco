extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if ProjectSettings.get_setting("application/config/name", "") == "MuJoCo Independent Pendulum":
		await check_pendulum()
		return
	check(ProjectSettings.get_setting("physics/3d/physics_engine") == "MuJoCo", "project selects MuJoCo")
	check(not ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false), "physics stays on the main thread")
	check("res://addons/mujoco_editor/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()), "editor plugin is enabled")
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	var packed := load(path) as PackedScene
	check(packed != null, "configured F5 scene opens: " + path)
	if not packed:
		finish(); return
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	var initial_y := 0.0
	if scene.name == "PassiveG1Gallery":
		var robot = scene.get_node("G1_1")
		check(robot.model_rid.is_valid(), "saved G1 loads without a source rebuild")
		if not robot.model_rid.is_valid():
			scene.free(); finish(); return
		initial_y = robot.state().bodies.pelvis.transform.origin.y
	for i in 360:
		await physics_frame
		await process_frame
	var space: RID = scene.get_world_3d().space
	var info: Dictionary = PhysicsServer3D.call("scene_info", space)
	check(info.get("time", 0.0) > 1.0, "default scene advances real simulation")
	check(info.get("warning_count", -1) == 0, "simulation has no MuJoCo warnings")
	match String(scene.name):
		"ShapeGallery":
			var model = scene.get_node("Model")
			check(model.model_rid.is_valid() and model.state().joints.size() == 7, "gallery has seven actual freejoint bodies")
			check(not info.contact_details.is_empty(), "gallery bodies make contact")
		"PassiveG1Gallery":
			var robot = scene.get_node("G1_1")
			check(robot.state().joints.size() == 30 and info.nu == 0, "G1 has a free base and 29 passive hinges")
			check(robot.state().bodies.pelvis.transform.origin.y < initial_y - 0.3, "single G1 falls under gravity")
			check(scene.get_node("DisplayControls").robots.size() == 1, "default entry loads one robot without hot-add")
		"SdfTerrain":
			check(scene.last_error.is_empty() and scene.native_rids.size() == 3, "three saved terrain chunks load")
			for rid in scene.native_rids:
				var geometry: Array = PhysicsServer3D.call("scene_geometry", space, rid)
				check(not geometry.is_empty() and geometry.all(func(geom): return geom.type == 8), "terrain uses actual SDF geometry")
			check(absf(scene.get_node("PitBall").position.y + 0.23) < 0.04, "saved pit ball rests at the concave floor")
			var package_path := FileAccess.get_file_as_string("res://map_package_path.txt").strip_edges()
			check(preload("res://addons/godot_mujoco/map/package.gd").validate(package_path).is_empty(), "saved map package validates")
		_:
			check(false, "unexpected default scene: " + String(scene.name))
	scene.free()
	await process_frame
	finish()

func check_pendulum() -> void:
	var packed := load(ProjectSettings.get_setting("application/run/main_scene")) as PackedScene
	check(packed != null, "pendulum main scene opens")
	if not packed:
		finish(); return
	var scene = packed.instantiate()
	root.add_child(scene)
	check(scene.world.is_ready(), "independent MjWorld loads its model")
	check(scene.world.get_nq() == 1 and scene.world.get_nu() == 1, "one hinge and actuator")
	var initial: float = scene.world.get_qpos()[0]
	for unused in 360:
		await physics_frame
		await process_frame
	check(scene.world.get_time() > 1.0, "pendulum advances real simulation")
	check(absf(scene.world.get_qpos()[0] - initial) > 0.0001, "pendulum actually moves")
	check(scene.world.get_warnings().is_empty(), "pendulum has no MuJoCo warnings")
	check(absf(scene.get_node("Pendulum").rotation.z + scene.world.get_qpos()[0]) < 0.001, "visual rotation follows simulation")
	scene.free()
	await process_frame
	finish()

func finish() -> void:
	print("EXAMPLE_PROJECT_RESULT ", JSON.stringify({"passed": passed, "failed": failed}))
	quit(1 if failed else 0)
