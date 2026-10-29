extends SceneTree
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
const BenchmarkStats = preload("res://benchmark_stats.gd")
var config: Dictionary
var world: Node3D
var camera: Camera3D
var camera_base: Transform3D
var center := Vector3.ZERO
var job := {}
var initial := PackedFloat64Array()
var fixture: Dictionary
var original_picking := false

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	push_error("BENCHMARK: " + message)
	quit(2)

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Cannot write " + path)
	file.store_string(JSON.stringify(value, "\t"))

func bridge(action: String, payload: Dictionary = {}) -> Dictionary:
	var value: Dictionary = PhysicsServer3D.call("scene_benchmark", world.space, action, payload)
	assert(value.get("error", "").is_empty(), str(value))
	return value

func write_state(path: String, value: PackedFloat64Array) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	for number in value: file.store_double(number)

func read_state(path: String) -> PackedFloat64Array:
	var file := FileAccess.open(path, FileAccess.READ)
	var values := PackedFloat64Array()
	while file.get_position() < file.get_length(): values.append(file.get_double())
	return values

func nodes(node: Node) -> Array[Node]:
	var values: Array[Node] = [node]
	for child in node.get_children(): values.append_array(nodes(child))
	return values

func mvec(value: Vector3) -> Array:
	return [value.x, -value.z, value.y]

func save_camera(directory: String) -> Dictionary:
	var projection := camera.get_camera_projection()
	var result := {"position":mvec(camera.global_position), "forward":mvec(-camera.global_basis.z), "up":mvec(camera.global_basis.y), "center":mvec(center), "near":camera.near, "far":camera.far, "top":camera.near / projection.y.y}
	var values: Array = []
	for key in ["position", "forward", "up", "center"]: values.append_array(result[key])
	values.append_array([result.near, result.far, result.top])
	var file := FileAccess.open(directory.path_join("camera.txt"), FileAccess.WRITE)
	file.store_string(" ".join(values.map(func(v): return String.num(float(v), 17))) + "\n")
	return result

func record_fixture(directory: String) -> Dictionary:
	var captured := bridge("capture", {"model_path":directory.path_join("model.mjb")})
	var state: PackedFloat64Array = captured.state
	captured.erase("state")
	write_state(directory.path_join("state.f64"), state)
	captured.model_sha256 = FileAccess.get_sha256(directory.path_join("model.mjb"))
	captured.state_sha256 = FileAccess.get_sha256(directory.path_join("state.f64"))
	captured.camera = save_camera(directory)
	captured.workload = config.workload
	var objects: Array = world.info().objects
	var visual_names := {}
	var mesh_count := 0
	for node in nodes(world):
		if node is MeshInstance3D and node.is_visible_in_tree(): mesh_count += 1
		if node is Instance:
			var prefix := ""
			for object in objects:
				if object.rid == node.model_rid: prefix = object.prefix
			for name in node.visuals:
				if node.visuals[name].is_visible_in_tree(): visual_names[prefix + name] = true
	var visible: Array = []
	var projections: Array = []
	for geom in captured.geoms:
		# Ordinary Godot terrain has native gN names and an independent mesh.
		if visual_names.has(geom.name) or str(geom.name).begins_with("g"):
			visible.append(geom.id)
			var point: Vector2 = camera.unproject_position(geom.position)
			projections.append({"id":geom.id, "name":geom.name, "world":mvec(geom.position), "pixel":[point.x,point.y]})
		geom.position = mvec(geom.position)
	var mask_file := FileAccess.open(directory.path_join("visible.txt"), FileAccess.WRITE)
	mask_file.store_string(" ".join(visible.map(func(v): return str(v))) + "\n")
	captured.visible_geoms = visible
	captured.projected_geom_centers = projections
	captured.mesh_nodes = mesh_count
	captured.compile_job = job.duplicate(true)
	if not job.is_empty():
		var request_file := FileAccess.open(str(job.directory).path_join("request.bin"), FileAccess.READ)
		var request: Dictionary = request_file.get_var(false)
		assert(str(request.generation) == str(world.space.get_id()))
		assert(int(request.revision) == int(captured.design_revision))
		captured.compile_request_sha256 = FileAccess.get_sha256(str(job.directory).path_join("request.bin"))
		captured.compile_result_sha256 = FileAccess.get_sha256(str(job.directory).path_join("result.bin"))
		var result_file := FileAccess.open(str(job.directory).path_join("result.bin"), FileAccess.READ)
		var result: Dictionary = result_file.get_var(false)
		var xml_file := FileAccess.open(directory.path_join("world.xml"), FileAccess.WRITE)
		xml_file.store_string(result.snapshot.xml)
	write_json(directory.path_join("manifest.json"), captured)
	return captured

