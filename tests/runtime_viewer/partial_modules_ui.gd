@tool
extends "res://addons/godot_mujoco/viewer/viewer_ui.gd"
## Authored inherited-scene fixture: customize optional modules before hydration.
@export var omitted_modules: PackedStringArray=[]
@export var omitted_sections: PackedStringArray=[]
@export var omitted_panels: PackedStringArray=[]
@export var profiler_indices: PackedInt32Array=[0,1,2,3]
@export var omit_numeric_sensor := false
@export var omit_sensor_images := false
func _ready() -> void:
	for node in find_children("*","Node",true,false):
		if not is_instance_valid(node):continue
		var remove: bool=node.has_meta("viewer_overlay") and omitted_modules.has(str(node.get_meta("viewer_overlay")))
		if node.has_meta("viewer_section") and omitted_sections.has(str(node.get_meta("viewer_section").name)):remove=true
		if node.has_meta("viewer_profiler") and not profiler_indices.has(int(node.get_meta("viewer_profiler"))):remove=true
		var role: String=str(node.get_meta("viewer_role",""))
		if omitted_panels.has(role):remove=true
		if role=="sensor_plot" and omit_numeric_sensor or role=="sensor_images" and omit_sensor_images:remove=true
		if remove:node.get_parent().remove_child(node);node.free()
	super._ready()
