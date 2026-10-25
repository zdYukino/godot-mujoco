extends SceneTree
var passed:=0
var failed:=0
var contacts: Dictionary={}
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene: PackedScene=load("res://Main.tscn")
	var world=scene.instantiate(); world.start_paused=true; root.add_child(world)
	await process_frame
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
				check(model.visuals[geom.name].material_override.albedo_color.is_equal_approx(colors[name]),"runtime material preserves authored RGBA "+name)
	check(actual==expected,"actual mjModel types match native primitives and convex mesh cone")
	check(model.state().joints.size()==7,"seven independent freejoint dynamic rigid bodies")
	var opened: Dictionary=model.model.open_document()
	var cone_hull:=false
	for geom in opened.document.collision_preview(.33,65):
		if geom.name=="cone_geom": cone_hull=geom.preview_kind=="compiled_convex_hull" and not geom.vertices.is_empty()
	check(cone_hull,"cone has a real compiled convex hull; no native cone or dynamic SDF")
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
	var before: Dictionary=model.state().joints.duplicate(true)
	var materials:= {}
	for name in model.visuals: materials[name]=model.visuals[name].material_override
	var controls=world.get_node("DisplayControls")
	for visual in [true,false]:
		for collision in [true,false]:
			controls.entities.set_pressed_no_signal(visual); controls.collisions.set_pressed_no_signal(collision); controls.apply_display()
			check(model.visuals.values().all(func(mesh): return mesh.visible==visual) and controls.overlays.values().all(func(overlay): return overlay.visible==collision),"runtime independent display combination %s/%s" % [visual,collision])
			var rgba_ok:=true
			for full_name in model.visuals:
				for name in colors:
					if str(full_name).ends_with(name): rgba_ok=rgba_ok and model.visuals[full_name].material_override.albedo_color.is_equal_approx(colors[name])
			check(rgba_ok,"four display modes preserve actual material RGB and alpha values")
			check(model.state().joints==before and model.visuals.keys().all(func(name): return model.visuals[name].material_override==materials[name]),"display preserves physical state and original materials")
	controls.entities.set_pressed_no_signal(true); controls.collisions.set_pressed_no_signal(true); controls.apply_display()
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
	world.free(); await process_frame
	world=scene.instantiate(); world.start_paused=true; root.add_child(world); await process_frame
	check(world.get_node("Model").state().joints==before,"saved scene reopen reproduces initial state")
	world.free(); await process_frame
	print("SHAPE_GALLERY_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"floor_contacts":contacts,"scope":"actual shared MuJoCo physics; GUI acceptance separate"}))
	quit(0 if failed==0 else 1)
