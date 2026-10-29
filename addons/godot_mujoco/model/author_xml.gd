@tool
extends RefCounted
## A complete XML tree, rather than a projection of the visible physics nodes.
## Unknown elements, attributes, comments and text survive authoring operations.

static func uuid() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func parse(text: String) -> Dictionary:
	var parser := XMLParser.new()
	if parser.open_buffer(text.to_utf8_buffer()) != OK:
		return {"error":"Cannot read MJCF XML"}
	var root: Dictionary = {}
	var stack: Array[Dictionary] = []
	while true:
		var result := parser.read()
		if result == ERR_FILE_EOF: break
		if result != OK: return {"error":"Invalid XML near line %d" % parser.get_current_line()}
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var attrs := {}
				for index in parser.get_attribute_count():
					attrs[parser.get_attribute_name(index)] = parser.get_attribute_value(index)
				var element := {"tag":parser.get_node_name(), "attrs":attrs, "children":[], "id":uuid()}
				if stack.is_empty():
					if not root.is_empty(): return {"error":"XML has multiple roots"}
					root = element
				else: stack.back().children.append(element)
				if not parser.is_empty(): stack.append(element)
			XMLParser.NODE_ELEMENT_END:
				if stack.is_empty() or stack.back().tag != parser.get_node_name():
					return {"error":"Unbalanced XML element"}
				stack.pop_back()
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA, XMLParser.NODE_COMMENT:
				if not stack.is_empty():
					stack.back().children.append({"tag":"#comment" if parser.get_node_type() == XMLParser.NODE_COMMENT else "#text", "text":parser.get_node_data() if parser.get_node_type() == XMLParser.NODE_TEXT else parser.get_node_name()})
	if root.is_empty() or not stack.is_empty(): return {"error":"Incomplete XML document"}
	return {"error":"", "tree":root}

