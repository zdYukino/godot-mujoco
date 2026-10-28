@tool
extends RefCounted
const Xml = preload("author_xml.gd")
const Author = preload("author_resource.gd")
const Appearance = preload("geom_appearance.gd")

static func kind_of(element: Dictionary, parent_tag := "") -> String:
	var kind := Xml.entity_kind(element)
	if not kind.is_empty(): return kind
	if parent_tag in ["actuator", "sensor", "tendon", "equality"]: return parent_tag
	return str(element.get("tag", ""))

static func references(element: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var attrs: Dictionary = element.get("attrs", {})
	var types := {"actuator":"actuator", "body":"body", "body1":"body", "body2":"body", "targetbody":"body", "joint":"joint", "joint1":"joint", "joint2":"joint", "jointinparent":"joint", "geom":"geom", "geom1":"geom", "geom2":"geom", "site":"site", "site1":"site", "site2":"site", "sidesite":"site", "refsite":"site", "cranksite":"site", "slidersite":"site", "tendon":"tendon", "tendon1":"tendon", "tendon2":"tendon"}
	for key in attrs:
		var kind: String = types.get(key, "")
		if key in ["objname", "name1", "name2"]: kind = attrs.get("objtype", "")
		if key == "refname": kind = attrs.get("reftype", "")
		if not kind.is_empty() and not str(attrs[key]).is_empty():
			result.append({"element":element, "key":key, "target":kind + ":" + str(attrs[key])})
	return result

static func all_references(element: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for child in Xml.walk(element): result.append_array(references(child))
	return result

static func names(tree: Dictionary, parent_tag := "") -> Dictionary:
	var result := {}
	var name: String = tree.get("attrs", {}).get("name", "")
	if not name.is_empty(): result[kind_of(tree, parent_tag) + ":" + name] = tree.get("id", "")
	for child in tree.get("children", []): result.merge(names(child, tree.get("tag", "")))
	return result

static func unique_name(tree: Dictionary, kind: String, desired: String) -> String:
	var used := names(tree)
	var result := desired
	var index := 2
	while used.has(kind + ":" + result):
		result = desired + "_" + str(index)
		index += 1
	return result

static func dependent_objects(tree: Dictionary, removed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var found := {}
	var targets := removed.duplicate()
	var changed := true
	while changed:
		changed = false
		for section_name in ["actuator", "sensor", "tendon", "equality", "contact", "custom"]:
			var section := Xml.section(tree, section_name)
			for object in section.get("children", []):
				if found.has(object.get("id", "")): continue
				for reference in all_references(object):
					if targets.has(reference.target):
						found[object.id] = true
						result.append(object)
						targets.merge(names(object, section_name))
						changed = true
						break
	# Camera/light targets and custom typed references can live in the body tree.
	for element in Xml.walk(tree):
		if element.tag not in ["camera", "light"] or found.has(element.id): continue
		for reference in references(element):
			if targets.has(reference.target):
				result.append(element)
				break
	return result

static func remove(tree: Dictionary, identity: String) -> void:
	var owner := Xml.parent(tree, identity)
	if owner.is_empty(): return
	for index in owner.children.size():
		if owner.children[index].get("id", "") == identity:
			owner.children.remove_at(index)
			return

static func rewrite(tree: Dictionary, replacements: Dictionary) -> void:
	for reference in all_references(tree):
		if replacements.has(reference.target): reference.element.attrs[reference.key] = replacements[reference.target]

static func world_pose(design: Resource, identity: String) -> Transform3D:
	var item: Dictionary = design.entity(identity)
	if item.is_empty(): return Transform3D.IDENTITY
	return world_pose(design, item.parent_id) * item.transform

static func execute(design: Resource, command: Dictionary) -> Dictionary:
	var before: Dictionary = design.author_snapshot()
	var candidate := Author.new()
	var error: String = candidate.restore_author(before)
	candidate.cached_entities = design.cached_entities.duplicate(true)
	if not error.is_empty(): return {"error":error}
	var result := _apply(candidate, command)
	if not result.error.is_empty() or result.get("confirmation_required", false): return result
	candidate.revision += 1
	result.before = before
	result.after = candidate.author_snapshot()
	return result

static func _apply(design: Resource, command: Dictionary) -> Dictionary:
	var result := {"error":"", "affected":[], "omitted":[]}
	var operation: String = command.get("op", "")
	var identity: String = command.get("id", "")
	var element := Xml.find(design.tree, identity)
	if operation.begins_with("add_"):
		var kind := operation.trim_prefix("add_")
		var owner := Xml.section(design.tree, "worldbody", true) if identity.is_empty() else element
		if owner.get("tag") not in ["worldbody", "body"]: return {"error":"Select a body or the model root as parent"}
		if kind not in ["body", "geom", "joint"]: return {"error":"Unknown author node type"}
		if kind == "joint" and owner.tag != "body": return {"error":"A joint must belong to a body"}
		var attrs := {"name":unique_name(design.tree, kind, command.get("name", kind))}
		if kind == "geom":
			var shape: String = command.get("type", "box")
			if shape not in ["plane", "sphere", "box", "cylinder", "capsule", "ellipsoid", "mesh"]: return {"error":"Use the map/terrain editor for this shape type"}
			attrs.type = shape
			attrs.size = {"plane":"5 5 .1", "sphere":".25", "box":".25 .25 .25", "cylinder":".25 .25", "capsule":".15 .25", "ellipsoid":".25 .3 .2"}.get(shape, "1 1 1")
			attrs.density = "1000"
			if shape == "mesh":
				if not command.has("mesh"): return {"error":"Choose a mesh asset"}
				attrs.mesh = command.mesh
		if kind == "joint": attrs.type = command.get("type", "hinge")
		var added := {"tag":kind, "id":Xml.uuid(), "attrs":attrs, "children":[]}
		owner.children.append(added)
		result.selected = added.id
		result.affected = [added.id]
		return result
	if element.is_empty() or Xml.entity_kind(element).is_empty(): return {"error":"Unknown author entity"}
	match operation:
		"appearance":
			var error := Appearance.apply(design, element, command.get("field", ""), command.get("value"))
			if not error.is_empty(): return {"error":error}
		"actuator":
			var actuator := Xml.find(design.tree, command.get("actuator_id", ""))
			if actuator.is_empty() or Xml.parent(design.tree, actuator.id).get("tag") != "actuator": return {"error":"Unknown actuator"}
			for key in command.get("values", {}):
				var value: Variant = command.values[key]
				actuator.attrs[key] = Xml.numeric_text(value) if value is Array or value is Vector3 else str(value)
		"inertia_mode":
			if Xml.entity_kind(element) != "body": return {"error":"Inertia belongs to a body"}
			if command.get("value") == "automatic":
				var inertial := Xml.section(element, "inertial")
				if not inertial.is_empty(): remove(design.tree, inertial.id)
			else:
				return _apply(design, {"op":"inertial", "id":identity, "field":"initialize"})
		"inertial":
			if Xml.entity_kind(element) != "body": return {"error":"Mass and inertia belong to a body"}
			if Xml.section(design.tree, "compiler").get("attrs", {}).get("inertiafromgeom", "auto") == "true": return {"error":"Source compiler forces geometry-derived inertia"}
			var inertial := Xml.section(element, "inertial", true)
			var compiled := {"mass":1.0, "inertia":[.001,.001,.001], "ipos":[0,0,0], "iquat":[1,0,0,0]}
			for item in design.cached_entities:
				if item.kind == "body" and item.name == element.attrs.name: compiled.merge(item.properties, true)
			if not inertial.attrs.has("mass"): inertial.attrs.mass = str(compiled.mass)
			if not inertial.attrs.has("pos"): inertial.attrs.pos = Xml.numeric_text(compiled.ipos)
			if not inertial.attrs.has("diaginertia"):
				inertial.attrs.diaginertia = Xml.numeric_text(compiled.inertia)
				inertial.attrs.quat = Xml.numeric_text(compiled.iquat)
				inertial.attrs.erase("fullinertia")
			match command.get("field"):
				"mass":
					var previous := float(inertial.attrs.mass)
					var moments := Xml.numbers(inertial.attrs.diaginertia)
					if previous > 0:
						for index in moments.size(): moments[index] *= float(command.value) / previous
					inertial.attrs.mass = str(command.value)
					inertial.attrs.diaginertia = Xml.numeric_text(moments)
				"inertia": inertial.attrs.diaginertia = Xml.numeric_text(command.value)
				"center_of_mass": inertial.attrs.pos = Xml.numeric_text(Xml.source_vector(command.value))
				"inertial_orientation":
					var basis := Xml.source_basis(Basis(command.value))
					var q := basis.get_rotation_quaternion()
					inertial.attrs.quat = Xml.numeric_text([q.w,q.x,q.y,q.z])
		"mesh_scale":
			var scale: Vector3 = command.get("value", Vector3.ONE)
			if not scale.is_finite() or scale.x <= 0 or scale.y <= 0 or scale.z <= 0: return {"error":"Mesh scale must be finite and positive"}
			var assets := Xml.section(design.tree, "asset")
			var mesh := {}
			for asset in assets.get("children", []):
				if asset.tag == "mesh" and asset.attrs.get("name") == element.attrs.get("mesh"): mesh = asset
			if mesh.is_empty(): return {"error":"Missing mesh asset"}
			if mesh.get("scale_owner", "") != identity:
				mesh = mesh.duplicate(true)
				mesh.id = Xml.uuid()
				mesh.attrs.name = unique_name(design.tree, "mesh", element.attrs.name + "_mesh")
				mesh.scale_owner = identity
				assets.children.append(mesh)
				element.attrs.mesh = mesh.attrs.name
			mesh.attrs.scale = Xml.numeric_text([scale.x, scale.z, scale.y])
		"rename":
			var label: String = command.get("name", "").strip_edges()
			var kind := Xml.entity_kind(element)
			var old: String = element.attrs.name
			if label.is_empty(): return {"error":"Model names cannot be empty"}
			if label != old and names(design.tree).has(kind + ":" + label): return {"error":"That name is already used by this entity type"}
			rewrite(design.tree, {kind + ":" + old:label})
			element.attrs.name = label
		"delete", "set_joint_type":
			if operation == "set_joint_type" and Xml.entity_kind(element) != "joint": return {"error":"Select a joint"}
			var dependents := dependent_objects(design.tree, names(element))
			if not dependents.is_empty() and not command.get("confirmed", false):
				var impacts: Array = []
				for item in dependents: impacts.append({"id":item.id, "type":item.tag, "name":item.attrs.get("name", item.tag)})
				return {"error":"", "confirmation_required":true, "impacts":impacts}
			for dependent in dependents: remove(design.tree, dependent.id)
			if operation == "delete":
				for item in Xml.walk(element):
					design.initial_pose.erase(item.get("id", ""))
				remove(design.tree, identity)
			else:
				var type: String = command.get("type", "hinge")
				if type not in ["hinge", "slide", "ball", "free"]: return {"error":"Unknown joint type"}
				element.tag = "joint"
				element.attrs.type = type
				if type in ["free", "ball"]:
					for key in ["axis", "range", "limited"]: element.attrs.erase(key)
				design.initial_pose.erase(identity)
			result.affected = [identity]
		"duplicate":
			var copy: Dictionary = element.duplicate(true)
			var original_names := names(element)
			var replacements := {}
			var ids := {}
			Xml.clone_ids(copy, ids)
			var reserved := names(design.tree)
			for item in Xml.walk(copy):
				if not item.get("attrs", {}).has("name"): continue
				var kind := kind_of(item)
				var old: String = item.attrs.name
				var label := old + "_copy"
				while reserved.has(kind + ":" + label): label += "_2"
				reserved[kind + ":" + label] = true
				replacements[kind + ":" + old] = label
				item.attrs.name = label
			rewrite(copy, replacements)
			Xml.parent(design.tree, identity).children.append(copy)
			for old_id in ids:
				if design.initial_pose.has(old_id): design.initial_pose[ids[old_id]] = design.initial_pose[old_id].duplicate() if design.initial_pose[old_id] is Array else design.initial_pose[old_id]
			var dependencies := []
			for section_name in ["actuator","sensor","tendon","equality","contact"]:
				for dependency in Xml.section(design.tree,section_name).get("children",[]):
					dependencies.append({"section":section_name,"source":dependency})
			var available := original_names.duplicate()
			var selected := {}
			var progress := true
			while progress:
				progress = false
				for entry in dependencies:
					var dependency: Dictionary = entry.source
					if selected.has(dependency.id): continue
					var refs := all_references(dependency)
					if refs.is_empty() or not refs.all(func(ref):return available.has(ref.target)): continue
					selected[dependency.id]=true; available.merge(names(dependency,entry.section)); progress=true
			for entry in dependencies:
				var dependency: Dictionary = entry.source
				if not selected.has(dependency.id):
					if all_references(dependency).any(func(ref):return available.has(ref.target)): result.omitted.append(dependency.attrs.get("name",dependency.tag))
					continue
				if dependency.attrs.has("name"):
					var old: String = dependency.attrs.name
					var label := unique_name(design.tree,entry.section,old+"_copy")
					while reserved.has(str(entry.section)+":"+label): label+="_2"
					reserved[str(entry.section)+":"+label]=true
					replacements[str(entry.section)+":"+old]=label
			for entry in dependencies:
				if not selected.has(entry.source.id): continue
				var dependency: Dictionary=entry.source.duplicate(true)
				Xml.clone_ids(dependency,{})
				if dependency.attrs.has("name"): dependency.attrs.name=replacements[str(entry.section)+":"+str(dependency.attrs.name)]
				rewrite(dependency,replacements)
				Xml.section(design.tree,entry.section).children.append(dependency)

			result.selected = copy.id
			result.affected = ids.values()
			result.id_map = ids
		"reparent":
			var target_id: String = command.get("parent_id", "")
			var target := Xml.section(design.tree, "worldbody", true) if target_id.is_empty() else Xml.find(design.tree, target_id)
			if target.get("tag") not in ["body", "worldbody"]: return {"error":"Author nodes must belong to a body or world"}
			if Xml.entity_kind(element) == "joint" and target.tag != "body": return {"error":"A joint must belong to a body"}
			if not Xml.find(element, target_id).is_empty(): return {"error":"Cannot move a body inside its own subtree"}
			var visible: Dictionary = design.entity(identity)
			if not visible.get("pose_editable", true): return {"error":"This source frame cannot be reparented without changing its physical meaning"}
			var pose := world_pose(design, target_id).affine_inverse() * world_pose(design, identity)
			remove(design.tree, identity)
			target.children.append(element)
			if Xml.entity_kind(element) == "joint":
				element.attrs.pos = Xml.numeric_text(Xml.source_vector(pose.origin))
				if visible.attrs.get("type","hinge") in ["hinge","slide"]:
					var v := Xml.numbers(visible.attrs.get("axis","0 0 1"))
					var axis: Vector3 = world_pose(design,target_id).basis.inverse() * world_pose(design,visible.parent_id).basis * visible.frame_transform.basis * Xml.mj_vector(Vector3(v[0],v[1],v[2]))
					element.attrs.axis=Xml.numeric_text(Xml.source_vector(axis.normalized()))
			else: Xml.write_pose(element.attrs, pose)
			result.affected = [identity]
		"pose":
			var item: Dictionary = design.entity(identity)
			if not item.get("pose_editable", true): return {"error":"Complex source frame scaling/inheritance makes this pose read-only"}
			var transform: Transform3D = command.get("transform", Transform3D.IDENTITY)
			var scale := transform.basis.get_scale()
			if not scale.is_equal_approx(Vector3.ONE): return {"error":"Edit physical dimensions; body/joint transforms cannot contain scale or shear"}
			var source: Transform3D = item.frame_transform.affine_inverse() * transform
			if Xml.entity_kind(element) == "joint":
				if element.attrs.get("type", "hinge") == "free" or element.tag == "freejoint": return {"error":"Set a free joint's initial pose using its body transform"}
				element.attrs.pos = Xml.numeric_text(Xml.source_vector(source.origin))
				if element.attrs.get("type", "hinge") in ["hinge", "slide"]: element.attrs.axis = Xml.numeric_text(Xml.source_vector(source.basis * Vector3.UP).normalized())
			else:
				var previous_world := world_pose(design, identity)
				Xml.write_pose(element.attrs, source)
				# Free-joint initial qpos is absolute in model space. Move it with the
				# authored body instead of letting an old override pin the body in place.
				if Xml.entity_kind(element) == "body":
					var delta := world_pose(design, identity) * previous_world.affine_inverse()
					for child in element.children:
						if Xml.entity_kind(child) != "joint" or child.attrs.get("type", "free" if child.tag == "freejoint" else "hinge") != "free": continue
						if not design.initial_pose.has(child.id): continue
						var p: Array = design.initial_pose[child.id]
						if p.size() != 7: continue
						var old_pose := Transform3D(Xml.mj_basis(Basis(Quaternion(p[4],p[5],p[6],p[3]))), Xml.mj_vector(Vector3(p[0],p[1],p[2])))
						var new_pose := delta * old_pose
						var q := Xml.source_basis(new_pose.basis).get_rotation_quaternion()
						var xyz := Xml.source_vector(new_pose.origin)
						design.initial_pose[child.id] = [xyz.x,xyz.y,xyz.z,q.w,q.x,q.y,q.z]
			result.affected = [identity]
		"set":
			var values: Dictionary = command.get("values", {})
			for key in values:
				var value: Variant = values[key]
				if value == null: element.attrs.erase(key)
				elif value is bool: element.attrs[key] = "true" if value else "false"
				elif value is Vector3 or value is Array or value is PackedFloat64Array: element.attrs[key] = Xml.numeric_text(value)
				else: element.attrs[key] = str(value)
		"initial_pose":
			if Xml.entity_kind(element) != "joint": return {"error":"Select a joint to set its initial position"}
			design.initial_pose[identity] = command.get("value", [])
			result.affected = [identity]
		_:
			return {"error":"Unknown author command: " + operation}
	return result
