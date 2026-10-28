@tool
extends RefCounted
## MJCF appearance edits use a material owned by this geom, so shared assets stay independent.
const Xml = preload("author_xml.gd")
const DEFAULT_COLOR := Color(0.5, 0.5, 0.5, 1.0)

static func fields() -> Array[Dictionary]:
	return [
		{"name":"mjcf/color", "type":TYPE_COLOR, "hint":PROPERTY_HINT_COLOR_NO_ALPHA, "hint_string":"", "usage":PROPERTY_USAGE_EDITOR, "label":"MJCF 颜色"},
		{"name":"mjcf/opacity", "type":TYPE_FLOAT, "hint":PROPERTY_HINT_RANGE, "hint_string":"0,1,0.01", "usage":PROPERTY_USAGE_EDITOR, "label":"MJCF 不透明度"},
		{"name":"mjcf/texture_file", "type":TYPE_STRING, "hint":PROPERTY_HINT_GLOBAL_FILE, "hint_string":"*.png", "usage":PROPERTY_USAGE_EDITOR, "label":"MJCF 贴图 (PNG)"},
	]

static func handles(property_name: StringName) -> bool:
	return String(property_name) in ["mjcf/color", "mjcf/opacity", "mjcf/texture_file"]

static func asset(design: Resource, kind: String, label: String) -> Dictionary:
	if label.is_empty(): return {}
	for entry in Xml.section(design.tree, "asset").get("children", []):
		if entry.tag == kind and entry.attrs.get("name", "") == label: return entry
	return {}

static func material(design: Resource, geom: Dictionary) -> Dictionary:
	var attrs: Dictionary = design.effective_attrs(geom)
	var label: String = attrs.get("material", "")
	if label.is_empty() and not attrs.has("material"):
		var mesh := asset(design, "mesh", attrs.get("mesh", ""))
		if not mesh.is_empty(): label = design.effective_attrs(mesh).get("material", "")
	return asset(design, "material", label)

static func rgba(text: String) -> Color:
	var numbers := Xml.numbers(text)
	return Color(numbers[0], numbers[1], numbers[2], numbers[3]) if numbers.size() == 4 else DEFAULT_COLOR

static func color(design: Resource, geom: Dictionary) -> Color:
	var value := rgba(design.effective_attrs(geom).get("rgba", "0.5 0.5 0.5 1"))
	var source := material(design, geom)
	# MuJoCo gives material RGBA precedence when geom RGBA equals the internal default.
	if value == DEFAULT_COLOR and not source.is_empty():
		value = rgba(design.effective_attrs(source).get("rgba", "1 1 1 1"))
	return value

static func texture_name(design: Resource, source: Dictionary) -> String:
	if source.is_empty(): return ""
	for role in ["rgba", "rgb"]:
		for layer in source.get("children", []):
			if layer.tag == "layer" and layer.attrs.get("role") == role: return layer.attrs.get("texture", "")
	return design.effective_attrs(source).get("texture", "")

static func get_value(design: Resource, geom: Dictionary, property_name: StringName) -> Variant:
	match String(property_name):
		"mjcf/color":
			var value := color(design, geom)
			return Color(value.r, value.g, value.b, 1.0)
		"mjcf/opacity": return color(design, geom).a
		"mjcf/texture_file":
			var texture := asset(design, "texture", texture_name(design, material(design, geom)))
			return texture.get("attrs", {}).get("file", "")
	return null

static func unique_asset_name(design: Resource, kind: String, label: String) -> String:
	var value := label
	var index := 2
	while not asset(design, kind, value).is_empty():
		value = label + "_" + str(index)
		index += 1
	return value

static func private_material(design: Resource, geom: Dictionary) -> Dictionary:
	var source := material(design, geom)
	if source.get("appearance_owner", "") == geom.id: return source
	var current := color(design, geom)
	var copy: Dictionary = source.duplicate(true) if not source.is_empty() else {"tag":"material", "attrs":{}, "children":[]}
	Xml.clone_ids(copy, {})
	copy.id = Xml.uuid()
	if not source.is_empty(): copy.attrs = design.effective_attrs(source)
	copy.attrs.name = unique_asset_name(design, "material", str(geom.attrs.name) + "_material")
	copy.attrs.rgba = Xml.numeric_text([current.r, current.g, current.b, current.a])
	copy.appearance_owner = geom.id
	Xml.section(design.tree, "asset", true).children.append(copy)
	geom.attrs.material = copy.attrs.name
	return copy

static func apply(design: Resource, geom: Dictionary, field: String, value: Variant) -> String:
	if geom.tag != "geom": return "Appearance belongs to a geom"
	var current := color(design, geom)
	match field:
		"color":
			if not value is Color: return "Choose an RGB color"
			current = Color(value.r, value.g, value.b, current.a)
		"opacity":
			if not value is float and not value is int: return "Opacity must be between 0 and 1"
			current.a = float(value)
		"texture_file":
			var path := str(value)
			var target := ""
			if not path.is_empty():
				if path.get_extension().to_lower() != "png" or not FileAccess.file_exists(path): return "Choose an existing PNG texture"
				var digest := FileAccess.get_sha256(path)
				var directory: String = "res://mujoco_models/" + design.document_id + "/assets"
				if DirAccess.make_dir_recursive_absolute(directory) != OK: return "Cannot create texture asset folder"
				target = directory.path_join(digest + ".png")
				if not FileAccess.file_exists(target) or FileAccess.get_sha256(target) != digest:
					if DirAccess.copy_absolute(path, target) != OK or FileAccess.get_sha256(target) != digest: return "Texture changed while copying"
				design.dependencies[target] = digest
			var own := private_material(design, geom)
			own.attrs.erase("texture")
			for layer in own.children.duplicate():
				if layer.tag == "layer" and layer.attrs.get("role") in ["rgb", "rgba"]: own.children.erase(layer)
			if not target.is_empty():
				var texture := {"tag":"texture", "id":Xml.uuid(), "attrs":{"name":unique_asset_name(design, "texture", str(geom.attrs.name) + "_texture"), "type":"2d", "file":target, "nchannel":"4"}, "children":[]}
				Xml.section(design.tree, "asset", true).children.append(texture)
				own.children.append({"tag":"layer", "id":Xml.uuid(), "attrs":{"role":"rgba", "texture":texture.attrs.name}, "children":[]})
			elif not own.children.any(func(child): return child.tag == "layer"):
				own.attrs.texture = ""
			return ""
		_: return "Unknown geom appearance property"
	for component in [current.r, current.g, current.b, current.a]:
		if not is_finite(component) or component < 0.0 or component > 1.0: return "Color and opacity must be between 0 and 1"
	var own := private_material(design, geom)
	var text := Xml.numeric_text([current.r, current.g, current.b, current.a])
	geom.attrs.rgba = text
	# Also set the private material, including the exact internal-default gray case.
	own.attrs.rgba = text
	return ""
