extends SceneTree
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Native = preload("res://addons/godot_mujoco/map/native_collision.gd")
var passed := 0
var failed := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int):
	for i in n: await physics_frame; await process_frame
func find_button(node: Node, title: String) -> Button:
	if node is Button and node.text==title: return node
	for child in node.get_children():
		var found := find_button(child,title)
		if found: return found
	return null
func run():
	var session := Session.new(); check(session.import_file("res://fixtures/room.obj","m","Y_UP"),"extended import")
	var mesh: MeshInstance3D=session.meshes()[0]; var path := str(session.visual.get_path_to(mesh))
	for mode in ["mesh","sdf"]:
		var built := Native.build(mesh,session.visual,{"kind":mode})
		check(built.error.is_empty(),"preview compile "+mode)
		var preview: Array=built.document.collision_preview(.375,65)
		var geo: Dictionary=preview[0]
		if mode=="mesh":
			var hit := false
			for i in range(0,geo.vertices.size(),3):
				if Geometry3D.ray_intersects_triangle(Vector3(0,1,-4),Vector3(0,0,1),geo.transform*geo.vertices[i],geo.transform*geo.vertices[i+1],geo.transform*geo.vertices[i+2])!=null: hit=true
			check(geo.preview_kind=="compiled_convex_hull" and hit,"compiled hull preview closes door")
		else:
			var door := 0; var wall := 0; var door_distance := INF; var wall_distance := INF
			for i in geo.slice_points.size():
				var p: Vector3=geo.slice_points[i]
				var a := Vector2(p.x,p.z).distance_squared_to(Vector2(0,-3)); var b := Vector2(p.x,p.z).distance_squared_to(Vector2(2,-3))
				if a<door_distance: door_distance=a; door=i
				if b<wall_distance: wall_distance=b; wall=i
			check(geo.preview_kind=="native_sdf_distance_slice" and geo.slice_distances[door]>.3 and geo.slice_distances[wall]<0 and geo.slice_contour.size()>0,"native distance slice distinguishes wall/door")
			check(built.document.collision_preview(.3,10000).is_empty(),"distance slice bounded")
		var overlay := preload("res://addons/godot_mujoco/map/collision_preview.gd").create(preview,built.pose)
		check(overlay.get_child_count()>0,"preview drawable "+mode); overlay.free()
	check(session.configure(path,{"kind":"sdf"}),"pair room SDF")
	for kind in ["box","capsule","mesh"]:
		var built := session.build_scene(); var scene: Node3D=built.scene; root.add_child(scene); await ticks(2)
		var asset := ""
		var geom := "type='box' size='.2 .2 .2'" if kind=="box" else "type='capsule' size='.15 .15'"
		if kind=="mesh":
			asset="<asset><mesh name='cube' vertex='-.2 -.2 -.2 .2 -.2 -.2 .2 .2 -.2 -.2 .2 -.2 -.2 -.2 .2 .2 -.2 .2 .2 .2 .2 -.2 .2 .2'/></asset>"
			geom="type='mesh' mesh='cube'"
		var bodies := ""
		for x in [0,2]: bodies += "<body name='probe%d' gravcomp='1' pos='%d 4 1'><freejoint name='free%d'/><geom name='probe_geom%d' %s/></body>" % [x,x,x,x,geom]
		var doc := MjEditorDocument.new()
		check(doc.restore({"format":1,"xml":"<mujoco><option timestep='.002'/>"+asset+"<worldbody>"+bodies+"</worldbody></mujoco>","state":{},"source":""}),"pair probes compile "+kind)
		var snapshot: Dictionary=doc.snapshot(); snapshot.state.erase("integration"); snapshot.state.qvel=[0,-2,0,0,0,0,0,-2,0,0,0,0]
		var space := scene.get_world_3d().space; PhysicsServer3D.call("scene_pause",space,true)
		var id: RID=PhysicsServer3D.call("scene_load_model",space,snapshot,"","pair_"+kind,Transform3D.IDENTITY)
		check(id.is_valid(),"pair actual load "+kind); PhysicsServer3D.call("scene_pause",space,false)
		var force := false; var normal := false
		for i in 75:
			await ticks(1)
			for contact in PhysicsServer3D.call("scene_info",space).contact_details:
				if contact.geoms.any(func(n):return str(n).ends_with("_collision")) and contact.geoms.any(func(n):return str(n).ends_with("_probe_geom2")):
					force=force or contact.force_contact_frame[0]>0; normal=normal or absf(contact.normal.z)>.8
		var state: Dictionary=PhysicsServer3D.call("scene_state",space,id)
		check(force and normal,"SDF target normal/force "+kind)
		check(state.bodies.probe0.transform.origin.z > -2.5 and state.bodies.probe2.transform.origin.z < -3.1,"SDF hole and wall "+kind)
		PhysicsServer3D.free_rid(id); scene.queue_free(); await ticks(3)
	session.close()
	var panel := preload("res://addons/mujoco_editor/map_panel.gd").new(); root.add_child(panel); await process_frame
	panel.path_field.text="res://fixtures/box.obj"; panel.unit.select(1); panel.axes.select(0); check(panel.import_source(false),"real UI import")
	panel.selected=str(panel.session.visual.get_path_to(panel.session.meshes()[0]))
	for i in panel.strategy.item_count:
		if panel.strategy.get_item_text(i)=="sdf": panel.strategy.select(i)
	panel.advanced.text='{"condim":4,"friction":[1.4,0.02,0.001],"priority":2}'
	find_button(panel,"验证并应用碰撞草稿").pressed.emit()
	check(panel.session.error.is_empty() and panel.session.specs[panel.selected].contact.condim is int and panel.session.specs[panel.selected].contact.priority is int,"real contact JSON UI normalized")
	var contact_built: Dictionary=panel.session.build_scene(); var contact_scene: Node3D=contact_built.scene; root.add_child(contact_scene); await ticks(2)
	var contact_geoms: Array=PhysicsServer3D.call("scene_geometry",contact_scene.get_world_3d().space,contact_scene.native_rids[0])
	check(contact_geoms[0].condim==4 and contact_geoms[0].priority==2 and absf(contact_geoms[0].friction[0]-1.4)<.00001,"real contact JSON UI final geom")
	contact_scene.queue_free(); await ticks(2)
	for field in ["condim","priority","layer","mask"]:
		for bad in [1.5,NAN,INF,"4",-2147483649 if field=="priority" else -1,2147483648]:
			var spec: Dictionary={"contact":{field:bad}} if field in ["condim","priority"] else {field:bad}
			check(not Native.contact_attributes(spec).error.is_empty(),"integer reject %s %s" % [field,str(bad)])
	check(Native.contact_attributes(JSON.parse_string('{"layer":2147483647,"mask":0,"contact":{"priority":2147483647,"condim":6}}')).error.is_empty(),"JSON signed filter and priority boundary")
	for priority_text in ["-2147483648","-1","2147483647"]:
		panel.advanced.text='{"condim":4,"priority":'+priority_text+'}'
		find_button(panel,"验证并应用碰撞草稿").pressed.emit()
		check(panel.session.error.is_empty() and panel.session.specs[panel.selected].contact.priority==int(priority_text),"JSON signed priority accepted "+priority_text)
		contact_built=panel.session.build_scene(); contact_scene=contact_built.scene; root.add_child(contact_scene); await ticks(2)
		contact_geoms=PhysicsServer3D.call("scene_geometry",contact_scene.get_world_3d().space,contact_scene.native_rids[0])
		check(contact_geoms[0].priority==int(priority_text),"final geom signed priority "+priority_text)
		contact_scene.queue_free(); await ticks(2)
	var retained: Dictionary=panel.session.specs.duplicate(true)
	for invalid in ['{"condim":4.5}','{"priority":"2"}','{"priority":1e999}','{"condim":2}','{"priority":2147483648}','{"priority":-2147483649}']:
		panel.advanced.text=invalid; find_button(panel,"验证并应用碰撞草稿").pressed.emit()
		check(not panel.session.error.is_empty() and panel.session.specs==retained,"contact JSON UI atomic rejection "+invalid)
	var apply := find_button(panel,"应用世界设置")
	panel.world_options.text='{"iterations":100,"noslip_iterations":0,"ccd_iterations":50,"sdf_iterations":10,"sdf_initpoints":40,"solver":"CG"}'
	apply.pressed.emit()
	check(panel.session.error.is_empty() and panel.session.world_settings.iterations is int and panel.session.world_settings.noslip_iterations==0,"real JSON UI integer normalization")
	var previous: Dictionary=panel.session.world_settings.duplicate(true)
	for invalid in ['{"iterations":1.5}','{"iterations":"100"}','{"noslip_iterations":-1}','{"iterations":1e999}']:
		panel.world_options.text=invalid; apply.pressed.emit(); check(not panel.session.error.is_empty() and panel.session.world_settings==previous,"real JSON rejection "+invalid)
	var built: Dictionary=panel.session.build_scene(); var scene: Node3D=built.scene; root.add_child(scene); await ticks(2)
	var opt: Dictionary=PhysicsServer3D.call("scene_info",scene.get_world_3d().space).runtime_options
	check(opt.iterations==100 and opt.noslip_iterations==0 and opt.sdf_initpoints==40 and opt.solver==1,"JSON UI actual mjModel.opt")
	scene.queue_free(); await ticks(2)
	panel.world_options.text='{"iterations":0,"tolerance":0,"noslip_iterations":0,"noslip_tolerance":0}'; apply.pressed.emit()
	check(panel.session.error.is_empty(),"native zero semantics accepted via JSON UI")
	built=panel.session.build_scene(); scene=built.scene; root.add_child(scene); await ticks(2)
	opt=PhysicsServer3D.call("scene_info",scene.get_world_3d().space).runtime_options
	check(opt.iterations==0 and opt.tolerance==0 and opt.noslip_iterations==0 and opt.noslip_tolerance==0,"native zero semantics actual mjModel.opt")
	scene.queue_free(); await ticks(2)
	panel.shutdown(); panel.queue_free(); await process_frame
	print("NATIVE_EXTENDED_RESULT ",JSON.stringify({"passed":passed,"failed":failed})); quit(0 if failed==0 else 1)