static func escaped(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")

static func write(element: Dictionary) -> String:
	var tag: String = element.get("tag", "")
	if tag == "#text": return escaped(element.get("text", ""))
	if tag == "#comment": return "<!--" + str(element.get("text", "")).replace("--", "- -") + "-->"
	var text := "<" + tag
	for key in element.get("attrs", {}): text += ' %s="%s"' % [key, escaped(str(element.attrs[key]))]
	if element.get("children", []).is_empty(): return text + "/>"
	text += ">"
	for child in element.children: text += write(child)
	return text + "</" + tag + ">"

static func walk(element: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = [element]
	for child in element.get("children", []):
		if not str(child.tag).begins_with("#"): result.append_array(walk(child))
	return result

static func find(element: Dictionary, identity: String) -> Dictionary:
	if identity.is_empty(): return {}
	if element.get("id", "") == identity: return element
	for child in element.get("children", []):
		var found := find(child, identity)
		if not found.is_empty(): return found
	return {}

static func parent(element: Dictionary, identity: String) -> Dictionary:
	for child in element.get("children", []):
		if child.get("id", "") == identity: return element
		var found := parent(child, identity)
		if not found.is_empty(): return found
	return {}

static func section(tree: Dictionary, tag: String, create := false) -> Dictionary:
	for child in tree.get("children", []):
		if child.tag == tag: return child
	if not create: return {}
	var result := {"tag":tag, "attrs":{}, "children":[], "id":uuid()}
	tree.children.append(result)
	return result

static func numbers(value: String) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for part in value.replace("\t", " ").replace("\n", " ").split(" ", false):
		if not part.is_valid_float(): return PackedFloat64Array()
		result.append(part.to_float())
	return result

static func numeric_text(values: Variant) -> String:
	if values is Vector3: values = [values.x, values.y, values.z]
	elif values is Vector2: values = [values.x, values.y]
	var parts := PackedStringArray()
	for value in values: parts.append(JSON.stringify(float(value), "", false, true))
	return " ".join(parts)

static func entity_kind(element: Dictionary) -> String:
	if element.tag == "freejoint": return "joint"
	return element.tag if element.tag in ["body", "geom", "joint"] else ""

static func ensure_names(tree: Dictionary) -> void:
	# Preserve MuJoCo's file-derived asset names before copying files to hashes.
	for asset in section(tree,"asset").get("children",[]):
		if asset.tag in ["mesh","texture","hfield","skin"] and str(asset.attrs.get("name","")).is_empty() and not str(asset.attrs.get("file","")).is_empty():
			asset.attrs.name = str(asset.attrs.file).get_file().get_basename()
	var used := {}
	var world := section(tree, "worldbody")
	if world.is_empty(): return
	var all := walk(world)
	for element in all:
		var name: String = element.get("attrs", {}).get("name", "")
		if not name.is_empty(): used[entity_kind(element) + ":" + name] = true
	for element in all:
		var kind := entity_kind(element)
		if kind.is_empty() or element.attrs.has("name"): continue
		var name := kind + "_" + str(element.id).left(10)
		while used.has(kind + ":" + name): name += "_"
		element.attrs.name = name
		used[kind + ":" + name] = true

static func normalize_fromto(tree: Dictionary) -> void:
	for element in walk(tree):
		if element.tag != "geom" or not element.attrs.has("fromto"): continue
		var endpoints := numbers(element.attrs.fromto)
		if endpoints.size() != 6: continue
		var start := Vector3(endpoints[0], endpoints[1], endpoints[2])
		var end := Vector3(endpoints[3], endpoints[4], endpoints[5])
		var delta := end - start
		if delta.length() < 1e-12: continue
		var type: String = element.attrs.get("type", "capsule")
		if type not in ["capsule", "cylinder"]: continue
		var size := numbers(element.attrs.get("size", ""))
		if size.is_empty(): continue
		var rotation := Quaternion(Vector3(0, 0, 1), delta.normalized())
		element.attrs.pos = numeric_text((start + end) * 0.5)
		element.attrs.quat = numeric_text([rotation.w, rotation.x, rotation.y, rotation.z])
		element.attrs.size = numeric_text([size[0], delta.length() * 0.5])
		element.attrs.erase("fromto")

static func mj_vector(value: Vector3) -> Vector3:
	return Vector3(value.x, value.z, -value.y)

static func source_vector(value: Vector3) -> Vector3:
	return Vector3(value.x, -value.z, value.y)

static func mj_basis(value: Basis) -> Basis:
	var conversion := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	return conversion * value * conversion.transposed()

static func source_basis(value: Basis) -> Basis:
	var conversion := Basis(Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP)
	return conversion.transposed() * value * conversion

static func pose(attrs: Dictionary, degrees := false, sequence := "xyz") -> Transform3D:
	var position := numbers(attrs.get("pos", "0 0 0"))
	var rotation := Quaternion.IDENTITY
	if attrs.has("quat"):
		var q := numbers(attrs.quat)
		if q.size() == 4: rotation = Quaternion(q[1], q[2], q[3], q[0]).normalized()
	elif attrs.has("axisangle"):
		var q := numbers(attrs.axisangle)
		if q.size() == 4 and Vector3(q[0], q[1], q[2]).length() > 1e-12:
			rotation = Quaternion(Vector3(q[0], q[1], q[2]).normalized(), deg_to_rad(q[3]) if degrees else q[3])
	elif attrs.has("euler"):
		var q := numbers(attrs.euler)
		if q.size() == 3:
			var angles := Vector3(q[0], q[1], q[2]) * (PI / 180.0 if degrees else 1.0)
			for index in mini(sequence.length(),3):
				var axis: Vector3 = {"x":Vector3.RIGHT,"y":Vector3.UP,"z":Vector3.BACK}.get(sequence[index].to_lower(),Vector3.RIGHT)
				var q_axis := Quaternion(axis,angles[index])
				rotation = rotation*q_axis if sequence[index]==sequence[index].to_lower() else q_axis*rotation
	elif attrs.has("xyaxes"):
		var q := numbers(attrs.xyaxes)
		if q.size()==6:
			var x := Vector3(q[0],q[1],q[2]).normalized()
			var y := Vector3(q[3],q[4],q[5]); y=(y-x*y.dot(x)).normalized()
			if x.length_squared()>.5 and y.length_squared()>.5: rotation=Basis(x,y,x.cross(y)).get_rotation_quaternion()
	elif attrs.has("zaxis"):
		var q := numbers(attrs.zaxis)
		if q.size() == 3 and Vector3(q[0], q[1], q[2]).length() > 1e-12:
			rotation = Quaternion(Vector3.BACK, Vector3(q[0], q[1], q[2]).normalized())
	return Transform3D(mj_basis(Basis(rotation)), mj_vector(Vector3(position[0], position[1], position[2])) if position.size() == 3 else Vector3.ZERO)

static func write_pose(attrs: Dictionary, transform: Transform3D) -> void:
	attrs.pos = numeric_text(source_vector(transform.origin))
	var q := source_basis(transform.basis).get_rotation_quaternion().normalized()
	attrs.quat = numeric_text([q.w, q.x, q.y, q.z])
	for key in ["euler", "axisangle", "xyaxes", "zaxis", "fromto"]: attrs.erase(key)

static func clone_ids(element: Dictionary, mapping: Dictionary) -> void:
	if element.has("id"):
		var old: String = element.id
		element.id = uuid()
		mapping[old] = element.id
	for child in element.get("children", []): clone_ids(child, mapping)
