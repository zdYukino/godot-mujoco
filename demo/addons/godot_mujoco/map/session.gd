@tool
extends RefCounted
const Importer = preload("importer.gd")
const Watch = preload("source_watch.gd")
const Collision = preload("collision.gd")
const Native = preload("native_collision.gd")
var world_settings: Dictionary = {}
var contact_relations: Dictionary = {}
var last_collision_attempt: Dictionary = {}
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
	if candidate_watch.hashes != importer.source_hashes:
		candidate.free(); error = "导入解析和来源记录之间内容已变，安全拒绝；请重试"; return false
	if is_instance_valid(visual): visual.free()
	visual = candidate; watch = candidate_watch; source = path; unit = selected_unit; axes = selected_axes
	diagnostics = importer.diagnostics; terrains = []; specs = {}; world_settings = {}; contact_relations = {}; view = {}; dirty = false; error = ""; history.clear_history()
	return true

func restore_specs(value: Dictionary) -> void:
	specs = value.duplicate(true); dirty = true

func configure(path: String, spec: Dictionary) -> bool:
	if not visual or not visual.has_node(NodePath(path)) or not visual.get_node(NodePath(path)) is MeshInstance3D: error = "找不到网格对象: " + path; return false
	if spec.get("kind")=="compound_boxes" and spec.get("native_contact",false):
		error="compound_boxes 原生接触参数尚未接入；请取消原生接触或为各对象选择受支持的原生基础体"
		last_collision_attempt=Native.record("compound_boxes","disabled",error)
		return false
	if spec.get("kind", "visual") != "visual":
		var test := Native.build(visual.get_node(NodePath(path)), visual, spec, world_settings) if Native.uses_native(spec) else Collision.build(visual.get_node(NodePath(path)), visual, spec)
		if not test.error.is_empty():
			error = path + ": " + test.error
			last_collision_attempt = Native.record(spec.get("kind","visual"),"disabled",error)
			return false
		if test.has("body"): test.body.free()
	var next := specs.duplicate(true); next[path] = spec.duplicate(true)
	for field in ["layer","mask"]:
		if next[path].has(field) and spec.get("kind","visual")!="visual": next[path][field]=int(next[path][field])
	if Native.uses_native(spec) and spec.has("contact"): next[path].contact=Native.contact_attributes(spec).contact
	next[path]["capability"] = Native.record(spec.get("kind","visual"),spec.get("kind","visual"))
	if Native.uses_native(spec): next[path].capability.adapter="map_mjcf"
	next[path]["source_hashes"] = watch.hashes.duplicate()
	var relation_error := validate_relation_candidate(next,terrains)
	if not relation_error.is_empty():
		error = path + ": " + relation_error
		last_collision_attempt = Native.record(spec.get("kind","visual"),"disabled",error)
		return false
	last_collision_attempt = next[path]["capability"].duplicate()
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
		if spec.get("kind")=="compound_boxes" and spec.get("native_contact",false): scene.free(); return {"error":path+": compound_boxes 原生接触参数尚未接入；拒绝忽略已保存请求"}
		if Native.uses_native(spec):
			var native := Native.build(mesh,visual,spec,world_settings)
			if not native.error.is_empty(): scene.free(); return {"error":path + ": " + native.error}
			scene.native_collisions.append({"snapshot":native.snapshot,"pose":native.pose,"contract":native.contract,"source_hash":native.source_hash,"source_node":path})
			continue
		var result := Collision.build(mesh, visual, spec)
		if not result.error.is_empty(): scene.free(); return {"error":path + ": " + result.error}
		result.body.name = "Object_" + str(physics.get_child_count()); result.body.set_meta("source_node", path); physics.add_child(result.body)
	for design in terrains:
		if design.has("native_contact"):
			var native := Native.build_height(design,world_settings)
			if not native.error.is_empty(): scene.free(); return native
			scene.native_collisions.append({"snapshot":native.snapshot,"pose":native.pose,"contract":native.contract,"source_hash":native.source_hash,"source_node":design.name})
			continue
		var terrain = preload("../model/static_heightfield.gd").new()
		terrain.name = design.name; terrain.design = design.grid.duplicate(true); terrain.transform = design.pose
		terrain.collision_layer = design.get("layer",1); terrain.collision_mask = design.get("mask",1)
		terrain.physics_material_override = design.material.duplicate(true)
		scene.add_child(terrain)
		if copy.has_node(NodePath(design.name)): copy.get_node(NodePath(design.name)).free()
	if not contact_relations.is_empty():
		var combined:=Native.combine(scene.native_collisions,contact_relations,world_settings)
		if not combined.error.is_empty(): scene.free(); return combined
		scene.native_collisions.assign([combined.entry])
	scene.set_meta("map_contact_relations",contact_relations.duplicate(true))
	var camera := preload("map_camera.gd").new(); camera.name = "MapCamera"
	var box := bounds(); var saved: Dictionary = view.get("camera",{})
	var center: Vector3 = saved.get("center",box.get_center()); var distance: float = saved.get("distance",maxf(.01,box.size.length()*1.5))
	var yaw: float = saved.get("yaw",.6); var pitch: float = saved.get("pitch",.35)
	camera.position = center + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.transform = camera.transform.looking_at(center); camera.near = maxf(.00001,distance/10000); camera.far = maxf(100,distance*100)
	camera.target = center; camera.distance = distance; camera.yaw = yaw; camera.pitch = pitch
	camera.set_meta("viewer_settings",saved); scene.add_child(camera)
	var light := DirectionalLight3D.new(); light.name = "MapLight"; light.rotation_degrees = Vector3(-50,-30,0); scene.add_child(light)
	scene.world_settings = world_settings.duplicate(true)
	scene.set_meta("map_world_settings",world_settings.duplicate(true))
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

