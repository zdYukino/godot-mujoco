@tool
@icon("res://addons/godot_mujoco/icons/mj_geom.svg")
class_name MjGeom3D
extends "author_node.gd"
const Appearance = preload("geom_appearance.gd")
const Collision = preload("collision_settings.gd")

func author_kind() -> String:
	return "geom"

func _get_property_list() -> Array[Dictionary]:
	# Godot already collects the base script's dynamic properties separately.
	var fields: Array[Dictionary] = []
	if not item().is_empty():
		fields.append_array(Appearance.fields())
		fields.append_array(Collision.geom_fields(self))
	return fields

func _get(property_name: StringName) -> Variant:
	if String(property_name).begins_with("mjcf/collision_") and not item().is_empty(): return Collision.geom_value(self,String(property_name).trim_prefix("mjcf/collision_"))
	if Appearance.handles(property_name) and not item().is_empty():
		return Appearance.get_value(author_model().design, Xml.find(author_model().design.tree, entity_id), property_name)
	return super._get(property_name)

func _set(property_name: StringName, value: Variant) -> bool:
	if String(property_name).begins_with("mjcf/collision_"):
		var target := author_model()
		if not target or not target.design: return false
		return target.apply_author_command({"op":"collision","id":entity_id,"field":String(property_name).trim_prefix("mjcf/collision_"),"value":value},false).get("error","").is_empty()
	if not Appearance.handles(property_name): return super._set(property_name, value)
	var model := author_model()
	if not model or not model.design: return false
	var result: Dictionary = model.apply_author_command({"op":"appearance", "id":entity_id, "field":String(property_name).trim_prefix("mjcf/"), "value":value}, false)
	return result.get("error", "").is_empty()