func common_visuals(geometry: Array) -> void:
	for node in nodes(world):
		if node is CanvasLayer: node.visible = false
		if node is Light3D: node.visible = false
		if node is WorldEnvironment: node.environment = null
		if node is MeshInstance3D and node.mesh:
			var old: Material = node.get_active_material(0)
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if old is BaseMaterial3D:
				material.albedo_color = old.albedo_color
				material.albedo_texture = old.albedo_texture
				material.transparency = old.transparency
			elif old is ShaderMaterial:
				var color: Variant = old.get_shader_parameter("base_color")
				if color is Color: material.albedo_color = color
				elif color is Vector4: material.albedo_color = Color(color.x,color.y,color.z,color.w)
			node.material_override = material
	var compiled_colors := {}
	for geom in geometry:
		compiled_colors[geom.name] = Color(geom.rgba[0],geom.rgba[1],geom.rgba[2],geom.rgba[3])
		if geom.has("node_path"):
			var owner := root.get_node_or_null(str(geom.node_path))
			if owner is MjStaticHeightField and owner._visual and owner._visual.material_override:
				owner._visual.material_override.albedo_color = compiled_colors[geom.name]
	var objects: Array = world.info().objects
	for node in nodes(world):
		if not node is Instance: continue
		for object in objects:
			if object.rid != node.model_rid: continue
			for key in node.visuals:
				var full_name: String = str(object.prefix) + str(key)
				if compiled_colors.has(full_name):
					node.visuals[key].material_override.albedo_color = compiled_colors[full_name]
	# Retain the example's update path; only its grid-material override would
	# otherwise replace our common unlit material every frame.
	var controls := world.get_node_or_null("DisplayControls")
	if controls: controls.set_meta("benchmark_common", true)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	root.world_3d.environment = environment

func orbit(elapsed: float) -> void:
	var angle := .25 * sin(TAU * elapsed / 12.0)
	var rotation := Basis(Vector3.UP, angle)
	camera.global_transform = Transform3D(rotation * camera_base.basis, center + rotation * (camera_base.origin - center))

