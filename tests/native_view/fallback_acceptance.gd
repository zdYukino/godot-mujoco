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
	var observer := scene.get_node_or_null("Runtime/F5RenderProbe")
	if observer: observer.free()
	scene.get_node("Runtime").start_paused=true
	return scene
func run() -> void:
	if DisplayServer.get_name()=="headless":root.size=Vector2i(1100,760)
	ProjectSettings.set_setting(Settings.MODE,Settings.MUJOCO)
	var scene := fixture(); var world: Node=scene.get_node("Runtime"); root.add_child(scene)
	check(await wait_for(func():return world.author_started and world.command_request==0 and not world.native_view_error.is_empty()),"headless native request reports startup failure")
	var viewer: Node=scene.get_node("RuntimeViewer")
	check(await wait_for(func():return viewer.status=="ACTIVE" and is_instance_valid(viewer._session._godot_viewport)),"native fallback binds the explicit Godot presentation component")
	check(not world.native_view_active and world.visible and not viewer._session._godot_viewport.disable_3d,"startup failure preserves actual Godot 3D rendering")
	check("原生回退" in world.rendering_status(),"fallback reason is visible in renderer status")
	check(world.step_simulation(5),"fallback still accepts physics commands")
	check(await wait_for(func():return world.command_request==0 and world.info().get("time",0)>0),"authoritative physics continues after native rejection")
	scene.queue_free()
	for frame in 5: await process_frame
	ProjectSettings.set_setting(Settings.MODE,Settings.GODOT)
	scene=fixture();world=scene.get_node("Runtime");world.native_view_experimental=true;root.add_child(scene)
	check(await wait_for(func():return world.author_started and world.command_request==0),"Godot choice starts valid world")
	check(not world.native_view_experimental and not world.native_view_active and world.native_view_error.is_empty(),"explicit Godot project choice overrides old scene opt-in")
	scene.queue_free()
	for frame in 5: await process_frame
	var failed := checks.filter(func(row):return not row.passed).size()
	FileAccess.open(OS.get_environment("GMJ_RENDER_TEST_OUT").path_join("fallback.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failed":failed},"  "))
	print("F5_RENDERER_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)
