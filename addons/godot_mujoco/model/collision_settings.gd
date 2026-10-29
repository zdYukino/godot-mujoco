@tool
extends RefCounted
const Xml = preload("author_xml.gd")
const WORLD_DEFAULTS := {"nativeccd":true, "multiccd":true, "ccd_iterations":35, "ccd_tolerance":0.000001, "sdf_iterations":10, "sdf_initpoints":40}
const MAX_CELLS_PER_MESH := 500000 # Same limit as the native SDF query certificate.
const DEPTH_WARNING := "此深度仅保存在 Godot 工程中，不随 MJCF 导出。独立加载导出的 XML 时，MuJoCo 使用引擎默认深度（当前为 6）。"

static func world_values(tree: Dictionary) -> Dictionary:
	var values := WORLD_DEFAULTS.duplicate()
	var option := Xml.section(tree, "option")
	var flags := Xml.section(option, "flag").get("attrs", {})
	for key in values:
		if key in ["nativeccd", "multiccd"]: values[key] = flags.get(key, "enable") != "disable"
		elif key == "ccd_tolerance": values[key] = float(option.get("attrs", {}).get(key, str(values[key])))
		else: values[key] = int(option.get("attrs", {}).get(key, str(values[key])))
	return values

static func write_world(tree: Dictionary, values: Dictionary) -> String:
	for key in values:
		if not WORLD_DEFAULTS.has(key): return "Unknown collision option: " + str(key)
		var value: Variant = values[key]
		if key in ["nativeccd", "multiccd"]:
			if not value is bool: return "Collision flag must be boolean"
		elif key == "ccd_tolerance":
			if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(value) or value < 0 or value > 100: return "CCD tolerance must be finite and between 0 and 100"
		elif typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(value) or value != floor(value) or value < 0 or value > 1000:
			return "Collision iteration counts must be integers in 0..1000"
	var option := Xml.section(tree, "option", true)
	for key in values:
		if key in ["nativeccd", "multiccd"]: Xml.section(option, "flag", true).attrs[key] = "enable" if values[key] else "disable"
		else: option.attrs[key] = String.num_scientific(float(values[key])) if key == "ccd_tolerance" else str(int(values[key]))
	return ""

static func limits() -> Dictionary:
	return {"triangles_per_mesh":maxi(4,int(ProjectSettings.get_setting("mujoco/authoring/sdf_max_triangles_per_mesh",20000))), "cells_per_world":maxi(1,int(ProjectSettings.get_setting("mujoco/authoring/sdf_max_cells_per_world",2000000)))}

static func context(world: Node, design: Resource) -> Dictionary:
	return {"collision_options":world_values(world.world_design.tree if world and world.world_design else design.tree), "limits":limits()}

static func signature(value: Dictionary) -> String:
	return var_to_bytes(value).hex_encode().sha256_text()

static func mesh_asset(design: Resource, geom: Dictionary) -> Dictionary:
	var label: String = design.effective_attrs(geom).get("mesh", "")
	for asset in Xml.section(design.tree,"asset").get("children",[]):
		if asset.tag == "mesh" and asset.attrs.get("name", "") == label: return asset
	return {}

static func private_mesh(design: Resource, geom: Dictionary) -> Dictionary:
	var mesh := mesh_asset(design, geom)
	if mesh.is_empty(): return {}
	var references := 0
	for entity in design.entities():
		if entity.kind == "geom" and entity.attrs.get("mesh", "") == mesh.attrs.name: references += 1
	if references <= 1 and mesh.get("edit_owner", "") == geom.id: return mesh
	var copy := mesh.duplicate(true)
	Xml.clone_ids(copy,{})
	copy.edit_owner = geom.id
	copy.attrs = design.effective_attrs(mesh)
	var label: String = str(geom.attrs.name) + "_mesh"
	var used := []
	for asset in Xml.section(design.tree,"asset").get("children",[]):
		if asset.tag == "mesh": used.append(asset.attrs.get("name", ""))
	while label in used: label += "_2"
	copy.attrs.name = label
	Xml.section(design.tree,"asset",true).children.append(copy)
	if design.mesh_options.has(mesh.id): design.mesh_options[copy.id] = design.mesh_options[mesh.id].duplicate(true)
	geom.attrs.mesh = label
	return copy

