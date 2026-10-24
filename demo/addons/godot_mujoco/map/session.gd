@tool
extends RefCounted
const Importer = preload("importer.gd")
const Watch = preload("source_watch.gd")
const Collision = preload("collision.gd")
var visual: Node3D
var source := ""
var unit := ""
var axes := ""
var error := ""
var diagnostics: Array = []
var watch = Watch.new()
var terrains: Array = []
var specs: Dictionary = {}
var view: Dictionary = {}
var dirty := false
var history: UndoRedo = UndoRedo.new()

func import_file(path: String, selected_unit: String, selected_axes: String, discard_local := false) -> bool:
	if dirty and not discard_local: error = "本地脏/冲突：先另存副本、保留本地，或明确丢弃并重导入"; return false
	var importer := Importer.new()
	var candidate := importer.import_file(path, selected_unit, selected_axes)
	if not candidate: error = importer.error; return false
	# Missing optional OBJ textures remain visible diagnostics and tracked as missing.
	var candidate_watch := Watch.new()
	var existing := importer.dependencies.filter(func(p): return FileAccess.file_exists(p))
	if not candidate_watch.capture(path, existing): candidate.free(); error = candidate_watch.error; return false
	for dependency in importer.dependencies:
		if not FileAccess.file_exists(dependency): candidate_watch.hashes[dependency] = "missing"
	if is_instance_valid(visual): visual.free()
	visual = candidate; watch = candidate_watch; source = path; unit = selected_unit; axes = selected_axes
	diagnostics = importer.diagnostics; terrains = []; specs = {}; view = {}; dirty = false; error = ""; history.clear_history()
	return true

func restore_specs(value: Dictionary) -> void:
	specs = value.duplicate(true); dirty = true

func configure(path: String, spec: Dictionary) -> bool:
	if not visual or not visual.has_node(NodePath(path)) or not visual.get_node(NodePath(path)) is MeshInstance3D: error = "找不到网格对象: " + path; return false
	if spec.get("kind", "visual") != "visual":
		var test := Collision.build(visual.get_node(NodePath(path)), visual, spec)
		if not test.error.is_empty(): error = path + ": " + test.error; return false
		test.body.free()
	var next := specs.duplicate(true); next[path] = spec.duplicate(true)
	history.create_action("地图碰撞/摩擦草稿")
	history.add_do_method(restore_specs.bind(next)); history.add_undo_method(restore_specs.bind(specs.duplicate(true))); history.commit_action()
	error = ""; return true

func meshes(node: Node = null) -> Array:
	if node == null: node = visual
	var result := []
	if node is MeshInstance3D and node.mesh: result.append(node)
	if node:
		for child in node.get_children(): result.append_array(meshes(child))
	return result

func bounds(node: Node3D = null) -> AABB:
	if node == null: node = visual
	var box := AABB(); var first := true
	for mesh in meshes(node):
		var next: AABB = Collision.pose_of(mesh, visual) * mesh.mesh.get_aabb()
		box = next if first else box.merge(next); first = false
	return box

