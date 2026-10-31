@tool
class_name MjViewerConfiguration
extends Resource
## Author-owned limits. Personal view preferences cannot widen these capabilities.
@export var disabled_groups: PackedStringArray = []:
	set(value):disabled_groups=value;emit_changed()
@export var disabled_actions: PackedStringArray = []:
	set(value):disabled_actions=value;emit_changed()
@export var allowed_preferences: PackedStringArray = ["layout","visibility","metrics","display","output","style"]
@export var allowed_metrics: PackedStringArray = ["fps","cpu","ram","gpu","vram","timing"]:
	set(value):allowed_metrics=value;emit_changed()
const GROUP_ACTIONS := {
	"camera":["camera","cycle_camera","camera_previous","camera_next","free_camera","align","copy_camera"],
	"selection":["select","parent"],
	"perturbation":["perturb_begin"],
	"simulation":["pause","step","reset_initial","capture_snapshot","restore_snapshot","history_back","history_forward","history_seek","speed","slower","faster","threads","pause_update","key_load","key_save","ctrl_noise","control","clear_control","joint","equality","reload"],
	"output":["copy_state","print_model","print_data","save_xml","save_mjb","screenshot","quit"],
	"visualization":["vis","rnd","visual","frame","label","group","tree_depth","skin","flex"],
	"analysis":["info","profiler","sensors","image_sensor","watch","logging"],
	"interface":["help","controls","panels","fullscreen","vsync","ui_spacing","ui_color","ui_font","renderer"],
	"performance":["performance","metric"]
}
func group_for(action: StringName, arguments: Dictionary = {}) -> String:
	if action==&"move": return "perturbation" if arguments.get("perturb",false) else "camera"
	if action==&"select" and arguments.get("button",1)==MOUSE_BUTTON_RIGHT:return "camera"
	for group in GROUP_ACTIONS:
		if str(action) in GROUP_ACTIONS[group]: return group
	return ""
func is_public_action(action: StringName) -> bool:
	if action==&"move":return true
	for actions in GROUP_ACTIONS.values():
		if str(action) in actions:return true
	return false
func normalize(action: StringName, arguments: Dictionary) -> Dictionary:
	var args := arguments.duplicate(true);var canonical := action
	match str(action):
		"move":
			if not args.has("perturb"):args.perturb=false
		"camera":
			if not args.has("id"):args.id=0
		"free_camera":canonical=&"camera";args.id=0
		"camera_previous","camera_next":canonical=&"cycle_camera";args.delta=-1 if action==&"camera_previous" else 1
		"slower","faster":canonical=&"speed";args.delta=1 if action==&"slower" else -1
	return {"action":canonical,"arguments":args}
func rejection_reason(action: StringName, arguments: Dictionary = {}) -> String:
	if not is_public_action(action):return "Unknown public viewer action: "+str(action)
	var group := group_for(action,arguments)
	if disabled_groups.has(group): return "Feature group disabled by component configuration: "+group
	var selectors := PackedStringArray([str(action)])
	if arguments.has("name"):
		selectors.append(str(action)+":"+str(arguments.name))
		if arguments.has("id"):selectors.append(str(action)+":"+str(arguments.name)+":"+str(arguments.id))
	elif arguments.has("id"):selectors.append(str(action)+":"+str(arguments.id))
	for selector in selectors:
		if disabled_actions.has(selector):return "Action disabled by component configuration: "+selector
	if action==&"metric" and not allowed_metrics.has(str(arguments.get("name",""))):return "Metric not permitted by component configuration"
	return ""
func allows(action: StringName, arguments: Dictionary = {}) -> bool:
	return rejection_reason(action,arguments).is_empty()
func allows_preference(category: String) -> bool:
	return allowed_preferences.has(category)
