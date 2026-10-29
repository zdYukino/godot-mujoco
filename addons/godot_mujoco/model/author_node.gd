@tool
extends Node3D
const Xml = preload("author_xml.gd")
@export_storage var entity_id := ""
var synchronizing := false
var displayed_transform := Transform3D.IDENTITY
var motion_correction := Transform3D.IDENTITY
var source_model: WeakRef
var inspector_schema: Array[Dictionary] = []
var inspector_schema_initialized := false

func author_kind() -> String:
	return ""

func author_model() -> Node:
	var node := get_parent()
	while node:
		if node.has_method("apply_author_command"): return node
		node = node.get_parent()
	return null

func _ready() -> void:
	set_notify_local_transform(Engine.is_editor_hint())
	if Engine.is_editor_hint(): refresh_inspector_schema()

func refresh_inspector_schema() -> void:
	# Rebuilding the Inspector destroys active color pickers and slider drags.
	# Values are read through _get(); only a changed field layout needs a rebuild.
	var fields: Array[Dictionary] = []
	for field in get_property_list():
		if String(field.name).begins_with("mjcf/"): fields.append(field)
	var layout_changed := inspector_schema_initialized and fields != inspector_schema
	inspector_schema = fields
	inspector_schema_initialized = true
	if layout_changed: notify_property_list_changed()

func _notification(what: int) -> void:
	if what != NOTIFICATION_LOCAL_TRANSFORM_CHANGED or synchronizing or not Engine.is_editor_hint(): return
	# Godot may deliver this notification after set_display_transform returns.
	# A display refresh must never become a fresh author edit.
	if transform.is_equal_approx(displayed_transform): return
	var model := author_model()
	if model and model.get("author_scene"):
		model.author_scene.node_transform_changed(self)

func item() -> Dictionary:
	var model := author_model()
	return model.design.entity(entity_id) if model and model.get("design") else {}

func property(name: String, type: int, hint := PROPERTY_HINT_NONE, hint_string := "", readonly := false) -> Dictionary:
	return {"name":"mjcf/" + name, "type":type, "hint":hint, "hint_string":hint_string, "usage":PROPERTY_USAGE_EDITOR | (PROPERTY_USAGE_READ_ONLY if readonly else 0)}

