@tool
extends RefCounted
const Probe=preload("res://live_protocol_probe.gd")
const Driver=preload("res://live_driver.gd")
class MockModel:
	extends Node
	var accept_control := true
	func set_control(_name: String, _value: float) -> bool:return accept_control
class MockWorld:
	extends Node
	var author_started := true
	var command_request := 0
	var views_pending := false
	var last_error := ""
	var accept_resume := false
	var accept_design := false
	func info() -> Dictionary:return {"compile_status":"ready","design_pending":false}
	func request_pause(_paused: bool) -> bool:
		command_request=77 if accept_resume else 0
		return accept_resume
	func request_editor_design(_command: Dictionary) -> int:return 88 if accept_design else 0
var checks := 0
var failures: Array[String] = []
var evidence: Array = []
func check(value: bool, label: String) -> void:
	checks+=1
	if not value:failures.append(label);print("FAIL ",label)
func conditions_match(sample: Dictionary) -> bool:
	var state: Dictionary=sample.game
	var info: Dictionary=state.get("info",{})
	var c: Dictionary=sample.conditions
	return c.game_two_models==(state.get("models",[]).size()==2) and c.ready==state.get("ready",false) and c.compile_ready==(info.get("compile_status")=="ready") and c.design_committed==(not info.get("design_pending",true))
func command(driver: Node, packet: Dictionary) -> Dictionary:
	var sequence: int=driver.next_sequence
	driver.waiting_command=packet;driver.dispatch()
	return driver.acks[str(sequence)]
func terminal_ack(ack: Dictionary, accepted: bool, label: String) -> void:
	check(ack.completed and ack.accepted==accepted,label+" terminal status")
	check(ack.has("completed_ms"),label+" completed timestamp exists")
	check(int(ack.get("completed_ms",-1))>=int(ack.accepted_ms),label+" same-game-clock timestamp order")
func run(editor: EditorPlugin) -> void:
	var legacy: bool="--negative-control" in OS.get_cmdline_user_args()
	var source=Node.new();var second=Node.new();second.name="Second";source.add_child(second)
	var probe=Probe.new();probe.run_id="protocol-test"
	probe.publications=[{"run_id":"protocol-test","sequence":101,"ready":false,"models":[{}],"info":{"compile_status":"compiling","design_pending":true}},{"run_id":"protocol-test","sequence":102,"ready":true,"models":[{},{}],"info":{"compile_status":"ready","design_pending":false}}]
	probe.duplicate_sample_ms=-1000
	check(not probe.duplicate_is_settled(source),"first publication remains pending")
	check(probe.read_count==1,"one state read per predicate evaluation")
	check(int(probe.duplicate_history[0].game.sequence)==101,"snapshot stays on decision publication")
	check(conditions_match(probe.duplicate_history[0]),"pending conditions match snapshot")
	probe.duplicate_sample_ms=-1000
	check(probe.duplicate_is_settled(source),"next publication becomes ready")
	check(probe.read_count==2,"two evaluations read exactly two publications")
	check(int(probe.duplicate_history[1].game.sequence)==102,"second publication preserved")
	check(conditions_match(probe.duplicate_history[1]),"ready conditions match snapshot")
	evidence.append({"reads":probe.read_count,"history":probe.duplicate_history.duplicate(true)})
	if not legacy:
		check(probe.duplicate_history[0].conditions_sequence==101 and probe.duplicate_history[1].conditions_sequence==102,"explicit condition sequence matches publication")
		probe.publications[0].models.append({});probe.publications[0].info.compile_status="mutated"
		check(probe.duplicate_history[0].game.models.size()==1 and probe.duplicate_history[0].game.info.compile_status=="compiling","recorded snapshot owns immutable copy")
		var reads: int=probe.read_count
		var empty: Dictionary=probe.call("diagnostic_snapshot",{})
		check(empty.game.is_empty() and probe.read_count==reads,"empty supplied state never triggers a fresh read")
		check(probe.get("duplicate_last_evaluation").sequence==102 and probe.get("duplicate_last_evaluation").game.sequence==102,"last decision retains its publication")
	source.free()
	var world=MockWorld.new();var model=MockModel.new();model.name="Model";world.add_child(model)
	var driver=Driver.new();driver.world=world;driver.channel="user://protocol-regression-no-files"
	var ack=command(driver,{"op":"control","value":.2});terminal_ack(ack,true,"immediate control success");check(ack.success,"successful control result")
	model.accept_control=false
	ack=command(driver,{"op":"control","value":.2});terminal_ack(ack,false,"immediate control rejection");check(not ack.success,"rejected control result")
	ack=command(driver,{"op":"resume"});terminal_ack(ack,false,"immediate resume rejection")
	ack=command(driver,{"op":"duplicate_model"});terminal_ack(ack,false,"immediate design rejection")
	world.accept_resume=true
	ack=command(driver,{"op":"resume"});check(ack.accepted and not ack.completed and not ack.has("completed_ms"),"queued resume is not prematurely completed")
	driver.completed({"request":999,"success":true},"world");check(not ack.completed,"unrelated completion ignored")
	await editor.get_tree().process_frame
	driver.completed({"request":77,"success":true},"world");terminal_ack(ack,true,"asynchronous resume completion")
	var completed_ms: int=ack.get("completed_ms",-1)
	await editor.get_tree().process_frame
	driver.completed({"request":77,"success":true},"world");check(ack.get("completed_ms",-2)==completed_ms,"duplicate completion does not rewrite completion time")
	world.command_request=0;world.accept_design=true
	ack=command(driver,{"op":"duplicate_model"});check(ack.accepted and not ack.completed,"design waits for completion")
	driver.completed({"request":88,"success":true},"design");terminal_ack(ack,true,"asynchronous design completion")
	evidence.append({"acks":driver.acks.duplicate(true)})
	driver.free();world.free()
	var result={"checks":checks,"failed":failures.size(),"failures":failures,"negative_control":legacy,"evidence":evidence}
	FileAccess.open("res://protocol-regression-result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("NODE_PROTOCOL_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	editor.get_tree().quit(0 if failures.is_empty() else 1)
