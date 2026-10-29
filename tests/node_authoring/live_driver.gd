extends Node
@export var run_id := ""
var world: Node
var channel := ""
var next_sequence := 1
var state_sequence := 0
var acks := {}
var waiting_command := {}
func completed(result: Dictionary, kind: String) -> void:
	for key in acks:
		var ack: Dictionary=acks[key]
		if not ack.completed and ack.kind==kind and int(ack.request_id)==int(result.get("request",-1)):
			ack["completed_ms"]=Time.get_ticks_msec();ack.completed=true;ack.success=result.get("success",false);ack.result=result.duplicate(true)
func dispatch() -> void:
	var path:=channel.path_join("command-%06d.json"%next_sequence)
	if waiting_command.is_empty() and FileAccess.file_exists(path):
		var value=JSON.parse_string(FileAccess.get_file_as_string(path));DirAccess.remove_absolute(path)
		if value is Dictionary and value.get("run_id", "")==run_id and int(value.get("sequence",-1))==next_sequence:
			waiting_command=value.command
	if waiting_command.is_empty(): return
	var command: Dictionary=waiting_command
	var op: String=command.get("op","")
	# Do not drop Continue while a checkpoint/capture or author compile is pending.
	if op=="resume" and (not world.author_started or world.command_request!=0 or world.views_pending or world.info().get("compile_status","")!="ready" or world.info().get("design_pending",true)): return
	var ack: Dictionary={"accepted_ms":Time.get_ticks_msec(),"command":command.duplicate(true),"kind":"instant","request_id":0,"accepted":false,"completed":true,"success":false,"command_request_before":world.command_request}
	if op=="resume":
		ack.accepted=world.request_pause(false);ack.request_id=world.command_request;ack.kind="world";ack.completed=not ack.accepted
	elif op=="control":
		ack.accepted=world.get_node("Model").set_control("motor",command.value);ack.success=ack.accepted
	else:
		ack.request_id=world.request_editor_design(command);ack.accepted=int(ack.request_id)>0;ack.kind="design";ack.completed=not ack.accepted
	if ack.completed: ack["completed_ms"]=Time.get_ticks_msec()
	ack.command_request_after=world.command_request;ack.error=world.last_error
	acks[str(next_sequence)]=ack;next_sequence+=1;waiting_command={}

var last_ms := 0
var last_reply := {}
func _ready() -> void:
	world = get_parent()
	channel="user://mj-live-tests/"+run_id
	assert(not run_id.is_empty())
	world.design_request_finished.connect(func(result): last_reply = result;completed(result,"design"))
	world.command_finished.connect(func(result):completed(result,"world"))
func _process(_delta: float) -> void:
	if Time.get_ticks_msec()-last_ms<40: return
	last_ms = Time.get_ticks_msec()
	dispatch()
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
	state_sequence+=1
	var data := {"run_id":run_id,"pid":OS.get_process_id(),"world_identity":{"author_live_id":world.author_live_id,"instance_id":world.get_instance_id(),"path":str(world.get_path()),"scene":world.scene_file_path,"space":str(world.space.get_id())},"sampled_ms":Time.get_ticks_msec(),"scene_path":world.scene_file_path,"views_pending":world.views_pending,"queued_design_revision":world.queued_design_revision,"compiler":compiler_diagnostic(world.author_compiler),"sequence":state_sequence,"acks":acks,"waiting_command":waiting_command,"command_request":world.command_request,"last_command_result":world.last_command_result,"ready":world.author_started,"connected":world.editor_connected,"info":info,"models":models,"terrain":world.get_node("Terrain").state(),"reply":last_reply}
	# The editor may kill the game on Stop: retain bounded in-memory trace in the
	# existing publication rather than relying on game _exit_tree to flush.
	if preload("res://addons/godot_mujoco/model/author_trace.gd").enabled():
		data["author_trace"]={"dropped":preload("res://addons/godot_mujoco/model/author_trace.gd").dropped,"events":preload("res://addons/godot_mujoco/model/author_trace.gd").events.duplicate(true)}
	var output := FileAccess.open(channel.path_join("state.tmp"),FileAccess.WRITE); output.store_string(JSON.stringify(data)); output.close()
	DirAccess.rename_absolute(channel.path_join("state.tmp"),channel.path_join("state.json"))

func compiler_diagnostic(service: Node) -> Dictionary:
	if not is_instance_valid(service): return {}
	var result={"busy":service.busy(),"pid":service.process_id,"serial":service.serial,"session_id":service.session_id,"age_ms":Time.get_ticks_msec()-service.started_ms}
	for field in ["active","queued"]:
		var job: Dictionary=service.get(field)
		var summary: Dictionary={}
		for key in ["job_id","revision","generation","directory"]:
			if job.has(key):summary[key]=job[key]
		result[field]=summary
	return result