func _get_property_list() -> Array[Dictionary]:
	var entity := item()
	if entity.is_empty(): return []
	var fields: Array[Dictionary] = [property("name", TYPE_STRING)]
	match author_kind():
		"body":
			fields.append(property("inertia_mode", TYPE_STRING, PROPERTY_HINT_ENUM, "automatic,explicit"))
			fields.append(property("mass", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0.000001,1000000,0.01,or_greater,suffix:kg"))
			fields.append(property("inertia", TYPE_VECTOR3))
			fields.append(property("center_of_mass", TYPE_VECTOR3))
			fields.append(property("inertial_orientation", TYPE_QUATERNION))
		"geom":
			fields.append(property("shape", TYPE_STRING, PROPERTY_HINT_ENUM, "plane,sphere,box,cylinder,capsule,ellipsoid,mesh,sdf,hfield", true))
			var shape: String = entity.attrs.get("type", "sphere")
			if shape in ["sphere", "cylinder", "capsule"]: fields.append(property("radius", TYPE_FLOAT, PROPERTY_HINT_RANGE, ".000001,100,0.001,or_greater,suffix:m"))
			if shape in ["cylinder", "capsule"]: fields.append(property("height", TYPE_FLOAT, PROPERTY_HINT_RANGE, ".000001,100,0.001,or_greater,suffix:m"))
			if shape in ["box", "ellipsoid"]: fields.append(property("dimensions", TYPE_VECTOR3))
			if shape == "plane": fields.append(property("display_extent", TYPE_VECTOR2))
			if shape in ["mesh","sdf"]:
				var assets := []
				for asset in Xml.section(author_model().design.tree,"asset").get("children",[]):
					if asset.tag=="mesh": assets.append(str(asset.attrs.get("name","")))
				fields.append(property("mesh",TYPE_STRING,PROPERTY_HINT_ENUM,",".join(assets)))
				fields.append(property("mesh_file",TYPE_STRING,PROPERTY_HINT_FILE,"*.obj,*.stl"))
				fields.append(property("mesh_scale", TYPE_VECTOR3))
			fields.append(property("density", TYPE_FLOAT, PROPERTY_HINT_RANGE, ".000001,100000,0.1,or_greater,suffix:kg/m³"))
			fields.append(property("friction", TYPE_VECTOR3))
			fields.append(property("collision_layer", TYPE_INT, PROPERTY_HINT_LAYERS_3D_PHYSICS))
			fields.append(property("collision_mask", TYPE_INT, PROPERTY_HINT_LAYERS_3D_PHYSICS))
			fields.append(property("margin", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,10,.001,or_greater,suffix:m"))
		"joint":
			fields.append(property("type", TYPE_STRING, PROPERTY_HINT_ENUM, "hinge,slide,ball,free"))
			var type: String = entity.attrs.get("type", "hinge")
			if type in ["hinge", "slide"]:
				fields.append(property("axis", TYPE_VECTOR3))
				fields.append(property("limited", TYPE_BOOL))
				fields.append(property("limits", TYPE_VECTOR2))
				fields.append(property("damping", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1000,.01,or_greater"))
				fields.append(property("friction_loss", TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,1000,.01,or_greater"))
				fields.append(property("initial_position", TYPE_FLOAT))
			if type == "ball": fields.append(property("initial_orientation", TYPE_QUATERNION))
			for actuator in joint_actuators():
				var prefix: String = "actuators/" + str(actuator.attrs.get("name",actuator.tag)) + "/"
				fields.append(property(prefix + "name", TYPE_STRING, PROPERTY_HINT_NONE, "", true))
				for parameter in actuator_parameters(actuator): fields.append(property(prefix + parameter, TYPE_FLOAT))
	fields.append(property("source_pose_editable", TYPE_BOOL, PROPERTY_HINT_NONE, "", true))
	return fields

func joint_actuators() -> Array:
	var model := author_model()
	if not model or not model.design: return []
	return Xml.section(model.design.tree, "actuator").get("children", []).filter(func(a): return a.get("attrs", {}).get("joint", "") == item().get("name", ""))

func actuator_parameters(actuator: Dictionary) -> Array:
	match actuator.tag:
		"position": return ["kp", "kv"]
		"velocity": return ["kv"]
		"intvelocity": return ["kp", "kv"]
	return []

func native_properties() -> Dictionary:
	var model := author_model()
	if not model or not model.get("design"): return {}
	for entity in model.design.cached_entities:
		if entity.kind == author_kind() and entity.name == model.design.source_name(entity_id): return entity.properties
	return {}

func values(key: String, fallback: String) -> PackedFloat64Array:
	return Xml.numbers(item().get("attrs", {}).get(key, fallback))

func _get(property_name: StringName) -> Variant:
	var key := String(property_name).trim_prefix("mjcf/")
	if key == String(property_name): return null
	var entity := item()
	if entity.is_empty(): return null
	var attrs: Dictionary = entity.attrs
	var compiled := native_properties()
	var model := author_model()
	if key.begins_with("actuators/"):
		var parts := key.split("/")
		var actuator: Dictionary = joint_actuators().filter(func(a):return a.attrs.get("name",a.tag)==parts[1])[0]
		return actuator.attrs.get("name", actuator.tag) if parts[2] == "name" else float(actuator.attrs.get(parts[2], "0"))
	match key:
		"name": return entity.name
		"source_pose_editable": return entity.pose_editable
		"shape": return attrs.get("type", "sphere")
		"type": return "free" if Xml.find(model.design.tree, entity_id).tag == "freejoint" else attrs.get("type", "hinge")
		"inertia_mode": return "automatic" if Xml.section(Xml.find(model.design.tree, entity_id), "inertial").is_empty() else "explicit"
		"mass":
			var inertial := Xml.section(Xml.find(model.design.tree, entity_id), "inertial")
			return float(inertial.get("attrs", {}).get("mass", compiled.get("mass", 1.0)))
		"inertia":
			var inertial := Xml.section(Xml.find(model.design.tree, entity_id), "inertial")
			var v: Variant = Xml.numbers(inertial.attrs.diaginertia) if inertial.get("attrs", {}).has("diaginertia") else compiled.get("inertia", [1.0, 1.0, 1.0])
			return Vector3(v[0], v[1], v[2])
		"center_of_mass":
			var inertial := Xml.section(Xml.find(model.design.tree, entity_id), "inertial")
			var v: Variant = Xml.numbers(inertial.attrs.pos) if inertial.get("attrs", {}).has("pos") else compiled.get("ipos", [0.0, 0.0, 0.0])
			return Xml.mj_vector(Vector3(v[0], v[1], v[2]))
		"inertial_orientation":
			var inertial := Xml.section(Xml.find(model.design.tree, entity_id), "inertial")
			var v: Variant = Xml.numbers(inertial.attrs.quat) if inertial.get("attrs", {}).has("quat") else compiled.get("iquat", [1.0,0.0,0.0,0.0])
			return Xml.mj_basis(Basis(Quaternion(v[1],v[2],v[3],v[0]))).get_rotation_quaternion()
		"radius":
			var size := values("size", ".1")
			return size[0] if size.size() else 0.1
		"height":
			var size := values("size", ".1 .1")
			return 2.0 * ((size[1] if size.size() > 1 else 0.1) + (size[0] if attrs.get("type") == "capsule" else 0.0))
		"dimensions":
			var size := values("size", ".1 .1 .1")
			return Vector3(size[0], size[2] if size.size() > 2 else 0.1, size[1] if size.size() > 1 else 0.1) * 2.0
		"display_extent":
			var size := values("size", "5 5 .1")
			return Vector2(size[0], size[1]) * 2.0
		"mesh": return attrs.get("mesh","")
		"mesh_file":
			for mesh in Xml.section(model.design.tree,"asset").get("children",[]):
				if mesh.tag=="mesh" and mesh.attrs.get("name")==attrs.get("mesh"): return mesh.attrs.get("file","")
			return ""
		"mesh_scale":
			for mesh in Xml.section(model.design.tree, "asset").get("children", []):
				if mesh.tag == "mesh" and mesh.attrs.get("name") == attrs.get("mesh"):
					var size := Xml.numbers(mesh.attrs.get("scale", "1 1 1"))
					return Vector3(size[0], size[2], size[1])
			return Vector3.ONE
		"friction":
			var v := values("friction", "1 .005 .0001")
			return Vector3(v[0], v[1] if v.size() > 1 else .005, v[2] if v.size() > 2 else .0001)
		"density": return float(attrs.get("density", "1000"))
		"collision_layer": return int(attrs.get("contype", "1"))
		"collision_mask": return int(attrs.get("conaffinity", "1"))
		"margin": return float(attrs.get("margin", "0"))
		"axis":
			var v := values("axis", "0 0 1")
			return entity.frame_transform.basis * Xml.mj_vector(Vector3(v[0], v[1], v[2]))
		"limited": return attrs.get("limited", "auto") == "true" or (attrs.get("limited", "auto") == "auto" and attrs.has("range"))
		"limits":
			var v := values("range", "-1 1")
			return Vector2(v[0], v[1]) * (180.0 / PI if attrs.get("type", "hinge") == "hinge" and not model.design.compiler_degrees() else 1.0)
		"damping": return float(attrs.get("damping", "0").split(" ")[0])
		"friction_loss": return float(attrs.get("frictionloss", "0"))
		"initial_position":
			var v: Array = model.design.initial_pose.get(entity_id, [0.0])
			return float(v[0]) * (180.0 / PI if attrs.get("type", "hinge") == "hinge" else 1.0)
		"initial_orientation":
			var v: Array = model.design.initial_pose.get(entity_id, [1.0, 0.0, 0.0, 0.0])
			return Xml.mj_basis(Basis(Quaternion(v[1], v[2], v[3], v[0]))).get_rotation_quaternion()
	return null

func _set(property_name: StringName, value: Variant) -> bool:
	var key := String(property_name).trim_prefix("mjcf/")
	if key == String(property_name): return false
	var model := author_model()
	if not model or not model.get("design"): return false
	var command := {"op":"set", "id":entity_id, "values":{}}
	var attrs: Dictionary = item().attrs
	if key.begins_with("actuators/"):
		var parts := key.split("/")
		model.apply_author_command({"op":"actuator", "id":entity_id, "actuator_id":joint_actuators().filter(func(a):return a.attrs.get("name",a.tag)==parts[1])[0].id, "values":{parts[2]:value}}, false)
		return true
	match key:
		"name": command = {"op":"rename", "id":entity_id, "name":value}
		"type": command = {"op":"set_joint_type", "id":entity_id, "type":value}
		"mass", "inertia", "center_of_mass", "inertial_orientation": command = {"op":"inertial", "id":entity_id, "field":key, "value":value}
		"inertia_mode": command = {"op":"inertia_mode", "id":entity_id, "value":value}
		"mesh": command.values.mesh=value
		"mesh_file":
			var plugin: Node=(EditorInterface.get_base_control().get_meta("mujoco_author_plugin") if EditorInterface.get_base_control().has_meta("mujoco_author_plugin") else null)
			if plugin: plugin.add_mesh_asset(model,item().parent_id,str(value),entity_id)
			return true
		"mesh_scale": command = {"op":"mesh_scale", "id":entity_id, "value":value}
		"radius", "height", "dimensions":
			var size := values("size", ".1 .1 .1")
			if key == "radius": size[0] = float(value)
			elif key == "height":
				if size.size() < 2: size.resize(2)
				size[1] = float(value) * 0.5 - (size[0] if attrs.get("type") == "capsule" else 0.0)
			else: size = PackedFloat64Array([value.x * .5, value.z * .5, value.y * .5])
			command.values.size = Array(size)
		"display_extent":
			var size := values("size", "5 5 .1")
			command.values.size = [value.x*.5,value.y*.5,size[2] if size.size() > 2 else .1]
		"axis":
			if value.length() < 1e-10: return false
			var frame: Transform3D = item().frame_transform
			command.values.axis = Xml.source_vector(frame.basis.inverse() * value.normalized())
		"limits":
			var v: Vector2 = value * (PI / 180.0 if attrs.get("type", "hinge") == "hinge" and not model.design.compiler_degrees() else 1.0)
			command.values.range = [v.x, v.y]
		"initial_position": command = {"op":"initial_pose", "id":entity_id, "value":[float(value) * (PI / 180.0 if attrs.get("type", "hinge") == "hinge" else 1.0)]}
		"initial_orientation":
			var q := Xml.source_basis(Basis(value)).get_rotation_quaternion()
			command = {"op":"initial_pose", "id":entity_id, "value":[q.w,q.x,q.y,q.z]}
		"friction_loss": command.values.frictionloss = value
		"collision_layer": command.values.contype = value
		"collision_mask": command.values.conaffinity = value
		"density":
			command.values.density = value
			command.values.mass = null
		"friction", "margin", "limited", "damping": command.values[key] = value
		_: return false
	model.apply_author_command(command, false)
	return true

func set_display_transform(value: Transform3D) -> void:
	synchronizing = true
	transform = value
	displayed_transform = value
	synchronizing = false
