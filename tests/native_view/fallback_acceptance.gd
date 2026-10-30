extends SceneTree
const Settings = preload("res://addons/godot_mujoco/native_view/settings.gd")
var checks: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, name: String) -> void:
	checks.append({"name":name,"passed":ok})
	if not ok: printerr("FAIL ",name)
func wait_for(test: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		if test.call(): return true
		await process_frame
	return false
func fixture() -> Node:
	var scene: Node = load("res://Main.tscn").instantiate()
	var observer := scene.get_node_or_null("F5RenderProbe")
	if observer: observer.free()
	scene.start_paused=true
	return scene
func run() -> void:
	ProjectSettings.set_setting(Settings.MODE,Settings.MUJOCO)
	var world := fixture();root.add_child(world)
	check(await wait_for(func():return world.author_started and world.command_request==0 and not world.native_view_error.is_empty()),"headless native request reports startup failure")
	check(not world.native_view_active and world.visible and not root.disable_3d,"startup failure preserves Godot 3D")
	check("原生回退" in world.rendering_status(),"fallback reason is visible in renderer status")
	check(world.step_simulation(5),"fallback still accepts physics commands")
	check(await wait_for(func():return world.command_request==0 and world.info().get("time",0)>0),"authoritative physics continues after native rejection")
	world.queue_free()
	for frame in 5: await process_frame
	ProjectSettings.set_setting(Settings.MODE,Settings.GODOT)
	world=fixture();world.native_view_experimental=true;root.add_child(world)
	check(await wait_for(func():return world.author_started and world.command_request==0),"Godot choice starts valid world")
	check(not world.native_view_experimental and not world.native_view_active and world.native_view_error.is_empty(),"explicit Godot project choice overrides old scene opt-in")
	world.queue_free()
	for frame in 5: await process_frame
	var failed := checks.filter(func(row):return not row.passed).size()
	FileAccess.open(OS.get_environment("GMJ_RENDER_TEST_OUT").path_join("fallback.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"  "))
	print("F5_RENDERER_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)
