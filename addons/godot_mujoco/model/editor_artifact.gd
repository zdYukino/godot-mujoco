@tool
extends RefCounted
## Portable preview qualification. This helper has no Model/Author dependency.
const SCHEMA := 3
const MAX_STORAGE_NUMBER_ROUNDS := 32
# Bump when compilation, preview transforms/materials, validation or generated
# resource semantics change, even if Godot and MuJoCo versions stay the same.
const PRODUCER_CONTRACT := 1
static var _producer: Dictionary = {}

static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys(); keys.sort_custom(func(a,b): return str(a) < str(b))
		for key in keys: result[str(key)] = canonical(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(canonical(item))
		return result
	return value

static func digest(value: Variant) -> String:
	return var_to_bytes(canonical(value)).hex_encode().sha256_text()

static func producer() -> Dictionary:
	if _producer.is_empty():
		# MjWorld's empty constructor/version getter never compile a model.
		var world: Object = ClassDB.instantiate("MjWorld")
		var version: String = world.get_mujoco_version() if world else "unavailable"
		if world: world.free()
		_producer = {"contract":PRODUCER_CONTRACT, "author_format":1, "godot":Engine.get_version_info(), "mujoco":version}
	return _producer.duplicate(true)

static func payload(design: Resource) -> Dictionary:
	return {"entities":design.cached_entities, "geometry":design.cached_geometry, "collision_geometry":design.collision_geometry, "collision_stats":design.collision_stats, "snapshot":design.compiled_snapshot}

static func result_payload(result: Dictionary) -> Dictionary:
	var value := {}
	for key in ["entities", "geometry", "collision_geometry", "collision_stats", "snapshot"]:
		if result.has(key): value[key] = result[key]
	return value

static func payload_digest(value: Dictionary) -> String:
	# The engine's numeric text parser can change a native double on resource
	# roundtrip. Qualify its stable storage representation, never an arbitrary
	# decimal quantizer that can put equivalent values on opposite rounding ties.
	# This changes only derived identity, not payload data or exact author hashes.
	return digest(_payload_storage_value(value))

static func _number_storage_text(value: float, packed64: bool) -> String:
	# The Variant writer has a compact float32-representable branch that the
	# scientific formatter does not model. Keep packed elements in their actual
	# constructor context rather than assuming scalar formatting is identical.
	return var_to_str(PackedFloat64Array([value])) if packed64 else var_to_str(value)

static func _float_storage_value(value: float, packed64 := false) -> Array:
	if value == 0.0: return ["float", "0"]
	if not is_finite(value): return ["float", _number_storage_text(value, packed64)]
	var text := _number_storage_text(value, packed64)
	var seen := {}
	var history: Array[String] = []
	for attempt in MAX_STORAGE_NUMBER_ROUNDS:
		if seen.has(text):
			# A repeated parse/write cycle has the same representative regardless
			# of which serialized member was the starting value.
			var cycle := history.slice(int(seen[text])); cycle.sort()
			return ["float", cycle[0]]
		seen[text] = history.size(); history.append(text)
		var parsed: Variant = str_to_var(text)
		if packed64:
			if not parsed is PackedFloat64Array or parsed.size() != 1: return ["float_unstable", var_to_bytes(value)]
			parsed = parsed[0]
		# Do not bless a finite nonzero value that text storage loses altogether.
		if not parsed is float or not is_finite(parsed) or parsed == 0.0: return ["float_unstable", var_to_bytes(value)]
		var next := _number_storage_text(parsed, packed64)
		if next == text: return ["float", text]
		text = next
	# Unsupported/nonconvergent representations keep exact identity, producing
	# a safe miss on a changed saved value instead of unbounded work/tolerance.
	return ["float_unstable", var_to_bytes(value)]

static func _payload_storage_value(value: Variant) -> Variant:
	# Tag every container/value, so a lookalike Dictionary/Array cannot collide
	# with the normalized representation of a different Variant type.
	if value is float: return _float_storage_value(value)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _payload_storage_value(value[key])
		return ["dictionary", result]
	if value is PackedFloat64Array:
		var result := []
		for item in value: result.append(_float_storage_value(item, true))
		return ["float64_array", result]
	if value is Array:
		var result := []
		for item in value: result.append(_payload_storage_value(item))
		return ["array", result]
	var components: Array = []
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_QUATERNION, TYPE_COLOR:
			var count: int = {TYPE_VECTOR2:2, TYPE_VECTOR3:3, TYPE_VECTOR4:4, TYPE_QUATERNION:4, TYPE_COLOR:4}[typeof(value)]
			for index in count: components.append(_payload_storage_value(float(value[index])))
		TYPE_BASIS:
			for axis in [value.x, value.y, value.z]: components.append(_payload_storage_value(axis))
		TYPE_TRANSFORM3D: components = [_payload_storage_value(value.basis), _payload_storage_value(value.origin)]
		TYPE_TRANSFORM2D: components = [_payload_storage_value(value.x), _payload_storage_value(value.y), _payload_storage_value(value.origin)]
		TYPE_AABB: components = [_payload_storage_value(value.position), _payload_storage_value(value.size)]
		TYPE_PLANE: components = [_payload_storage_value(value.normal), _payload_storage_value(value.d)]
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			for item in value: components.append(_payload_storage_value(item))
		_: return ["value", typeof(value), value]
	# Component normalization also makes native negative zero equal the positive
	# zero written by Godot's text resource serializer.
	return ["components", typeof(value), components]

static func project_path(path: Variant) -> bool:
	return path is String and path.begins_with("res://") and not path.contains("..") and not path.contains("\\") and not path.trim_prefix("res://").split("/").has("")

static func preview_paths(value: Dictionary) -> Array:
	var paths := {}
	for key in ["geometry", "collision_geometry"]:
		var geometry: Variant = value.get(key, [])
		if not geometry is Array: continue
		for geom in geometry:
			if not geom is Dictionary: continue
			for field in ["mesh_path", "texture_path"]:
				if geom.get(field) is String: paths[geom[field]] = true
	var result := paths.keys(); result.sort()
	return result

static func payload_complete(value: Dictionary) -> bool:
	for key in ["entities", "geometry", "collision_geometry", "collision_stats"]:
		if not value.get(key) is Array: return false
	if not value.get("snapshot") is Dictionary or not value.snapshot.get("xml") is String or value.snapshot.xml.is_empty(): return false
	for entity in value.entities:
		if not entity_record(entity): return false
	for geom in value.geometry:
		if not geometry_record(geom) or not project_path(geom.get("mesh_path")): return false
	for key in ["geometry", "collision_geometry"]:
		for geom in value[key]:
			if not geom is Dictionary: return false
			for field in ["mesh_path", "texture_path"]:
				if geom.has(field) and not project_path(geom[field]): return false
	for path in preview_paths(value):
		if not project_path(path): return false
	return true

static func entity_record(value: Variant) -> bool:
	return value is Dictionary and value.get("kind") is String and value.get("name") is String and value.get("properties") is Dictionary

static func geometry_record(value: Variant) -> bool:
	return value is Dictionary and value.get("name") is String and typeof(value.get("type")) == TYPE_INT and value.get("size") is Vector3 and value.get("source_size", value.size) is Vector3 and value.get("transform") is Transform3D and value.get("color", Color.WHITE) is Color and value.get("texture_repeat", Vector2.ONE) is Vector2

static func candidate_reason(author: Dictionary, context: Dictionary, value: Dictionary, stamp: Dictionary) -> String:
	if stamp.get("schema") != SCHEMA: return "missing or incompatible artifact schema"
	if stamp.get("producer") != producer(): return "preview producer changed"
	if stamp.get("author_digest") != digest(author): return "author content changed"
	if stamp.get("context_digest") != digest(context): return "world context or validation budget changed"
	if not payload_complete(value): return "preview payload is incomplete"
	if stamp.get("payload_digest") != payload_digest(value): return "preview payload changed"
	var files: Variant = stamp.get("preview_files")
	if not files is Dictionary: return "missing preview resource manifest"
	for path in files:
		if not project_path(path) or not files[path] is String or files[path].length() != 64: return "invalid preview resource manifest"
	var paths: Array = files.keys(); paths.sort()
	if paths != preview_paths(value): return "preview resource manifest changed"
	return ""

static func make_stamp(author: Dictionary, context: Dictionary, value: Dictionary, files: Dictionary) -> Dictionary:
	return {"schema":SCHEMA, "producer":producer(), "author_digest":digest(author), "context_digest":digest(context), "payload_digest":payload_digest(value), "preview_files":files}

static func observe_files(paths: Array) -> Dictionary:
	# Metadata schedules verification; it never replaces the worker's byte hashes.
	var result := {}
	for path in paths:
		if not project_path(path):
			result[path] = []; continue
		var file := FileAccess.open(path, FileAccess.READ)
		result[path] = [FileAccess.get_modified_time(path), file.get_length()] if file else []
	return result
