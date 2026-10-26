extends SceneTree
const Session=preload("res://addons/godot_mujoco/map/session.gd")
const Package=preload("res://addons/godot_mujoco/map/package.gd")
var passed:=0
var failed:=0
var evidence: Dictionary={}
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(count: int) -> void:
	for i in count: await physics_frame; await process_frame
func ray(scene: Node3D,x: float,excluded: Array[RID]=[]) -> Dictionary:
	var q:=PhysicsRayQueryParameters3D.create(Vector3(x,2,0),Vector3(x,-1,0),1,excluded)
	q.collide_with_areas=false
	return scene.get_world_3d().direct_space_state.intersect_ray(q)
func add_ball(scene: Node3D,p: Vector3,radius:=.12) -> RigidBody3D:
	var b:=RigidBody3D.new(); b.position=p; b.mass=.2
	var shape:=CollisionShape3D.new(); var sphere:=SphereShape3D.new(); sphere.radius=radius; shape.shape=sphere; b.add_child(shape); scene.add_child(b)
	return b
func run() -> void:
	var started:=Time.get_ticks_usec()
	var scene=load("res://Main.tscn").instantiate()
	# Visual alpha must not remove physical SDFs from ray queries.
	for entry in scene.native_collisions: entry.snapshot.xml=entry.snapshot.xml.replace("<geom name='collision'","<geom name='collision' rgba='1 1 1 0'")
	root.add_child(scene); await ticks(3)
	check(scene.last_error.is_empty() and scene.native_rids.size()==3,"three native SDF terrain chunks load")
	if scene.native_rids.size()!=3: scene.free(); quit(1); return
	var space: RID=scene.get_world_3d().space
	PhysicsServer3D.call("scene_pause",space,true)
	var excluded: Array[RID]=[]
	for name in ["StairsBall","PitBall","RoughBall"]: excluded.append(scene.get_node(name).get_rid())
	var types: Array=[]
	for rid in scene.native_rids:
		var geometry: Array=PhysicsServer3D.call("scene_geometry",space,rid)
		types.append(geometry.map(func(g):return g.type))
		check(not geometry.is_empty() and geometry.all(func(g):return g.type==8),"actual mjModel target type is SDF 8")
	var before: Dictionary=PhysicsServer3D.call("scene_info",space)
	var pit_hit:=ray(scene,0,excluded)
	check(not pit_hit.is_empty() and absf(pit_hit.position.y+.35)<.035,"SDF ray enters depression floor rather than convex rim")
	check(not pit_hit.is_empty() and pit_hit.normal.y>.9,"SDF pit ray outward floor normal")
	check(not pit_hit.is_empty() and pit_hit.collider==scene and pit_hit.collider_id==scene.get_instance_id() and pit_hit.rid in scene.native_rids,"SDF query has actual map RID and owning node identity")
	var q:=PhysicsPointQueryParameters3D.new(); q.position=Vector3(0,0,0); q.collision_mask=1; q.collide_with_areas=false
	check(scene.get_world_3d().direct_space_state.intersect_point(q).is_empty(),"point above pit floor remains empty despite being below rim")
	q.position=Vector3(0,-.45,0)
	check(not scene.get_world_3d().direct_space_state.intersect_point(q).is_empty(),"point inside closed SDF terrain volume hits")
	var mask_query:=PhysicsRayQueryParameters3D.create(Vector3(0,2,0),Vector3(0,-1,0),0,excluded); mask_query.collide_with_areas=false
	check(scene.get_world_3d().direct_space_state.intersect_ray(mask_query).is_empty(),"zero ray mask filters map")
	if not pit_hit.is_empty():
		var removed:=excluded.duplicate(); removed.append(pit_hit.rid)
		check(ray(scene,0,removed).is_empty(),"exclude imported RID filters target")
	check(PhysicsServer3D.call("scene_info",space).time==before.time,"queries do not advance simulation time")
	var visible_state:=pit_hit.duplicate()
	scene.get_node("Visual").visible=false
	check(ray(scene,0,excluded)==visible_state,"entity visibility does not alter physical ray")
	scene.get_node("Visual").visible=true
	var extra: Array[RigidBody3D]=[]
	for i in [2,5]: extra.append(add_ball(scene,Vector3(-4.25+i*.5,2,0),.07))
	PhysicsServer3D.call("scene_pause",space,false)
	var contact_counts: Dictionary={}
	var pit_normal:=false
	var pit_contact: Dictionary={}
	for i in 600:
		await ticks(1)
		var info: Dictionary=PhysicsServer3D.call("scene_info",space)
		for index in info.contacts.size():
			var pair: Array=info.contacts[index]
			var detail: Dictionary=info.contact_details[index]
			for rid in scene.native_rids:
				if pair.has(rid) and detail.force_contact_frame[0]>0: contact_counts[str(rid.get_id())]=true
			if pair.has(scene.get_node("PitBall").get_rid()) and detail.force_contact_frame[0]>0 and absf(detail.normal.y)>.8: pit_normal=true;pit_contact=detail.duplicate(true)
	var pit_y: float=scene.get_node("PitBall").position.y
	var stairs_y: float=scene.get_node("StairsBall").position.y
	check(absf(pit_y-(-.35+.12))<.04,"falling sphere rests at pit floor plus radius, not rim plus radius")
	check(absf(stairs_y-.12)<.04,"lowest stair has independent physical support")
	check(absf(extra[0].position.y-(2*.18+.07))<.04 and absf(extra[1].position.y-(5*.18+.07))<.04,"middle and top stairs have distinct supported heights")
	check(contact_counts.size()==3 and pit_normal,"all terrain chunks produce actual positive target contacts; pit floor normal measured")
	check(PhysicsServer3D.call("scene_info",space).warning_count==0,"terrain dynamics has no MuJoCo warnings")
	evidence={"pit_center_y":pit_y,"pit_expected_y":-.23,"rim_plus_radius":.42,"stairs_y":stairs_y,"target_types":types,"positive_contact_chunks":contact_counts.size(),"pit_contact":pit_contact,"native_time":PhysicsServer3D.call("scene_info",space).time}
	scene.queue_free(); await ticks(4)
	# Explicitly labelled convex-hull control, never the example default.
	var session:=Session.new(); check(session.import_file("res://assets/terrain.obj","m","Y_UP"),"control source import")
	for mesh in session.meshes(): check(session.configure(str(session.visual.get_path_to(mesh)),{"kind":"mesh"}),"explicit convex control configuration")
	var built:=session.build_scene(); check(built.error.is_empty(),"explicit convex control scene")
	if built.error.is_empty():
		var control: Node3D=built.scene; root.add_child(control); await ticks(3)
		var b:=add_ball(control,Vector3(0,1.5,0)); await ticks(600)
		check(absf(b.position.y-.42)<.04,"labelled convex control fills pit and supports sphere at rim plus radius")
		var control_hit:=ray(control,0,[b.get_rid()])
		check(not control_hit.is_empty() and absf(control_hit.position.y-.3)<.035,"mesh ray uses actual compiled convex hull, not visual triangles")
		evidence["convex_control_center_y"]=b.position.y
		control.queue_free(); await ticks(4)
	session.close()
	var package_path:=FileAccess.get_file_as_string("res://map_package_path.txt")
	check(Package.validate(package_path).is_empty(),"standalone saved terrain package validates")
	var original:="res://assets/terrain.obj"; var offline:="res://assets/terrain.source-offline"
	check(DirAccess.rename_absolute(original,offline)==OK,"remove original terrain input before package reopen")
	var reopened=load(package_path.path_join("map.tscn")).instantiate(); root.add_child(reopened); await ticks(3)
	check(reopened.last_error.is_empty() and reopened.native_rids.size()==3,"saved SDF package reopens without original source")
	var rehit:=ray(reopened,0)
	check(not rehit.is_empty() and absf(rehit.position.y+.35)<.035,"reopened package preserves SDF depression")
	reopened.queue_free(); await ticks(4)
	check(DirAccess.rename_absolute(offline,original)==OK,"restore this fixture's generated source")
	evidence["wall_seconds"]=(Time.get_ticks_usec()-started)/1000000.0
	var result:={"passed":passed,"failed":failed,"evidence":evidence,"gui":"pending locked GTR session"}
	print("SDF_TERRAIN_RESULT ",JSON.stringify(result))
	quit(0 if failed==0 else 1)