func restore() -> void:
	bridge("restore", {"state":initial})
	for node in nodes(world):
		if node is Instance: node._physics_process(0.0)

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 1: fail("Expected one config JSON path"); return
	config = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not PhysicsServer3D.has_method("scene_benchmark"): fail("Build with GMJ_VIEWER_BENCHMARK=ON"); return
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	root.mode = Window.MODE_FULLSCREEN
	DisplayServer.window_set_size(Vector2i(config.width, config.height))
	root.size = Vector2i(config.width, config.height)
	root.content_scale_size = Vector2i.ZERO
	original_picking = root.physics_object_picking
	root.physics_object_picking = false
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	world = packed.instantiate()
	world.name = "BenchmarkWorld"
	world.start_paused = true
	if config.workload == "g1-dual":
		var source: Node3D = world.get_node("G1_1")
		var copy := source.duplicate()
		copy.design = source.design.fork()
		copy.design_instance_id = "benchmark-second-g1"
		copy.name = "G1_2"
		copy.position.x += 3.6
		world.add_child(copy)
	root.add_child(world)
	current_scene = world
	world.author_compiler.completed.connect(func(value):
		if value.get("success", false): job = {"directory":value.directory, "job_id":value.job_id, "generation":value.generation, "revision":value.revision})
	var deadline := Time.get_ticks_msec() + 180000
	var ready_frames := 0
	while ready_frames < 12:
		await process_frame
		var info: Dictionary = world.info()
		var ready: bool = world.author_started and world.command_request == 0 and info.get("compile_status") == "ready" and not info.get("design_pending", true)
		for node in nodes(world):
			if node is MjStaticHeightField and node.pending_request != 0: ready = false
			if node is Instance:
				if not node.model_rid.is_valid():
					ready = false
					if not node.last_error.is_empty(): fail(str(node.get_path()) + ": " + node.last_error); return
				if node.author_scene and not node.author_scene.geometry_queue.is_empty(): ready = false
		ready_frames = ready_frames + 1 if ready else 0
		if Time.get_ticks_msec() > deadline: fail("World/visuals did not become ready: " + str(info)); return
	camera = root.get_camera_3d()
	if not camera: fail("No active camera"); return
	if config.workload == "g1-dual" and camera.has_method("frame_for_count"): camera.frame_for_count(2)
	camera.set_process_unhandled_input(false)
	camera_base = camera.global_transform
	# Keep saved framing and roll. A point on its forward axis defines the orbit.
	center = camera_base.origin - camera_base.basis.z * (4.8 if config.workload == "g1-dual" else 3.2)
	var directory: String = config.fixture
	if config.mode == "prepare":
		record_fixture(directory)
		print("BENCHMARK FIXTURE READY ", directory)
		quit(); return
	fixture = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	initial = read_state(directory.path_join("state.f64"))
	var check := bridge("capture", {"model_path":str(config.output) + ".loaded.mjb"})
	if FileAccess.get_sha256(str(config.output) + ".loaded.mjb") != fixture.model_sha256:
		# Change only the dedicated test world's runtime naming after a full
		# model-array comparison, then use the identical frozen MJB on both ends.
		var previous_prefixes: Dictionary = check.models
		bridge("load_fixture", {"model_path":directory.path_join("model.mjb"), "prefixes":fixture.models})
		var controls := world.get_node_or_null("DisplayControls")
		if controls and controls.get("robot_overlays") is Dictionary:
			for robot in controls.robot_overlays:
				var label := str(robot.get_path())
				var old_prefix: String = previous_prefixes.get(label, "")
				var new_prefix: String = fixture.models.get(label, "")
				var renamed := {}
				for key in controls.robot_overlays[robot]:
					renamed[new_prefix + str(key).trim_prefix(old_prefix)] = controls.robot_overlays[robot][key]
				controls.robot_overlays[robot] = renamed
		check = bridge("capture", {"model_path":str(config.output) + ".loaded.mjb"})
		if FileAccess.get_sha256(str(config.output) + ".loaded.mjb") != fixture.model_sha256:
			fail("Loaded model differs from frozen fixture; do not compare these runs"); return
	DirAccess.remove_absolute(str(config.output) + ".loaded.mjb")
	restore()
	if config.mode == "physics":
		bridge("physics", {"state":initial, "steps":mini(1000, int(config.steps)), "tick":1.0/Engine.physics_ticks_per_second})
		var result := bridge("physics", {"state":initial, "steps":int(config.steps), "tick":1.0/Engine.physics_ticks_per_second})
		write_state(str(config.output) + ".final.f64", result.state)
		result.erase("state"); result.backend = "godot"; result.mode = "physics"; result.sim_time = world.info().time
		result.loaded_model_sha256 = fixture.model_sha256
		write_json(str(config.output) + ".json", result)
		quit(); return
	if config.profile == "common": common_visuals(check.geoms)
	else:
		# UI is excluded from both renderers' pixel workload. Its update work is
		# retained, as are the current example's hidden-collision update costs.
		for node in nodes(world):
			if node is CanvasLayer: node.visible = false
		root.physics_object_picking = original_picking
		root.warp_mouse(Vector2(config.width / 2.0, config.height / 2.0))
	if config.mode == "static":
		# A paused MuJoCo world still receives production node callbacks. Freeze
		# those only for the pure-render case; "paused" measures that real cost.
		for node in nodes(world):
			node.set_process(false)
			node.set_physics_process(false)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(str(config.output) + ".png")
	var rows: Array[Array] = []
	var started := Time.get_ticks_usec()
	var previous := started
	var measuring := false
	if config.mode == "running": world.set_paused(false)
	while true:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := (now - started) / 1000000.0
		if not measuring and elapsed >= float(config.warmup):
			world.set_paused(true); restore()
			if config.mode == "running": world.set_paused(false)
			started = Time.get_ticks_usec(); previous = started; elapsed = 0.0; measuring = true
			bridge("metrics"); BenchmarkStats.sync_us = 0.0
			continue
		var finished: bool = measuring and elapsed >= float(config.sample)
		var metrics := bridge("metrics")
		var sync_us: float = BenchmarkStats.sync_us
		BenchmarkStats.sync_us = 0.0
		if measuring:
			var viewport := root.get_viewport_rid()
			rows.append([(now-previous)/1000.0, float(metrics.step_us)/1000.0, float(metrics.state_us)/1000.0, float(metrics.info_us)/1000.0, float(metrics.ray_us)/1000.0, metrics.ray_count, sync_us/1000.0, RenderingServer.viewport_get_measured_render_time_cpu(viewport), RenderingServer.viewport_get_measured_render_time_gpu(viewport), Performance.get_monitor(Performance.TIME_PROCESS)*1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), metrics.time, metrics.ncon])
		previous = now
		if finished: break
		orbit(elapsed)
	var actual_sample_s := (previous-started)/1000000.0
	world.set_paused(true)
	var final := bridge("state")
	write_state(str(config.output) + ".final.f64", final.state)
	var csv := FileAccess.open(str(config.output) + ".csv", FileAccess.WRITE)
	csv.store_line("frame_ms,step_ms,state_ms,info_ms,ray_ms,ray_count,sync_ms,render_cpu_ms,gpu_ms,process_ms,physics_process_ms,draw_calls,primitives,sim_time,ncon")
	for row in rows: csv.store_line(",".join(row.map(func(v): return String.num(float(v), 12))))
	var result := {"backend":"godot", "mode":config.mode, "profile":config.profile, "renderer":RenderingServer.get_video_adapter_name(), "vendor":RenderingServer.get_video_adapter_vendor(), "godot_version":Engine.get_version_info(), "mujoco_version":check.version, "mujoco_library":check.mujoco_library, "loaded_model_sha256":fixture.model_sha256, "frames":rows.size(), "sim_time":world.info().time, "simulated_s":world.info().time-initial[0], "sample_s":config.sample, "actual_sample_s":actual_sample_s, "warnings":final.warnings, "width":root.size.x, "height":root.size.y, "vsync_requested":false, "display_driver":DisplayServer.get_name(), "runtime_callbacks":config.mode!="static", "automatic_picking":root.physics_object_picking, "original_picking":original_picking, "ui":false, "gpu_timing":"RenderingServer viewport timer; zero means unavailable"}
	write_json(str(config.output) + ".json", result)
	print("BENCHMARK COMPLETE ", config.output)
	quit()
