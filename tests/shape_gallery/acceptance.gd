extends SceneTree
var passed:=0
var failed:=0
var contacts: Dictionary={}
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func material_color(material: Material) -> Color:
	return material.get_shader_parameter("base_color") if material is ShaderMaterial else material.albedo_color
func command_settle(world) -> void:
	var deadline := Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await physics_frame; await process_frame
		if world.author_started and world.command_request==0: return
func viewer_command(viewer: Node, command: Dictionary) -> void:
	check(viewer.request_action(command),"queue shared viewer "+str(command.action))
	var deadline := Time.get_ticks_msec()+10000
	while viewer.command_request!=0 and Time.get_ticks_msec()<deadline: await process_frame
	check(viewer.command_request==0 and viewer.last_error.is_empty(),"shared viewer completes "+str(command.action))
	await process_frame; await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: PackedScene=load("res://Main.tscn")
	var world=scene.instantiate(); world.start_paused=true; root.add_child(world)
	await process_frame
	await command_settle(world)
	var model=world.get_node("Model")
	check(world.ready_for_models and model.model_rid.is_valid(),"saved scene loads one shared runtime world and model")
	if not model.model_rid.is_valid(): printerr(model.last_error); quit(1); return
	var expected: Dictionary={"sphere_geom":2,"box_geom":6,"cylinder_geom":5,"cone_geom":7,"capsule_geom":3,"ellipsoid_geom":4,"probe_geom":2,"floor_geom":6}
	var colors: Dictionary={"sphere_geom":Color(.9,.25,.18,1),"box_geom":Color(.2,.55,.95,1),"cylinder_geom":Color(.25,.8,.4,1),"cone_geom":Color(.95,.6,.12,1),"capsule_geom":Color(.65,.3,.9,1),"ellipsoid_geom":Color(.15,.8,.8,1),"probe_geom":Color(1,.8,.65,1),"floor_geom":Color(.25,.28,.32,1)}
	var actual:= {}
	for geom in PhysicsServer3D.call("scene_geometry",world.space,model.model_rid):
		for name in expected:
			if str(geom.name).ends_with(name):
				actual[name]=geom.type
				check(geom.has("color") and geom.color.is_equal_approx(colors[name]),"actual runtime geometry preserves MJCF RGBA "+name)
				check(material_color(model.visuals[name].material_override).is_equal_approx(colors[name]),"runtime material preserves authored RGBA "+name)
	check(actual==expected,"actual mjModel types match native primitives and convex mesh cone")
	var canonical: bool=model.state().joints.size()==7
	check(model.state().joints.size()==model.design.entities().filter(func(entity):return entity.kind=="joint").size(),"current saved authored joints are all simulated")
	var opened: Dictionary={"error":"", "document":ClassDB.instantiate("MjEditorDocument")}
	opened.document.compile_author(model.design.worker_xml(),model.design.native_initial_pose(),model.design.native_mesh_options())
	var cone_hull:=false
	for geom in opened.document.collision_preview(.33,65):
		if geom.name=="cone_geom": cone_hull=geom.preview_kind=="compiled_convex_hull" and not geom.vertices.is_empty()
	check(cone_hull,"cone has a real compiled convex hull; no native cone or dynamic SDF")
	var before: Dictionary=model.state().joints.duplicate(true)
	var materials:= {}
	for name in model.visuals: materials[name]=model.visuals[name].material_override
	var controls=world.get_node("DisplayControls")
	var viewer: Node=world.runtime_viewer
	while viewer.frame.is_empty(): await process_frame
	while not viewer.preference_queue.is_empty() or not viewer.pending.is_empty(): await process_frame
	check(not viewer.windows.help.visible and not viewer.controls.visible,"runtime help and F11 controls start collapsed")
	for i in 5:
		viewer.toggle_auxiliary("help")
		check(viewer.windows.help.visible,"F1 action opens shared help")
		check(viewer.windows.help is Control and not viewer.windows.help is Window,"F1 is the original scene overlay")
		viewer.toggle_auxiliary("help")
		check(not viewer.windows.help.visible,"F1 action closes original help for repeat use")
	check(model.state().joints==before,"help interactions preserve physical state")
	var window_size:=root.size
	for size in [Vector2i(1280,800),Vector2i(900,600)]:
		root.size=size; await process_frame; await process_frame
		viewer.set_controls_visible(true); await process_frame
		var bounds := Rect2(Vector2(viewer.controls.position),Vector2(viewer.controls.size))
		check(bounds.position.x>=0 and bounds.end.x<=root.get_visible_rect().size.x and bounds.end.y<=root.get_visible_rect().size.y,"F11 floating controls fit window "+str(size))
		viewer.set_controls_visible(false)
		check(not viewer.controls.visible,"F11 controls close in resized window")
	root.size=window_size; await process_frame
	var floor: MeshInstance3D
	for name in model.visuals:
		if str(name).ends_with("floor_geom"): floor=model.visuals[name]
	var floor_mesh:=floor.mesh
	var floor_transform:=floor.transform
	var original_count: int=model.visuals.size()
	check(floor.material_override is ShaderMaterial and floor.material_override.shader==load("res://floor_grid.gdshader"),"existing floor uses example-only grid shader")
	check(is_equal_approx(controls.grid_material.get_shader_parameter("spacing_m"),1.0) and is_equal_approx(controls.grid_material.get_shader_parameter("line_width_m"),.015),"grid defaults to one world metre with 15 mm lines")
	var shader_code: String=controls.grid_material.shader.code
	check(shader_code.contains("MODEL_MATRIX * vec4(VERTEX, 1.0)") and shader_code.contains("world_position.xz / spacing_m") and shader_code.contains("fwidth(world_position.xz)") and shader_code.contains("step(0.9, world_normal.y)"),"grid uses world metric XZ, antialiasing and top-face gating")
	controls.grid_spacing_m=2.0; controls.apply_floor_grid()
	check(is_equal_approx(controls.grid_material.get_shader_parameter("spacing_m"),2.0) and floor.mesh==floor_mesh and floor.transform==floor_transform and model.visuals.size()==original_count and model.state().joints==before,"configurable grid spacing does not alter geometry or physics")
	controls.grid_spacing_m=1.0; controls.apply_floor_grid()
	var retained_material=controls.grid_material
	model.author_scene.geometry_queue=model.design.cached_geometry.duplicate(true)
	while not model.author_scene.geometry_queue.is_empty(): model.author_scene.build_geometry_step()
	controls.apply_floor_grid()
	check(controls.grid_material==retained_material and model.visuals.values().filter(func(mesh): return mesh.material_override==retained_material).size()==1,"runtime visual rebuild reapplies cached grid only to floor")
	materials.clear()
	for name in model.visuals: materials[name]=model.visuals[name].material_override
	viewer.cache_geometry() # Rebind mesh visibility after the explicit visual rebuild above.
	for visual in [true,false]:
		for diagnostic in [true,false]:
			await viewer_command(viewer,{"action":"group","name":"geom","id":0,"value":visual})
			await viewer_command(viewer,{"action":"vis","id":2,"value":diagnostic})
			check(model.visuals.values().all(func(mesh): return mesh.visible==visual) and bool(viewer.frame.settings.vis[2])==diagnostic,"runtime group and official diagnostics %s/%s" % [visual,diagnostic])
			var rgba_ok:=true
			for full_name in model.visuals:
				for name in colors:
					if str(full_name).ends_with(name): rgba_ok=rgba_ok and material_color(model.visuals[full_name].material_override).is_equal_approx(colors[name])
			check(rgba_ok,"four display modes preserve actual material RGB and alpha values")
			check(model.state().joints==before and model.visuals.keys().all(func(name): return model.visuals[name].material_override==materials[name]),"display preserves physical state and original materials")
	await viewer_command(viewer,{"action":"group","name":"geom","id":0,"value":true})
	await viewer_command(viewer,{"action":"pause"})
	check(not world.info().paused,"shared pause action resumes actual world")
	await viewer_command(viewer,{"action":"pause"})
	check(world.info().paused,"shared pause action pauses actual world")
	await viewer_command(viewer,{"action":"reset_initial"})
	check(model.state().joints==before and world.info().paused,"initial reset restores design state and retains pause")
	world.set_paused(false)
	var body_pair:=false
	var stable_samples:=[]
	for i in 600:
		await physics_frame
		for contact in world.info().contact_details:
			if contact.force_contact_frame[0]<=0: continue
			var names: Array=contact.geoms.map(func(name): return str(name))
			if names.any(func(name): return name.ends_with("floor_geom")):
				for name in expected:
					if names.any(func(full): return full.ends_with(name)): contacts[name]=true
			if names.any(func(name): return name.ends_with("probe_geom")) and names.any(func(name): return name.ends_with("box_geom")): body_pair=true
		if i>=570: stable_samples.append(model.state().bodies)
	world.set_paused(true)
	for name in ["sphere","box","cylinder","cone","capsule","ellipsoid"]:
		if not canonical:
			check(model.state().bodies[name].transform.is_finite(),name+" remains finite in the locally edited saved design")
			continue
		check(contacts.has(name+"_geom"),name+" has positive contact force against the common floor")
		var body: Dictionary=model.state().bodies[name]
		check(body.transform.is_finite() and body.transform.origin.y>-.1 and body.transform.origin.y<1.5,name+" settles above floor after actual drop")
		var spread:=0.0
		for sample in stable_samples: spread=maxf(spread,body.transform.origin.distance_to(sample[name].transform.origin))
		check(spread<.05,name+" final half-second translation remains stable")
	if canonical: check(body_pair,"positive box/probe contact proves object-object collision in the same space")
	check(world.info().warning_count==0,"no MuJoCo instability warnings")
	# Non-unit alpha guards all four channels through the actual shared backend API.
	var tint={"format":1,"xml":"<mujoco><compiler angle='radian'/><option timestep='0.002' gravity='0 0 -9.81' integrator='implicitfast' solver='Newton'><flag nativeccd='enable'/></option><worldbody><geom name='rgba_probe' type='sphere' size='.1' pos='20 0 0' rgba='.13 .27 .61 .37'/></worldbody></mujoco>","source":"","state":{}}
	var tint_doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	check(tint_doc.compile_author(tint.xml),"RGBA probe compiles through the real author backend")
	if tint_doc.get_error().is_empty():
		var tint_geoms: Array=tint_doc.geometry()
		check(tint_geoms.size()==1 and tint_geoms[0].has("color") and tint_geoms[0].color.is_equal_approx(Color(.13,.27,.61,.37)),"backend preserves non-unit alpha and all RGB channels")
		var tint_visual=preload("res://addons/godot_mujoco/model/model_visual.gd").create(tint_geoms[0])
		check(tint_visual.material_override.albedo_color.is_equal_approx(Color(.13,.27,.61,.37)),"runtime visual receives non-unit RGBA without fallback")
		tint_visual.free()
	viewer.toggle_auxiliary("help")
	world.free(); await process_frame
	world=scene.instantiate(); world.start_paused=true; root.add_child(world); await command_settle(world)
	check(not world.runtime_viewer.windows.help.visible and not world.runtime_viewer.controls.visible,"saved scene reopen defaults to hidden help/controls")
	check(world.get_node("Model").state().joints==before,"saved scene reopen reproduces initial state")
	world.free(); await process_frame
	print("SHAPE_GALLERY_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"floor_contacts":contacts,"scope":"actual shared MuJoCo physics; GUI acceptance separate"}))
	quit(0 if failed==0 else 1)