static func geom_fields(node: Node) -> Array[Dictionary]:
	var entity: Dictionary = node.item()
	if entity.is_empty(): return []
	var mesh: bool = entity.attrs.get("type", "sphere") in ["mesh", "sdf"]
	var fields: Array[Dictionary] = [{"name":"MJCF 碰撞", "type":TYPE_NIL, "usage":PROPERTY_USAGE_GROUP, "hint_string":"mjcf/collision_"}, node.property("collision_mode",TYPE_STRING,PROPERTY_HINT_NONE,"",not mesh)]
	if mesh:
		if entity.attrs.get("type") == "sdf": fields.append(node.property("collision_sdf_depth",TYPE_INT))
		else: fields.append(node.property("collision_maxhullvert",TYPE_INT))
	fields.append(node.property("collision_actual",TYPE_STRING,PROPERTY_HINT_NONE,"",true))
	fields.append(node.property("collision_world",TYPE_STRING,PROPERTY_HINT_NONE,"",true))
	return fields

static func geom_value(node: Node, key: String) -> Variant:
	var model: Node = node.author_model()
	var geom := Xml.find(model.design.tree,node.entity_id)
	var attrs: Dictionary = model.design.effective_attrs(geom)
	var mesh := mesh_asset(model.design,geom)
	match key:
		"mode": return "sdf" if attrs.get("type") == "sdf" else "hull" if attrs.get("type") == "mesh" else "native"
		"sdf_depth": return model.design.mesh_options.get(mesh.get("id", ""),{}).get("octree_maxdepth",0)
		"maxhullvert": return int(model.design.effective_attrs(mesh).get("maxhullvert", "-1")) if not mesh.is_empty() else -1
		"world":
			var values: Dictionary = context(model.find_world(),model.design).collision_options
			return "凸检测：%s；多接触点：%s" % ["GJK/EPA" if values.nativeccd else "libccd/MPR", "开" if values.multiccd else "关"]
		"actual":
			var suffix := "" if model.design.validated_revision == model.design.revision and model.design.validated_context == model.compilation_signature() else "（上次有效）"
			for entity in model.design.cached_entities:
				if entity.kind != "geom" or entity.name != node.item().name: continue
				var type: int = entity.properties.type
				if type == 8:
					for stat in model.design.collision_stats:
						if stat.mesh == entity.properties.mesh: return "SDF · 实际深度 %d · %d 单元%s" % [stat.depth,stat.cells,suffix]
				return ("凸包" if type == 7 else "原生（%s）" % attrs.get("type","sphere")) + suffix
			return "等待后台验证"
	return null

static func apply_geom(design: Resource, geom: Dictionary, key: String, value: Variant) -> String:
	if geom.tag != "geom" or design.effective_attrs(geom).get("type", "sphere") not in ["mesh", "sdf"]: return "Only mesh-backed geoms can change collision representation"
	if key == "mode":
		if value not in ["hull", "sdf"]: return "Choose convex hull or SDF"
		geom.attrs.type = "sdf" if value == "sdf" else "mesh"
		return ""
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value) or value != floor(value): return "Collision precision must be an integer"
	if key == "sdf_depth" and value != 0 and (value < 3 or value > 8): return "SDF depth must be default or 3..8"
	if key == "maxhullvert" and value != -1 and value < 4: return "Convex hull vertex limit must be unlimited or at least 4"
	if key not in ["sdf_depth", "maxhullvert"]: return "Unknown collision precision"
	var mesh := private_mesh(design,geom)
	if mesh.is_empty(): return "Missing mesh asset"
	if key == "maxhullvert": mesh.attrs.maxhullvert = str(int(value))
	elif value == 0: design.mesh_options.erase(mesh.id)
	else: design.mesh_options[mesh.id] = {"octree_maxdepth":int(value)}
	return ""