func build_scene() -> Dictionary:
	if not visual: return {"error":"尚无地图"}
	var scene := preload("map_root.gd").new(); scene.name = "StaticMap"
	var copy := visual.duplicate(); copy.name = "Visual"; scene.add_child(copy)
	var physics := Node3D.new(); physics.name = "Physics"; scene.add_child(physics)
	for mesh in meshes():
		var path := str(visual.get_path_to(mesh)); var spec: Dictionary = specs.get(path, {})
		if spec.get("kind", "visual") == "visual": continue
		var result := Collision.build(mesh, visual, spec)
		if not result.error.is_empty(): scene.free(); return {"error":path + ": " + result.error}
		result.body.name = "Object_" + str(physics.get_child_count()); result.body.set_meta("source_node", path); physics.add_child(result.body)
	for design in terrains:
		var terrain = preload("../model/static_heightfield.gd").new()
		terrain.name = design.name; terrain.design = design.grid.duplicate(true); terrain.transform = design.pose
		terrain.collision_layer = design.get("layer",1); terrain.collision_mask = design.get("mask",1)
		terrain.physics_material_override = design.material.duplicate(true)
		scene.add_child(terrain)
		if copy.has_node(NodePath(design.name)): copy.get_node(NodePath(design.name)).free()
	var camera := preload("map_camera.gd").new(); camera.name = "MapCamera"
	var box := bounds(); var saved: Dictionary = view.get("camera",{})
	var center: Vector3 = saved.get("center",box.get_center()); var distance: float = saved.get("distance",maxf(.01,box.size.length()*1.5))
	var yaw: float = saved.get("yaw",.6); var pitch: float = saved.get("pitch",.35)
	camera.position = center + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.transform = camera.transform.looking_at(center); camera.near = maxf(.00001,distance/10000); camera.far = maxf(100,distance*100)
	camera.target = center; camera.distance = distance; camera.yaw = yaw; camera.pitch = pitch
	camera.set_meta("viewer_settings",saved); scene.add_child(camera)
	var light := DirectionalLight3D.new(); light.name = "MapLight"; light.rotation_degrees = Vector3(-50,-30,0); scene.add_child(light)
	scene.set_meta("map_terrains", terrains.duplicate(true))
	scene.set_meta("map_specs", specs.duplicate(true)); scene.set_meta("map_view", view.duplicate(true))
	scene.set_meta("source_hashes", watch.hashes.duplicate()); scene.set_meta("contract", visual.get_meta("contract")); scene.set_meta("diagnostics", diagnostics)
	Importer._owners(scene,scene)
	return {"error":"", "scene":scene}

func close() -> void:
	if is_instance_valid(visual): visual.free()
	visual = null
	if is_instance_valid(history): history.clear_history(); history.free()
	history = null

func import_height(path: String, contract: Dictionary) -> bool:
	var result := preload("height_import.gd").read(path,contract)
	if not result.error.is_empty(): error = result.error; return false
	if not visual:
		visual = Node3D.new(); visual.name = "Map"
		unit = "m"; axes = "Y_UP"; source = path
		visual.set_meta("contract",{"version":1,"source":path,"unit":"m","axes":"Y_UP","metres_per_unit":1.0,"target":"right-handed Y-up metres"})
	var name := "HeightField_" + str(terrains.size())
	var mesh := MeshInstance3D.new(); mesh.name = name; mesh.mesh = result.grid.mesh(); visual.add_child(mesh); mesh.owner = visual
	terrains.append({"name":name,"grid":result.grid,"pose":Transform3D.IDENTITY,"material":PhysicsMaterial.new(),"contract":contract.duplicate(true)})
	watch.hashes[path] = result.source_hash
	dirty = true; error = "高度场已按契约导入；可通过地形面板编辑材质并显式 Apply"; return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(visual): visual.free()
		if is_instance_valid(history): history.free()

func restore_terrains(value: Array) -> void:
	terrains = value.duplicate(true); dirty = true

func configure_terrain(name: String, friction: float, layer: int, mask: int) -> bool:
	if not is_finite(friction) or friction < 0 or friction > 1 or layer < 0 or layer > 4294967295 or mask < 0 or mask > 4294967295: error = "地形材质/层掩码无效"; return false
	var next := terrains.duplicate(true)
	for i in next.size():
		if next[i].name != name: continue
		next[i].material = next[i].material.duplicate(true); next[i].material.friction = friction
		next[i].layer = layer; next[i].mask = mask
		history.create_action("地图地形材质草稿")
		history.add_do_method(restore_terrains.bind(next)); history.add_undo_method(restore_terrains.bind(terrains.duplicate(true))); history.commit_action()
		error = ""; return true
	error = "地形对象不存在"; return false