func import_height(path: String, contract: Dictionary, contract_path := "") -> bool:
	var contract_hash := ""
	if not contract_path.is_empty():
		if not FileAccess.file_exists(contract_path): error = "高度契约文件缺失"; return false
		contract_hash = FileAccess.get_sha256(contract_path)
		var actual: Variant = JSON.parse_string(FileAccess.get_file_as_string(contract_path))
		if actual != contract or FileAccess.get_sha256(contract_path) != contract_hash: error = "高度契约读取期间已变，安全拒绝"; return false
	var result := preload("height_import.gd").read(path,contract)
	if not result.error.is_empty(): error = result.error; return false
	if not contract_path.is_empty() and FileAccess.get_sha256(contract_path) != contract_hash: error = "高度契约导入期间已变，安全拒绝"; return false
	if not visual:
		visual = Node3D.new(); visual.name = "Map"
		unit = "m"; axes = "Y_UP"; source = path
		visual.set_meta("contract",{"version":1,"source":path,"unit":"m","axes":"Y_UP","metres_per_unit":1.0,"target":"right-handed Y-up metres"})
	var name := "HeightField_" + str(terrains.size())
	var mesh := MeshInstance3D.new(); mesh.name = name; mesh.mesh = result.grid.mesh(); visual.add_child(mesh); mesh.owner = visual
	terrains.append({"name":name,"grid":result.grid,"pose":Transform3D.IDENTITY,"material":PhysicsMaterial.new(),"contract":contract.duplicate(true)})
	watch.hashes[path] = result.source_hash
	if not contract_path.is_empty(): watch.hashes[contract_path] = contract_hash
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

func restore_world(value: Dictionary) -> void:
	world_settings = value.duplicate(true); dirty = true

func configure_world(value: Dictionary) -> bool:
	var checked := Native.options(value)
	if not checked.error.is_empty(): error = checked.error; return false
	var doc := MjEditorDocument.new()
	if not doc.restore({"format":1,"xml":"<mujoco>"+checked.xml+"<worldbody/></mujoco>","state":{},"source":""}): error = doc.get_error(); return false
	history.create_action("地图世界碰撞设置")
	history.add_do_method(restore_world.bind(checked.settings)); history.add_undo_method(restore_world.bind(world_settings)); history.commit_action()
	error = ""; return true

func configure_terrain_native(name: String, contact: Variant, properties: Dictionary = {}) -> bool:
	var next := terrains.duplicate(true)
	for i in next.size():
		if next[i].name!=name: continue
		if not properties.is_empty():
			var friction: Variant=properties.get("friction",next[i].material.friction); var layer: Variant=properties.get("layer",next[i].get("layer",1)); var mask: Variant=properties.get("mask",next[i].get("mask",1))
			if typeof(friction) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(friction) or friction<0 or friction>1 or not Collision.integer_in_range(layer,0,4294967295) or not Collision.integer_in_range(mask,0,4294967295): error="地形材质/过滤无效"; return false
			next[i].material=next[i].material.duplicate(true); next[i].material.friction=friction; next[i].layer=int(layer); next[i].mask=int(mask)
		if contact==null: next[i].erase("native_contact")
		else:
			next[i].native_contact=contact
			var checked := Native.build_height(next[i],world_settings)
			if not checked.error.is_empty(): error=checked.error; return false
			next[i].native_contact=Native.contact_attributes({"contact":contact}).contact
		var relation_error := validate_relation_candidate(specs,next)
		if not relation_error.is_empty(): error=name+": "+relation_error; return false
		history.create_action("高度场原生接触属性")
		history.add_do_method(restore_terrains.bind(next)); history.add_undo_method(restore_terrains.bind(terrains)); history.commit_action()
		error=""; return true
	error="找不到高度场"; return false

func restore_relations(value: Dictionary) -> void:
	contact_relations=value.duplicate(true); dirty=true

func configure_relations(value: Dictionary) -> bool:
	var previous:=contact_relations; contact_relations=value
	var candidate:=build_scene(); contact_relations=previous
	if not candidate.error.is_empty(): error=candidate.error; return false
	candidate.scene.free()
	value=value.duplicate(true)
	for pair in value.get("pairs",[]):
		if pair.has("condim"): pair.condim=int(pair.condim)
	history.create_action("地图显式 pair/exclude")
	history.add_do_method(restore_relations.bind(value)); history.add_undo_method(restore_relations.bind(previous)); history.commit_action()
	error=""; return true

# Validate cross-object references before adding any history action. Scene building is
# synchronous; restore original container identities even when the candidate fails.
func validate_relation_candidate(candidate_specs: Dictionary, candidate_terrains: Array) -> String:
	if contact_relations.is_empty(): return ""
	var previous_specs := specs; var previous_terrains := terrains
	specs=candidate_specs; terrains=candidate_terrains
	var candidate := build_scene()
	specs=previous_specs; terrains=previous_terrains
	if not candidate.error.is_empty(): return candidate.error
	candidate.scene.free()
	return ""
