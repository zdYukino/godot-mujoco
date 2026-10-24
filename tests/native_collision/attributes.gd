extends SceneTree
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var passed:=0
var failed:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int):
	for i in n: await physics_frame; await process_frame
func drop(scene: Node3D) -> RigidBody3D:
	var ball:=RigidBody3D.new(); ball.position=Vector3(0,2,0)
	var shape:=CollisionShape3D.new(); shape.shape=SphereShape3D.new(); shape.shape.radius=.2; ball.add_child(shape); scene.add_child(ball); return ball
func material_contact(scene: Node3D, friction: float) -> bool:
	var found:=false
	for i in 80:
		await ticks(1)
		for contact in PhysicsServer3D.call("scene_info",scene.get_world_3d().space).contact_details:
			if contact.geoms.any(func(n):return str(n).ends_with("_collision")) and contact.force_contact_frame[0]>0 and absf(contact.friction-friction)<.00001: found=true
	return found
func run():
	var session:=Session.new(); check(session.import_file("res://fixtures/box.obj","m","Y_UP"),"attribute import")
	var mesh: MeshInstance3D=session.meshes()[0]; var path:=str(session.visual.get_path_to(mesh))
	for mode in ["box","sphere","capsule","cylinder"]:
		mesh.scale=Vector3(1,2,1) if mode=="capsule" else Vector3.ONE
		check(session.configure(path,JSON.parse_string(JSON.stringify({"kind":mode,"native_contact":true,"contact":{"friction":[1.6,.03,.002],"priority":3,"condim":4,"solmix":.8,"solref":[.02,1],"solimp":[.9,.95,.001,.5,2],"margin":0,"gap":0}}))),"explicit native material "+mode+" "+session.error)
		var built:=session.build_scene(); check(built.error.is_empty(),"native material scene "+mode)
		if not built.error.is_empty(): continue
		var scene: Node3D=built.scene; root.add_child(scene); await ticks(2); drop(scene)
		var geoms: Array=PhysicsServer3D.call("scene_geometry",scene.get_world_3d().space,scene.native_rids[0])
		check(geoms.size()==1 and geoms[0].type=={"sphere":2,"capsule":3,"cylinder":5,"box":6}[mode] and geoms[0].condim==4 and geoms[0].priority==3 and absf(geoms[0].friction[0]-1.6)<.00001 and absf(geoms[0].solmix-.8)<.00001,"final mjModel geom native parameters "+mode)
		check(await material_contact(scene,1.6),"actual native friction >1 "+mode)
		scene.queue_free(); await ticks(2)
	mesh.scale=Vector3.ONE
	check(session.configure(path,{"kind":"box","native_contact":true,"contact":{"friction":[.4,.01,.001],"priority":0,"solmix":3,"solref":[.04,1]}}),"equal priority mixing configuration")
	var mixed:=session.build_scene(); var mixed_scene: Node3D=mixed.scene; root.add_child(mixed_scene); await ticks(2); drop(mixed_scene)
	var mix_ok:=false
	for i in 80:
		await ticks(1)
		for contact in PhysicsServer3D.call("scene_info",mixed_scene.get_world_3d().space).contact_details:
			if contact.geoms.any(func(n):return str(n).ends_with("_collision")) and contact.force_contact_frame[0]>0:
				mix_ok=mix_ok or absf(contact.solref[0]-.035)<.00001
	check(mix_ok,"actual solmix weighted contact solref")
	mixed_scene.queue_free(); await ticks(2)
	var old:=session.specs.duplicate(true); mesh.scale=Vector3(1,1,.005)
	check(not session.configure(path,{"kind":"sdf"}) and session.specs==old,"thin component rejects without fallback")
	mesh.scale=Vector3.ONE
	var original:=mesh.mesh; var faces:=original.get_faces()
	for i in faces.size():
		if faces[i].y>0: faces[i]=Vector3(-faces[i].x,faces[i].y,-faces[i].z)
	var arrays:=[]; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=faces
	var twisted:=ArrayMesh.new(); twisted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.mesh=twisted
	check(not session.configure(path,{"kind":"sdf"}) and session.specs==old,"self folded closed shell rejects")
	mesh.mesh=original
	check(session.configure(path,{"kind":"box","native_contact":true,"contact":{"friction":[1.6,.03,.002],"priority":3}}),"override base")
	var value: Dictionary=JSON.parse_string('{"override":true,"o_friction":[0.3,0.3,0.02,0.001,0.001],"o_solref":[0.02,1],"o_solimp":[0.9,0.95,0.001,0.5,2],"o_margin":0,"iterations":100,"noslip_iterations":0}')
	check(session.configure_world(value),"contact override JSON")
	var built:=session.build_scene(); var scene: Node3D=built.scene; root.add_child(scene); await ticks(2); drop(scene)
	check(await material_contact(scene,.3),"world override actual contact wins")
	scene.queue_free(); await ticks(2)
	var packed:=Package.pack(session,"res://attribute_packages"); check(packed.error.is_empty(),"native attribute package")
	if packed.error.is_empty():
		var f:=FileAccess.open("res://attribute_path.txt",FileAccess.WRITE); f.store_string(packed.path); f.close()
	session.close(); session=Session.new()
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/ramp.height.json"))
	check(session.import_height("res://fixtures/ramp.raw",contract),"heightfield input")
	var design: Dictionary=session.terrains[0]
	var height_native:=Session.Native.build_height(design,{})
	var geometry: Dictionary=height_native.document.collision_preview(.33,65)[0]
	var expected_faces: PackedVector3Array=design.grid.mesh().get_faces(); var matches:=true
	for point in expected_faces:
		var nearest:=INF
		for vertex in geometry.vertices: nearest=minf(nearest,point.distance_to(geometry.transform*vertex))
		matches=matches and nearest<.00001
	check(matches,"compiled hfield preview matches height contract boundary")
	design.grid.heights.fill(0)
	check(session.configure_terrain_native(design.name,JSON.parse_string('{"friction":[1.8,0.04,0.003],"priority":3,"condim":4}')),"heightfield native attributes "+session.error)
	built=session.build_scene(); check(built.error.is_empty(),"heightfield native build "+built.error)
	if built.error.is_empty():
		scene=built.scene; root.add_child(scene); await ticks(2); drop(scene)
		check(scene.native_rids.size()==1 and scene.last_error.is_empty(),"heightfield actual native load")
		check(await material_contact(scene,1.8),"heightfield actual three-friction priority")
		scene.queue_free(); await ticks(2)
	var height_package:=Package.pack(session,"res://height_attribute_packages"); check(height_package.error.is_empty(),"height native package")
	if height_package.error.is_empty():
		var file:=FileAccess.open("res://height_attribute_path.txt",FileAccess.WRITE); file.store_string(height_package.path); file.close()
	session.close()
	session=Session.new(); check(session.import_file("res://fixtures/box.obj","m","Y_UP"),"relations input")
	mesh=session.meshes()[0]; path=str(session.visual.get_path_to(mesh))
	var other: MeshInstance3D=mesh.duplicate(); other.name="Other"; other.position.x=.6; mesh.get_parent().add_child(other)
	var other_path:=str(session.visual.get_path_to(other))
	check(session.configure(path,{"kind":"sphere","native_contact":true}) and session.configure(other_path,{"kind":"sphere","native_contact":true}),"two relation endpoints")
	check(session.configure_relations(JSON.parse_string(JSON.stringify({"pairs":[{"first":path,"second":other_path,"condim":4,"friction":[.7,.7,.02,.001,.001]}]}))),"explicit pair compilation "+session.error)
	built=session.build_scene(); check(built.error.is_empty(),"pair collection build "+built.error)
	if built.error.is_empty():
		scene=built.scene; root.add_child(scene); await ticks(3)
		var info: Dictionary=PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
		var pair_contact:=false
		for contact in info.contact_details:
			if contact.geoms.all(func(n):return str(n).contains("collision_")) and contact.condim==4 and absf(contact.friction-.7)<.00001: pair_contact=true
		check(info.npair==1 and pair_contact,"explicit pair actual contact bypasses welded-static filter")
		scene.queue_free(); await ticks(2)
	check(session.contact_relations.pairs[0].condim is int,"pair JSON canonical integer persisted")
	var previous:=session.contact_relations.duplicate(true)
	for invalid in [3.9,2,-1,2147483648,"4",true,NAN,INF]:
		var relation_value: Dictionary={"pairs":[{"first":path,"second":other_path,"condim":invalid}]}
		if typeof(invalid)!=TYPE_FLOAT or is_finite(invalid): relation_value=JSON.parse_string(JSON.stringify(relation_value))
		check(not session.configure_relations(relation_value) and session.contact_relations==previous,"pair JSON invalid integer atomic "+str(invalid))
	for invalid in [{"excludes":[{"first":0,"second":other_path}]},{"excludes":[{"first":path,"second":other_path,"condim":4}]}]:
		check(not session.configure_relations(JSON.parse_string(JSON.stringify(invalid))) and session.contact_relations==previous,"exclude rejects numeric index/unsupported fields")
	check(not session.configure_relations({"pairs":[{"first":"missing","second":path}]}) and session.contact_relations==previous,"invalid endpoint rollback")
	check(session.configure_relations(JSON.parse_string(JSON.stringify({"excludes":[{"first":path,"second":other_path}]}))),"exclude configuration")
	built=session.build_scene()
	if built.error.is_empty():
		scene=built.scene; root.add_child(scene); await ticks(3)
		var info: Dictionary=PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
		check(info.nexclude==1 and info.npair==0 and info.ncon==0,"exclude actual model and no contacts")
		scene.queue_free(); await ticks(2)
	session.history.undo(); check(session.contact_relations==previous,"relations Undo")
	var pair_package:=Package.pack(session,"res://pair_packages"); check(pair_package.error.is_empty(),"pair package")
	if pair_package.error.is_empty():
		var file:=FileAccess.open("res://pair_path.txt",FileAccess.WRITE); file.store_string(pair_package.path); file.close()
	session.close()
	print("NATIVE_ATTRIBUTES_RESULT ",JSON.stringify({"passed":passed,"failed":failed})); quit(0 if failed==0 else 1)
