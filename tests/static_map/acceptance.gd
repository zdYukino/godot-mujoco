extends SceneTree
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Importer = preload("res://addons/godot_mujoco/map/importer.gd")
const Collision = preload("res://addons/godot_mujoco/map/collision.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
const Watch = preload("res://addons/godot_mujoco/map/source_watch.gd")
const Height = preload("res://addons/godot_mujoco/map/height_import.gd")
var passed := 0
var failed := 0
var scene: Node3D
var output := {}
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int):
	for i in n: await physics_frame; await process_frame
func ray(from: Vector3, to: Vector3, mask_value := 1) -> Dictionary:
	return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,mask_value))
func write(path: String, text: String):
	var f := FileAccess.open(path,FileAccess.WRITE); f.store_string(text); f.close()
func mesh_path(session) -> String: return str(session.visual.get_path_to(session.meshes()[0]))
func boxes(key: String) -> Array:
	var values: Array = JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/parts.json"))[key]; var result := []
	for v in values: result.append({"center":Vector3(v.center[0],v.center[1],v.center[2]),"size":Vector3(v.size[0],v.size[1],v.size[2])})
	return result
func ball(position_value: Vector3, radius := .2) -> RigidBody3D:
	var b := RigidBody3D.new(); b.position = position_value; b.gravity_scale = 0; b.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE; b.linear_damp = 0
	var c := CollisionShape3D.new(); c.shape = SphereShape3D.new(); c.shape.radius = radius; b.add_child(c); scene.add_child(b); return b
