@tool
class_name MjAuthorResource
extends Resource
## Persistent author data. Compilation is optional and never a condition of saving.
const Xml = preload("author_xml.gd")
signal design_changed
@export_storage var format_version := 1
@export_storage var document_id := ""
@export_storage var tree: Dictionary = {}
@export_storage var initial_pose: Dictionary = {}
@export_storage var dependencies: Dictionary = {}
@export_storage var provenance: Dictionary = {}
@export_storage var revision := 0
@export_storage var validated_revision := -1
@export_storage var validation_error := ""
@export_storage var cached_entities: Array = []
@export_storage var cached_geometry: Array = []
@export_storage var collision_geometry: Array = []
@export_storage var cache_path := ""
@export_storage var legacy_snapshot: Dictionary = {}
@export_storage var compiled_snapshot: Dictionary = {}

static func from_xml(text: String) -> Dictionary:
	var parsed := Xml.parse(text)
	if not parsed.error.is_empty(): return parsed
	if parsed.tree.tag != "mujoco": return {"error":"Select an MJCF <mujoco> document"}
	var result := MjAuthorResource.new()
	result.document_id = Xml.uuid()
	result.tree = parsed.tree
	Xml.ensure_names(result.tree)
	result.normalize_geometries()
	return {"error":"", "design":result}

static func from_legacy(model: Resource) -> Dictionary:
	if not model or not model.get("snapshot") is Dictionary: return {"error":"Not a MuJoCo model resource"}
	return from_snapshot(model.snapshot,model.resource_path.get_base_dir(),model.provenance,model.dependencies)

static func from_snapshot(snapshot: Dictionary, directory := "", source_provenance := {}, source_dependencies := {}) -> Dictionary:
	if not snapshot.get("xml") is String or not snapshot.get("state",{}) is Dictionary or not snapshot.get("state",{}).get("qpos",[]) is Array: return {"error":"Invalid legacy XML/state document"}
	var result := from_xml(snapshot.get("xml", ""))
	if not result.error.is_empty(): return result
	var design: MjAuthorResource = result.design
	for element in Xml.walk(design.tree):
		for key in element.get("attrs", {}):
			if key in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"]:
				var path: String = element.attrs[key]
				if not path.is_absolute_path() and not path.begins_with("res://"): element.attrs[key] = directory.path_join(path)
	design.provenance = source_provenance.duplicate(true)
	design.dependencies = source_dependencies.duplicate(true)
	design.legacy_snapshot = snapshot.duplicate(true)
	var positions: Array = snapshot.get("state", {}).get("qpos", [])
	var offset := 0
	for entity in design.entities():
		if entity.kind != "joint": continue
		var type: String = entity.attrs.get("type", "hinge")
		var count := 7 if type == "free" else 4 if type == "ball" else 1
		if offset + count <= positions.size(): design.initial_pose[entity.id] = positions.slice(offset, offset + count)
		offset += count
	return result

func author_snapshot() -> Dictionary:
	return {"format":format_version, "document_id":document_id, "tree":tree.duplicate(true), "initial_pose":initial_pose.duplicate(true), "dependencies":dependencies.duplicate(true), "provenance":provenance.duplicate(true), "revision":revision}

func restore_author(value: Dictionary) -> String:
	if value.get("format") != 1 or not value.get("tree") is Dictionary: return "Unsupported author document"
	var candidate: Dictionary = value.tree.duplicate(true)
	if candidate.get("tag") != "mujoco": return "Author document must contain a mujoco root"
	var identities := {}
	for element in Xml.walk(candidate):
		if not element.has("id") or identities.has(element.id): return "Missing or duplicate author identity"
		identities[element.id] = true
	format_version = 1
	document_id = value.get("document_id", Xml.uuid())
	tree = candidate
	initial_pose = value.get("initial_pose", {}).duplicate(true)
	dependencies = value.get("dependencies", {}).duplicate(true)
	provenance = value.get("provenance", {}).duplicate(true)
	revision = int(value.get("revision", 0))
	design_changed.emit()
	emit_changed()
	return ""

func xml() -> String:
	return Xml.write(tree)

func normalize_geometries() -> void:
	Xml.normalize_fromto(tree)
	var world := Xml.section(tree,"worldbody")
	if world.is_empty(): return
	for element in Xml.walk(world):
		if element.tag!="geom" or not element.attrs.has("fromto"): continue
		var normalized := {"tag":"geom","attrs":effective_attrs(element),"children":[]}
		Xml.normalize_fromto(normalized)
		if normalized.attrs.has("fromto"): continue
		for key in ["pos","quat","size"]: element.attrs[key]=normalized.attrs[key]
		for key in ["fromto","euler","axisangle","xyaxes","zaxis"]: element.attrs.erase(key)

func source_pose(attrs: Dictionary) -> Transform3D:
	return Xml.pose(attrs,compiler_degrees(),Xml.section(tree,"compiler").get("attrs",{}).get("eulerseq","xyz"))

func compiler_degrees() -> bool:
	return Xml.section(tree, "compiler").get("attrs", {}).get("angle", "degree") != "radian"

func entities() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var classes := {}
	for kind in ["body","geom","joint"]:
		classes[kind] = {}
		default_classes(kind, Xml.section(tree,"default"), {}, classes[kind])
	_collect(Xml.section(tree, "worldbody"), "", Transform3D.IDENTITY, [], result, classes, "main")
	return result