static func validate_stats(stats: Array, budget: Dictionary) -> String:
	var cells := 0
	for stat in stats:
		if stat.triangles > int(budget.get("triangles_per_mesh",20000)): return "SDF %s exceeds the triangle budget" % stat.mesh
		if stat.cells > MAX_CELLS_PER_MESH: return "SDF %s exceeds the 500000-cell query limit" % stat.mesh
		if not stat.query_valid: return "SDF %s is outside the supported spatial-query domain" % stat.mesh
		cells += int(stat.cells)
	if cells > int(budget.get("cells_per_world",2000000)): return "SDF octree total exceeds the world budget"
	return ""

static func validate_geometry(geometry: Array, entities: Array, budget: Dictionary) -> String:
	var mesh_names := {}
	for entity in entities:
		if entity.kind == "geom": mesh_names[entity.name] = entity.properties.get("mesh","")
	var checked := {}
	for geom in geometry:
		if geom.type != 8: continue
		var label: String = mesh_names.get(geom.name,geom.name)
		if checked.has(label): continue
		checked[label] = true
		var faces: PackedVector3Array = geom.get("vertices",PackedVector3Array())
		if faces.size() < 12 or faces.size()%3 != 0: return "SDF %s has no closed triangle surface" % label
		if faces.size()/3 > int(budget.get("triangles_per_mesh",20000)): return "SDF %s exceeds the triangle budget" % label
		var box := AABB(faces[0],Vector3.ZERO)
		for point in faces:
			if not point.is_finite(): return "SDF contains nonfinite coordinates"
			box = box.expand(point)
		var extent := maxf(box.size.x,maxf(box.size.y,box.size.z))
		if extent <= 0: return "SDF has zero extent"
		var lookup := {}; var points: Array[Vector3] = []; var triangles := []; var edges := {}
		for index in range(0,faces.size(),3):
			var triangle := []
			for offset in 3:
				var point := faces[index+offset]
				if not lookup.has(point): lookup[point] = points.size(); points.append((point-box.get_center())/extent)
				triangle.append(lookup[point])
			if (points[triangle[1]]-points[triangle[0]]).cross(points[triangle[2]]-points[triangle[0]]).length_squared() < 1e-24: return "SDF contains degenerate triangles"
			triangles.append(triangle)
			for offset in 3:
				var a: int = triangle[offset]; var b: int = triangle[(offset+1)%3]
				var key := Vector2i(mini(a,b),maxi(a,b))
				edges[key] = edges.get(key,Vector2i.ZERO) + Vector2i(1,1 if a<b else -1)
		for edge in edges.values():
			if edge != Vector2i(2,0): return "SDF %s requires closed, consistently wound manifold triangles" % label
		var error: String = preload("../map/sdf_quality.gd").validate(points,triangles,true,int(budget.get("triangles_per_mesh",20000)))
		if not error.is_empty(): return label + ": " + error
	return ""

static func register_project_settings() -> void:
	for entry in [
		["mujoco/authoring/sdf_max_triangles_per_mesh",20000,"4,1000000,1,or_greater"],
		["mujoco/authoring/sdf_max_cells_per_world",2000000,"1,20000000,1,or_greater"],
		["mujoco/authoring/compile_timeout_seconds",120.0,"1,600,1,or_greater"]]:
		if not ProjectSettings.has_setting(entry[0]): ProjectSettings.set_setting(entry[0],entry[1])
		ProjectSettings.set_initial_value(entry[0],entry[1])
		ProjectSettings.add_property_info({"name":entry[0],"type":typeof(entry[1]),"hint":PROPERTY_HINT_RANGE,"hint_string":entry[2]})