func run():
	scene = preload("res://addons/godot_mujoco/map/map_root.gd").new(); root.add_child(scene)
	var session := Session.new()
	check(not session.import_file("res://fixtures/box.obj","","Y_UP"),"P0 unknown units rejected")
	for file in ["box.obj","box.glb","box_binary.stl"]:
		check(session.import_file("res://fixtures/"+file,"m","Y_UP"),"P1 import "+file+" "+session.error)
		check(session.bounds().size.distance_to(Vector3.ONE)<.00001,"P0 1m calibration "+file)
	check(session.import_file("res://fixtures/box.stl","mm","Z_UP"),"P1 ASCII STL adapter")
	check(session.bounds().size.distance_to(Vector3.ONE)<.00001,"P0 mm STL converted to metres")
	check(session.import_file("res://fixtures/box_tabs_crlf.stl","mm","Y_UP") and session.bounds().size.distance_to(Vector3.ONE)<.00001,"P1 ASCII STL tabs and CRLF whitespace")
	check(session.import_file("res://fixtures/hierarchy.gltf","m","Y_UP"),"P1 external glTF")
	check(session.bounds().size.distance_to(Vector3(1,2,3))<.00001 and session.bounds().get_center().distance_to(Vector3(3,3,4))<.00001,"P0 asymmetric hierarchy transforms")
	var original = session.visual
	for file in ["bad.obj","ngon.obj","bad.stl","bad.glb","missing.gltf"]:
		check(not session.import_file("res://fixtures/"+file,"m","Y_UP") and session.visual == original,"P1 rejected input keeps previous "+file)
	check(session.import_file("res://fixtures/box.obj","m","Y_UP"),"P1 missing MTL retains geometry")
	check(session.diagnostics.any(func(s):return "缺" in s),"P1 missing dependencies diagnosed")
	var path := mesh_path(session)
	check(session.configure(path,{"kind":"box","friction":.2,"layer":4,"mask":8}),"P2 box authored")
	check(not session.import_file("res://fixtures/box.glb","m","Y_UP"),"P0 dirty import blocked")
	session.history.undo(); check(session.specs.is_empty(),"P3 Undo collision draft")
	session.history.redo(); check(session.specs[path].friction == .2,"P3 Redo collision draft")
	check(not session.configure(path,{"kind":"convex"}),"P2 unsupported convex rejected")
	check(not session.configure(path,{"kind":"box","friction":NAN}),"P3 invalid friction atomic rejection")
	check(session.specs[path].friction == .2,"P3 rejected draft preserved")
	var primitive: Dictionary = session.build_scene(); scene.add_child(primitive.scene); await ticks(5)
	check(not ray(Vector3(0,2,0),Vector3(0,-2,0),4).is_empty(),"P2 box actual ray layer 4")
	check(ray(Vector3(0,2,0),Vector3(0,-2,0),1).is_empty(),"P2 layer rejection")
	primitive.scene.queue_free(); await ticks(3)
	var watch := Watch.new(); var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(doc.import_file("res://fixtures/main.xml"),"P0 compiled include document")
	check(watch.capture("res://fixtures/main.xml",doc.asset_manifest().assets),"P0 capture main/include")
	var output_lines := []
	var code := OS.execute("python3",["-c","import pathlib,os;p=pathlib.Path(r'"+ProjectSettings.globalize_path("res://fixtures/include.xml")+"');s=p.stat();p.write_text(p.read_text().replace('3 3 .1','4 3 .1'));os.utime(p,ns=(s.st_atime_ns,s.st_mtime_ns))"],output_lines,true)
	check(code == 0 and watch.inspect(false).state == "源已变","P0 same-mtime include content change")
	check(watch.inspect(true).state == "冲突","P0 source/local dirty conflict")
	var before: Dictionary = doc.snapshot()
	check(not doc.import_file("res://fixtures/bad.xml") and doc.snapshot() == before,"P0 bad MJCF atomic rollback")
	var packed_model: Dictionary = preload("res://addons/godot_mujoco/model/package_builder.gd").pack(doc,"res://mjcf_packages","normalized")
	check(packed_model.error.is_empty(),"P0 normalized MJCF safe copy "+packed_model.error)
	if packed_model.error.is_empty():
		var resource = load(packed_model.path); check(resource.open_document().error.is_empty(),"P0 reimport normalized include-free copy")

	var assets_doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(assets_doc.import_file("res://fixtures/asset.xml"),"P0 MJCF mesh/texture document")
	var asset_watch := Watch.new()
	check(asset_watch.capture("res://fixtures/asset.xml",assets_doc.asset_manifest().assets),"P0 mesh/texture provenance capture")
	for asset in ["box.obj","texture.png","asset.xml"]:
		var target: String = "res://fixtures/"+asset; var bytes := FileAccess.get_file_as_bytes(target)
		var f := FileAccess.open(target,FileAccess.WRITE); f.store_buffer(bytes); f.store_8(32); f.close()
		check(asset_watch.inspect(false).changes.any(func(v):return v.ends_with(asset)),"P0 detects changed "+asset)
		f = FileAccess.open(target,FileAccess.WRITE); f.store_buffer(bytes); f.close()
	# Building feasibility gate: explicit component boxes, never convex hull of the room.
	check(session.import_file("res://fixtures/room.obj","m","Y_UP",true),"P1 doorway room")
	check(session.configure(mesh_path(session),{"kind":"compound_boxes","parts":boxes("room"),"friction":.8,"layer":1,"mask":1}),"P2 explicit room components")
	var built: Dictionary = session.build_scene(); scene.add_child(built.scene); await ticks(5)
	check(ray(Vector3(0,1,-4),Vector3(0,1,-2)).is_empty(),"P2 doorway ray remains open")
	check(not ray(Vector3(2,1,-4),Vector3(2,1,-2)).is_empty(),"P2 wall ray blocks")
	var through := ball(Vector3(0,1,-4)); through.linear_velocity = Vector3(0,0,2)
	var blocked := ball(Vector3(2,1,-4)); blocked.linear_velocity = Vector3(0,0,2)
	await ticks(90)
	check(through.position.z > -2,"P2 actual rigid body traverses doorway")
	check(blocked.position.z < -3.25,"P2 actual rigid body blocked by wall")
	output.doorway_z = through.position.z; output.wall_z = blocked.position.z
	through.queue_free(); blocked.queue_free(); built.scene.queue_free(); await ticks(3)
	# Save this room; shell will remove sources and relocate the package before reopening.
	var room_contract := {"width":3,"depth":2,"spacing_x":1.0,"spacing_z":1.0,"unit":"m","row_order":"increasing_z","encoding":"float32_le"}
	check(session.import_height("res://fixtures/ramp.raw",room_contract),"P3 mixed room and terrain package")
	session.terrains[0].pose.origin = Vector3(10,0,0)
	session.visual.get_node("HeightField_0").position = Vector3(10,0,0)
	check(session.configure_terrain("HeightField_0",.42,4,3),"P3 terrain material draft")
	var result := Package.pack(session,"res://packages")
	check(result.error.is_empty(),"P3 immutable self-contained room package "+result.error)
	if result.error.is_empty(): write("res://saved_path.txt",result.path)
	var bad_spec := session.specs.duplicate(true); bad_spec[mesh_path(session)].friction = NAN; session.specs = bad_spec
	var rejected := Package.pack(session,"res://packages"); check(not rejected.error.is_empty(),"P3 invalid package publish rejected")
	if result.error.is_empty(): check(Package.validate(result.path).is_empty(),"P3 old package survives failed publish")
	check(session.import_file("res://fixtures/stairs.obj","m","Y_UP",true),"P1 stairs")
	check(session.configure(mesh_path(session),{"kind":"compound_boxes","parts":boxes("stairs")}),"P2 explicit stair components")
	built = session.build_scene(); scene.add_child(built.scene); await ticks(3)
	for i in 5:
		var hit := ray(Vector3(i*.5,3,0),Vector3(i*.5,-1,0))
		check(absf(hit.get("position",Vector3.INF).y-.25*(i+1))<.002,"P2 actual stair tread "+str(i))
	built.scene.queue_free(); await ticks(3)
	var contract := {"width":3,"depth":2,"spacing_x":1.0,"spacing_z":1.0,"unit":"m","row_order":"increasing_z","encoding":"float32_le"}
	var height := Height.read("res://fixtures/ramp.raw",contract)
	check(height.error.is_empty() and height.grid.heights == PackedFloat32Array([-1,0,1,-1,0,1]),"P2 negative non-square RAW slope")
	for invalid_width in [2.5,NAN,INF,1,257]:
		var invalid: Dictionary = contract.duplicate(); invalid.width = invalid_width
		check(not Height.read("res://fixtures/ramp.raw",invalid).error.is_empty(),"P2 invalid height dimension "+str(invalid_width))
	contract.spacing_x = .5; check(not Height.read("res://fixtures/ramp.raw",contract).error.is_empty(),"P2 unsupported spacing explicit rejection"); contract.spacing_x = 1.0
	check(session.import_height("res://fixtures/ramp.raw",contract),"P2 import supported HeightField")
	var terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd").new(); terrain.design = height.grid; scene.add_child(terrain); await ticks(10)
	check(terrain.body_rid.is_valid(),"P2 heightfield committed")
	check(absf(ray(Vector3(.5,3,0),Vector3(.5,-3,0)).get("position",Vector3.INF).y-.5)<.002,"P2 slope actual collision")
	terrain.queue_free(); await ticks(3)
	await sliding()
	session.close(); scene.queue_free(); await ticks(3)
	output.passed = passed; output.failed = failed
	print("STATIC_MAP_RESULT ",JSON.stringify(output)); quit(1 if failed else 0)