func default_classes(kind: String, block: Dictionary, inherited: Dictionary, result: Dictionary) -> void:
	var values := inherited.duplicate(true)
	for child in block.get("children", []):
		if child.tag == kind: values.merge(child.attrs, true)
	result[str(block.get("attrs", {}).get("class", "main"))] = values
	for child in block.get("children", []):
		if child.tag == "default": default_classes(kind, child, values, result)

func effective_attrs(element: Dictionary) -> Dictionary:
	var classes := {}
	var kind := "joint" if element.tag == "freejoint" else str(element.tag)
	default_classes(kind, Xml.section(tree,"default"), {}, classes)
	var class_name_value: String = element.attrs.get("class", "")
	var ancestor := Xml.parent(tree, element.id)
	while class_name_value.is_empty() and not ancestor.is_empty():
		class_name_value = ancestor.get("attrs", {}).get("childclass", "")
		ancestor = Xml.parent(tree, ancestor.get("id", ""))
	var values: Dictionary = classes.get(class_name_value if not class_name_value.is_empty() else "main", {}).duplicate(true)
	# freejoint deliberately ignores the joint default class in MJCF.
	if element.tag == "freejoint": values = {"type":"free"}
	values.merge(element.attrs, true)
	if kind == "geom" and values.has("mesh") and not values.has("type"): values.type = "mesh"
	return values

func _collect(element: Dictionary, parent_id: String, frame_pose: Transform3D, frames: Array, output: Array[Dictionary], classes: Dictionary, inherited_class: String) -> void:
	if element.is_empty(): return
	var kind := Xml.entity_kind(element)
	var next_parent := parent_id
	var next_pose := frame_pose
	var next_frames := frames
	if element.tag == "frame":
		next_pose = frame_pose * source_pose(element.attrs)
		next_frames = frames.duplicate()
		next_frames.append(element.id)
	elif not kind.is_empty():
		var class_name_value: String = element.attrs.get("class", inherited_class)
		var attrs: Dictionary = classes.get(kind,{}).get(class_name_value,{}).duplicate(true)
		if element.tag == "freejoint": attrs = {"type":"free"}
		attrs.merge(element.attrs,true)
		if kind == "geom" and attrs.has("mesh") and not attrs.has("type"): attrs.type = "mesh"
		var editable := not attrs.has("fromto")
		for frame_id in frames:
			var frame_attrs: Dictionary = Xml.find(tree, frame_id).attrs
			if frame_attrs.has("scale") or frame_attrs.has("scaling") or frame_attrs.has("massscale") or frame_attrs.has("childclass"): editable = false
		output.append({"id":element.id, "kind":kind, "name":element.attrs.get("name", ""), "parent_id":parent_id, "attrs":attrs, "transform":frame_pose * source_pose(attrs), "frame_transform":frame_pose, "pose_editable":editable})
		if kind == "body":
			next_parent = element.id
			next_pose = Transform3D.IDENTITY
			next_frames = []
	for child in element.get("children", []): _collect(child, next_parent, next_pose, next_frames, output, classes, element.get("attrs",{}).get("childclass",inherited_class))

func entity(identity: String) -> Dictionary:
	for item in entities():
		if item.id == identity: return item
	return {}

func source_name(identity: String) -> String:
	return str(Xml.find(tree, identity).get("attrs", {}).get("name", ""))

func touch() -> void:
	revision += 1
	validation_error = ""
	design_changed.emit()
	emit_changed()

func fork() -> MjAuthorResource:
	var result := MjAuthorResource.new()
	result.restore_author(author_snapshot())
	result.document_id = Xml.uuid()
	result.cached_entities = cached_entities.duplicate(true)
	result.cached_geometry = cached_geometry.duplicate(true)
	result.collision_geometry = collision_geometry.duplicate(true)
	result.cache_path = cache_path
	result.validated_revision = validated_revision
	result.legacy_snapshot = legacy_snapshot.duplicate(true)
	result.compiled_snapshot = compiled_snapshot.duplicate(true)
	return result

func worker_xml() -> String:
	var copy := tree.duplicate(true)
	for element in Xml.walk(copy):
		for key in element.get("attrs", {}):
			if key in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"]:
				var path: String = element.attrs[key]
				if path.begins_with("res://"): element.attrs[key] = ProjectSettings.globalize_path(path)
	return Xml.write(copy)

func native_initial_pose() -> Dictionary:
	var result := {}
	for identity in initial_pose:
		var name := source_name(identity)
		if not name.is_empty(): result[name] = initial_pose[identity].duplicate() if initial_pose[identity] is Array else initial_pose[identity]
	return result

func runtime_xml() -> String:
	if compiled_snapshot.is_empty() or validated_revision != revision: return worker_xml()
	var parsed := Xml.parse(compiled_snapshot.get("xml", ""))
	if not parsed.error.is_empty(): return worker_xml()
	var assets := {}
	for element in Xml.walk(tree):
		if element.get("attrs", {}).has("name"): assets[str(element.tag) + ":" + str(element.attrs.name)] = element.attrs
	for element in Xml.walk(parsed.tree):
		var source: Dictionary = assets.get(str(element.tag) + ":" + str(element.get("attrs", {}).get("name", "")), {})
		for key in element.get("attrs", {}):
			if key in ["file", "fileleft", "fileright", "fileup", "filedown", "filefront", "fileback"] and source.has(key):
				var path: String = source[key]
				element.attrs[key] = ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
	return Xml.write(parsed.tree)
