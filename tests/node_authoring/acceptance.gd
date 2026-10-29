extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source := '<mujoco><compiler angle="radian"/><default><geom friction=".8"/></default><!--kept--><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0"/><geom name="rod" type="capsule" fromto="0 0 0 0 0 -.6" size=".04" density="600"/></body><body name="other" pos="1 0 1"><geom name="other_geom" size=".1"/></body></worldbody><actuator><motor name="motor" joint="hinge"/></actuator><sensor><jointpos name="encoder" joint="hinge"/></sensor><contact><exclude body1="arm" body2="other"/></contact></mujoco>'
	var parsed := Author.from_xml(source)
	check(parsed.error.is_empty(), "parse complete author document")
	var design: Resource = parsed.design
	check(design.entities().size() == 5, "body/geom/joint hierarchy excludes defaults")
	check(not Xml.section(design.tree, "default").children[0].attrs.has("name"), "never add names to default prototypes")
	check(design.xml().contains("<!--kept-->"), "XML comments preserved")
	check(not design.xml().contains("fromto="), "fromto normalized")
	var arm: Dictionary = design.entities()[0]
	var hinge: Dictionary = design.entities()[1]
	var rename := Commands.execute(design, {"op":"rename", "id":hinge.id, "name":"new_hinge"})
	check(rename.error.is_empty(), "rename accepted")
	design.restore_author(rename.after)
	check(design.xml().contains('joint="new_hinge"'), "actuator/sensor references repaired")
	check(design.entity(hinge.id).name == "new_hinge", "identity stable across rename")
	var deletion := Commands.execute(design, {"op":"delete", "id":arm.id})
	check(deletion.get("confirmation_required", false), "deletion requires explicit dependency confirmation")
	check(deletion.impacts.size() == 3, "motor, sensor and contact dependency closure")
	var clone := Commands.execute(design, {"op":"duplicate", "id":arm.id})
	check(clone.error.is_empty(), "duplicate subtree")
	var duplicate := Author.new()
	duplicate.restore_author(clone.after)
	check(duplicate.entities().size() == 8, "duplicate body/geom/joint")
	check(Xml.section(duplicate.tree, "actuator").children.size() == 2, "copy internal actuator")
	check(Xml.section(duplicate.tree, "sensor").children.size() == 2, "copy internal sensor")
	check(Xml.section(duplicate.tree, "contact").children.size() == 1, "do not copy cross-boundary contact")
	check(clone.omitted.size() == 1, "cross-boundary omission reported")
	var chain: Resource = Author.from_xml('<mujoco><worldbody><body name="arm"><joint name="j"/><geom name="g" size=".1"/></body></worldbody><tendon><fixed name="rope"><joint joint="j" coef="1"/></fixed></tendon><actuator><motor name="pull" tendon="rope"/></actuator><sensor><actuatorfrc name="load" actuator="pull"/></sensor><equality><tendon name="constraint" tendon1="rope"/></equality></mujoco>').design
	var copied_chain := Commands.execute(chain,{"op":"duplicate","id":chain.entities()[0].id})
	var copied: Resource=Author.new();copied.restore_author(copied_chain.after)
	check(Xml.section(copied.tree,"actuator").children.size()==2 and Xml.section(copied.tree,"sensor").children.size()==2,"copy transitive tendon/actuator/sensor dependency closure")
	check(copied.xml().contains('tendon="rope_copy"') and copied.xml().contains('actuator="pull_copy"'),"copied dependencies reference copied targets")
	var fork: Resource = design.fork()
	check(fork.document_id != design.document_id, "model instance fork gets independent document identity")
	fork.tree.attrs.model = "isolated"
	check(not design.tree.attrs.has("model"), "fork does not mutate shared author document")
	for sequence in ["xyz","ZYX","xYz"]:
		var orientation_xml: String = '<mujoco><compiler angle="radian" eulerseq="%s"/><worldbody><geom name="g" type="box" size=".1 .2 .3" euler=".3 .4 -.7"/></worldbody></mujoco>' % sequence
		var orientation: Resource = Author.from_xml(orientation_xml).design
		var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
		check(document.compile_author(orientation.worker_xml(),{}) and orientation.entities()[0].transform.is_equal_approx(document.geometry()[0].transform),"Euler sequence matches MuJoCo: "+sequence)
	var from_default: Resource = Author.from_xml('<mujoco><default><geom type="capsule" size=".04"/></default><worldbody><body name="b"><geom name="g" fromto="0 0 0 0 0 -.6"/></body></worldbody></mujoco>').design
	check(not from_default.xml().contains("fromto=") and is_equal_approx(Xml.numbers(from_default.entity(from_default.entities()[1].id).attrs.size)[1],.3),"fromto uses inherited default size without changing capsule")
	var file_path := "res://unfinished.tres"
	var invalid: Resource = Author.from_xml('<mujoco><worldbody><body name="unfinished"><joint name="hinge"/></body></worldbody></mujoco>').design
	check(ResourceSaver.save(invalid, file_path) == OK, "save incomplete physical design")
	var reopened: Resource = ResourceLoader.load(file_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened != null and reopened.entities().size() == 2, "reopen incomplete design without compilation")
	var service := Service.new()
	root.add_child(service)
	var heartbeat := 0
	service.submit({"author":design.author_snapshot(), "revision":design.revision, "generation":design.document_id})
	var deadline := Time.get_ticks_msec() + 30000
	var output := {}
	service.completed.connect(func(result): output.merge(result))
	while output.is_empty() and Time.get_ticks_msec() < deadline:
		heartbeat += 1
		await process_frame
	check(output.get("success", false), "isolated native compilation succeeds: " + str(output.get("error", "timeout")))
	check(heartbeat > 2, "main loop responsive during compilation")
	check(FileAccess.file_exists(output.get("compiled_path", "")), "MJB artifact published")
	if output.get("success", false):
		check(output.entities.size() >= 5, "compiler returns semantic entity metadata")
		check(output.geometry.size() == 2, "compiler returns actual geometry")
	# Current author resources preserve deliberate initial qpos and project-owned dependencies.
	var native: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(native.compile_author('<mujoco><worldbody><body name="b"><joint name="j"/><geom size=".1"/></body></worldbody></mujoco>', {"j":[.4]}), "prepare native initial pose")
	var imported: Resource = Author.from_native_document(native).design
	check(is_equal_approx(float(imported.native_initial_pose().j[0]), .4), "current author import retains initial qpos")
	# Validate kill and recovery using a worker that never returns to its event loop.
	output.clear()
	service.worker_script = "res://slow_worker.gd"
	service.timeout_seconds = .2
	service.submit({"generation":"timeout"})
	var timeout_pid: int = service.process_id
	deadline = Time.get_ticks_msec() + 5000
	while output.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(output.get("cancelled",false) and not service.busy(), "unresponsive worker times out without blocking UI")
	check(not FileAccess.file_exists("/proc/"+str(timeout_pid)+"/stat"), "timeout terminates the actual worker process")
	output.clear()
	service.timeout_seconds = 120
	service.submit({"generation":"cancel"})
	var cancel_pid: int = service.process_id
	service.cancel()
	check(output.get("cancelled",false) and not service.busy() and not FileAccess.file_exists("/proc/"+str(cancel_pid)+"/stat"), "cancel hard-kills the compiler")
	output.clear()
	service.submit({"generation":"obsolete"})
	var stale_pid: int = service.process_id
	service.worker_script = Service.WorkerPath
	service.submit({"author":design.author_snapshot(),"generation":"latest"})
	deadline = Time.get_ticks_msec() + 30000
	while output.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(output.get("success",false) and output.get("generation") == "latest", "superseded worker cannot publish stale results; service recovers")
	check(not FileAccess.file_exists("/proc/"+str(stale_pid)+"/stat"), "superseded worker is terminated")
	var free_design: Resource = Author.from_xml('<mujoco><worldbody><body name="floating" pos="0 0 1"><freejoint name="base"/><geom name="sphere" size=".1"/></body></worldbody></mujoco>').design
	var body: Dictionary = free_design.entities()[0]
	var free_joint: Dictionary = free_design.entities()[1]
	free_design.initial_pose[free_joint.id] = [0.,0.,1.,1.,0.,0.,0.]
	var moved: Transform3D = body.transform; moved.origin.x += 2
	var motion := Commands.execute(free_design,{"op":"pose","id":body.id,"transform":moved})
	check(is_equal_approx(motion.after.initial_pose[free_joint.id][0],2.), "body Gizmo moves saved free-joint initial pose")
	var framed: Resource = Author.from_xml('<mujoco><worldbody><frame pos="1 0 0" euler="0 0 30"><body name="framed"><geom name="ball" size=".1"/></body></frame><body name="target" pos="0 0 2"/></worldbody></mujoco>').design
	var child: Dictionary = framed.entities()[0]
	var parent: Dictionary = framed.entities()[2]
	var original: Transform3D = Commands.world_pose(framed,child.id)
	var reparented := Commands.execute(framed,{"op":"reparent","id":child.id,"parent_id":parent.id})
	framed.restore_author(reparented.after)
	check(Commands.world_pose(framed,child.id).is_equal_approx(original), "reparent preserves design world pose through hidden frames")
	service.queue_free()
	await process_frame
	print("NODE_AUTHORING_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
