extends Node
var world: Node
var last_ms := 0
var last_reply := {}
func _ready() -> void:
	world = get_parent()
	world.design_request_finished.connect(func(result): last_reply = result)
func _process(_delta: float) -> void:
	if Time.get_ticks_msec()-last_ms<40: return
	last_ms = Time.get_ticks_msec()
	if FileAccess.file_exists("res://live-command.json"):
		var command = JSON.parse_string(FileAccess.get_file_as_string("res://live-command.json")); DirAccess.remove_absolute("res://live-command.json")
		if command.get("op") == "resume": world.request_pause(false)
		elif command.get("op") == "control": world.get_node("Model").set_control("motor",command.value)
		else: world.request_editor_design(command)
	var models := []
	for node in world.get_children():
		if not node is MjModelInstance: continue
		var state: Dictionary = node.state()
		var appearances := {}
		for geom_name in node.visuals:
			var material: StandardMaterial3D = node.visuals[geom_name].material_override as StandardMaterial3D
			if material: appearances[geom_name] = {"color":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a], "texture":material.albedo_texture != null}
		models.append({"name":str(node.name),"id":node.design_instance_id,"revision":node.design.revision,"bodies":state.get("bodies",{}),"joints":state.get("joints",{}),"controls":state.get("controls",{}),"appearances":appearances})
	var info: Dictionary = world.info()
	var data := {"ready":world.author_started,"connected":world.editor_connected,"info":info,"models":models,"terrain":world.get_node("Terrain").state(),"reply":last_reply}
	var output := FileAccess.open("res://live-state.tmp",FileAccess.WRITE); output.store_string(JSON.stringify(data)); output.close()
	DirAccess.rename_absolute("res://live-state.tmp","res://live-state.json")
