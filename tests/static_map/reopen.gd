extends SceneTree
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var passed := 0
var failed := 0
func _initialize(): call_deferred("run")
func check(ok: bool, label: String):
	if ok: passed += 1
	else: failed += 1
	print("PASS " if ok else "FAIL ",label)
func run():
	var path := FileAccess.get_file_as_string("res://saved_path.txt").strip_edges()
	check(Package.validate(path).is_empty(),"P3 package hashes after source removal/migration")
	var packed := load(path.path_join("map.tscn")) as PackedScene
	if not packed: quit(1); return
	var scene := packed.instantiate(); root.add_child(scene)
	for i in 15: await physics_frame; await process_frame
	var space = scene.get_world_3d().direct_space_state
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,-4),Vector3(0,1,-2))).is_empty(),"P3 reopened door open")
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(2,1,-4),Vector3(2,1,-2))).is_empty(),"P3 reopened wall collision")
	var terrain = scene.get_node("HeightField_0")
	check(terrain.body_rid.is_valid() and is_equal_approx(terrain.physics_material_override.friction,.42),"P3 reopened terrain transaction and friction")
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(10.5,3,0),Vector3(10.5,-3,0),4))
	check(absf(hit.get("position",Vector3.INF).y-.5)<.002,"P3 reopened terrain actual slope/layer")
	var visual_mesh = scene.get_node("Visual/SourceCoordinates/OBJ/Object")
	check(visual_mesh.mesh.surface_get_material(0).albedo_texture.get_image().get_width()==2,"P3 embedded texture survives source removal")
	var body := scene.get_node("Physics").get_child(0)
	check(body.collision_layer == 1 and body.collision_mask == 1 and is_equal_approx(body.physics_material_override.friction,.8),"P3 reopened friction/layers")
	check(scene.get_meta("source_hashes").size() > 0 and scene.get_meta("contract").unit == "m","P3 reopened provenance/units")
	scene.queue_free(); await process_frame; await process_frame
	print("STATIC_MAP_REOPEN ",JSON.stringify({"passed":passed,"failed":failed})); quit(1 if failed else 0)
