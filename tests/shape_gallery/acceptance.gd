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
	for i in 12:
		await physics_frame; await process_frame
		if world.command_request==0: return
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
				check(material_color(model.visuals[geom.name].material_override).is_equal_approx(colors[name]),"runtime material preserves authored RGBA "+name)
	check(actual==expected,"actual mjModel types match native primitives and convex mesh cone")
	check(model.state().joints.size()==7,"seven independent freejoint dynamic rigid bodies")
	var opened: Dictionary=model.model.open_document()
	var cone_hull:=false
	for geom in opened.document.collision_preview(.33,65):
		if geom.name=="cone_geom": cone_hull=geom.preview_kind=="compiled_convex_hull" and not geom.vertices.is_empty()
	check(cone_hull,"cone has a real compiled convex hull; no native cone or dynamic SDF")
	var before: Dictionary=model.state().joints.duplicate(true)
	var materials:= {}
	for name in model.visuals: materials[name]=model.visuals[name].material_override
	var controls=world.get_node("DisplayControls")
	check(not controls.help_panel.visible and not controls.help_button.button_pressed,"runtime help starts collapsed")
	for i in 5:
		controls.help_button.button_pressed=true
		check(controls.help_panel.visible,"help toggle opens panel")
		controls.help_panel.get_child(0).get_child(0).get_children().back().pressed.emit()
		check(not controls.help_panel.visible and not controls.help_button.button_pressed,"help close resets toggle for repeat use")
	check(model.state().joints==before,"help interactions preserve physical state")
	var window_size:=root.size
	for size in [Vector2i(1280,800),Vector2i(900,600)]:
		root.size=size; await process_frame; await process_frame
		controls.layout_chrome(); await process_frame
		var bounds: Rect2=controls.chrome.get_global_rect()
		check(bounds.position.x>=0 and bounds.end.x<=root.get_visible_rect().size.x and bounds.size.y<125,"collapsed toolbar stays compact inside window "+str(size))
		controls.set_help_visible(true); await process_frame
		check(controls.chrome.get_global_rect().end.y<=root.get_visible_rect().size.y,"expanded help fits window "+str(size))
		controls.set_help_visible(false)
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
	model.build_visuals(PhysicsServer3D.call("scene_geometry",world.space,model.model_rid),true)
	controls.apply_floor_grid()
	check(controls.grid_material==retained_material and model.visuals.values().filter(func(mesh): return mesh.material_override==retained_material).size()==1,"runtime visual rebuild reapplies cached grid only to floor")
	materials.clear()
	for name in model.visuals: materials[name]=model.visuals[name].material_override
	for visual in [true,false]:
		for collision in [true,false]:
			controls.entities.set_pressed_no_signal(visual); controls.collisions.set_pressed_no_signal(collision); controls.apply_display()
			check(model.visuals.values().all(func(mesh): return mesh.visible==visual) and controls.overlays.values().all(func(overlay): return overlay.visible==collision),"runtime independent display combination %s/%s" % [visual,collision])
			var rgba_ok:=true
			for full_name in model.visuals:
				for name in colors:
					if str(full_name).ends_with(name): rgba_ok=rgba_ok and material_color(model.visuals[full_name].material_override).is_equal_approx(colors[name])
			check(rgba_ok,"four display modes preserve actual material RGB and alpha values")
			check(model.state().joints==before and model.visuals.keys().all(func(name): return model.visuals[name].material_override==materials[name]),"display preserves physical state and original materials")
	controls.entities.set_pressed_no_signal(true); controls.collisions.set_pressed_no_signal(true); controls.apply_display()
	controls.pause_button.pressed.emit(); await command_settle(world)
	check(not world.info().paused,"compact pause button resumes actual world")
	controls.pause_button.pressed.emit(); await command_settle(world)
	check(world.info().paused,"compact pause button pauses actual world")
	controls.reset_button.pressed.emit(); await command_settle(world)
	check(model.state().joints==before and world.info().paused,"compact reset restores initial state and retains pause")
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
		check(contacts.has(name+"_geom"),name+" has positive contact force against the common floor")
		var body: Dictionary=model.state().bodies[name]
		check(body.transform.is_finite() and body.transform.origin.y>-.1 and body.transform.origin.y<1.5,name+" settles above floor after actual drop")
		var spread:=0.0
		for sample in stable_samples: spread=maxf(spread,body.transform.origin.distance_to(sample[name].transform.origin))
		check(spread<.05,name+" final half-second translation remains stable")
	check(body_pair,"positive box/probe contact proves object-object collision in the same space")
	check(world.info().warning_count==0,"no MuJoCo instability warnings")
	# Non-unit alpha guards all four channels through the actual shared backend API.
	var tint={"format":1,"xml":"<mujoco><compiler angle='radian'/><option timestep='0.002' gravity='0 0 -9.81' integrator='implicitfast' solver='Newton'><flag nativeccd='enable'/></option><worldbody><geom name='rgba_probe' type='sphere' size='.1' pos='20 0 0' rgba='.13 .27 .61 .37'/></worldbody></mujoco>","source":"","state":{}}
	var tint_rid: RID=PhysicsServer3D.call("scene_load_model",world.space,tint,"","rgba_test",Transform3D.IDENTITY)
	check(tint_rid.is_valid(),"RGBA probe loads into real shared runtime: "+str(world.info().last_error))
	if tint_rid.is_valid():
		var tint_geoms: Array=PhysicsServer3D.call("scene_geometry",world.space,tint_rid)
		check(tint_geoms.size()==1 and tint_geoms[0].has("color") and tint_geoms[0].color.is_equal_approx(Color(.13,.27,.61,.37)),"backend preserves non-unit alpha and all RGB channels")
		var tint_visual=preload("res://addons/godot_mujoco/model/model_visual.gd").create(tint_geoms[0])
		check(tint_visual.material_override.albedo_color.is_equal_approx(Color(.13,.27,.61,.37)),"runtime visual receives non-unit RGBA without fallback")
		tint_visual.free(); PhysicsServer3D.free_rid(tint_rid)
	controls.set_help_visible(true)
	world.free(); await process_frame
	world=scene.instantiate(); world.start_paused=true; root.add_child(world); await process_frame
	check(not world.get_node("DisplayControls").help_panel.visible,"saved scene reopen defaults to hidden help")
	check(world.get_node("Model").state().joints==before,"saved scene reopen reproduces initial state")
	world.free(); await process_frame
	print("SHAPE_GALLERY_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"floor_contacts":contacts,"scope":"actual shared MuJoCo physics; GUI acceptance separate"}))
	quit(0 if failed==0 else 1)