func sliding():
	var map_session := Session.new()
	check(map_session.import_file("res://fixtures/box.obj","m","Y_UP"),"P3 friction map source import")
	var mesh: MeshInstance3D = map_session.meshes()[0]
	mesh.scale = Vector3(20,.2,6); mesh.position.y = -.1
	var path := mesh_path(map_session); var distances := []
	for friction in [0.0,.8]:
		check(map_session.configure(path,{"kind":"box","friction":friction,"layer":1,"mask":1}),"P3 configure map friction "+str(friction))
		var package := Package.pack(map_session,"res://friction_packages")
		check(package.error.is_empty(),"P3 save friction map "+str(friction))
		if not package.error.is_empty(): map_session.close(); return
		var reopened := ResourceLoader.load(package.path.path_join("map.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var map := reopened.instantiate(); scene.add_child(map)
		var box := RigidBody3D.new(); box.position = Vector3(-2,.25,0); box.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE; box.linear_damp = 0
		var c := CollisionShape3D.new(); c.shape = BoxShape3D.new(); c.shape.size = Vector3(.5,.5,.5); box.add_child(c); scene.add_child(box)
		await ticks(30); box.linear_velocity = Vector3(1.5,0,0); var start := box.position.x; await ticks(30)
		distances.append(box.position.x-start)
		var info: Dictionary = PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
		check(not info.contact_details.is_empty() and absf(info.contact_details[0].friction-friction)<.001,"P3 reopened map compiled contact friction "+str(friction))
		if friction > 0: check(absf(box.linear_velocity.x)<.1,"P3 reopened high-friction map stops box")
		box.queue_free(); map.queue_free(); await ticks(3)
	check(distances[0]>.65,"P3 reopened low-friction map actual sliding")
	check(distances[1]<distances[0]*.5,"P3 reopened high-friction map observable reduction")
	output.low_friction_distance = distances[0]; output.high_friction_distance = distances[1]
	map_session.close()
