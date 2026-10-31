extends RefCounted
## Focused R7/A08 integration probe. Model changes use the real author compiler;
## only automatic delivery/inspection is held to inspect the synchronous window.
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
var test
var viewer: Node
var extras: Node
var world: Node3D
var robot: Node
var observations: Array = []
var commit_evidence := {}

func check(ok: bool, label: String) -> void:
	test.check(ok,label)

func ready() -> bool:
	return is_instance_valid(viewer._session) and not viewer._session.frame.is_empty() and viewer._session.presented_frame_id>0 and viewer._session.presented_layout==viewer._session.layout_generation and viewer._session.pending.is_empty()

func widgets_ready() -> bool:
	return is_instance_valid(viewer._session) and is_instance_valid(viewer.ui) and not viewer._session.details.get("joints",[]).is_empty() and viewer.ui.fields.has("control:0") and viewer.ui.fields.has("equality:0") and viewer.ui.fields.has("joint:%d" % int(viewer._session.details.joints[0].id))

func widgets() -> Dictionary:
	var joint: int=viewer._session.details.joints[0].id
	return {"camera":viewer.ui.fields.camera_choice,"joint":viewer.ui.fields["joint:%d" % joint],"joint_slider":viewer.ui.fields["joint:%d:slider" % joint],"control":viewer.ui.fields["control:0"],"control_slider":viewer.ui.fields["control:0:slider"],"equality":viewer.ui.fields["equality:0"],"joint_row":viewer.ui.fields["joint:%d:row" % joint],"control_row":viewer.ui.fields["control:0:row"]}

func identity(values: Dictionary) -> Dictionary:
	var ids := {}
	for key in values: ids[key]=values[key].get_instance_id() if is_instance_valid(values[key]) else 0
	return ids

func focus_edit(values: Dictionary) -> LineEdit:
	var line: LineEdit=values.control.get_line_edit()
	viewer.ui.right_panel.ensure_control_visible(line)
	await test.process_frame; await test.process_frame
	var point := line.get_global_rect().get_center()
	var click := InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=point; click.global_position=point
	Input.parse_input_event(click); await test.process_frame
	click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await test.process_frame
	await test.key(KEY_A,true)
	for index in "0.79".length():
		var event := InputEventKey.new(); event.keycode="0.79".unicode_at(index); event.physical_keycode=event.keycode; event.unicode=event.keycode; event.pressed=true
		Input.parse_input_event(event); await test.process_frame
		event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await test.process_frame
	check(line.has_focus() and line.text=="0.79","actual mouse and text input focus the old actuator editor before replacement")
	line.set_meta("probe_focus_outs",0)
	line.focus_exited.connect(func():line.set_meta("probe_focus_outs",int(line.get_meta("probe_focus_outs",0))+1))
	return line

func retired(values: Dictionary, focused: LineEdit, phase: String) -> void:
	for key in ["joint","joint_slider","control","control_slider","equality","camera"]:
		var item: Variant=values[key]
		check(is_instance_valid(item) and item.is_blocking_signals() and not item.is_inside_tree() and not item.is_visible_in_tree(),phase+": old "+key+" is synchronously blocked and detached")
		if not is_instance_valid(item):continue
		check(item.disabled if item is BaseButton else not item.editable,phase+": old "+key+" is disabled")
	check(not focused.has_focus() and int(focused.get_meta("probe_focus_outs",0))==1,phase+": real focus-exited fires before a pending text commit")
	check(viewer.ui.fields.keys().all(func(key):return not str(key).begins_with("joint:") and not str(key).begins_with("control:") and not str(key).begins_with("equality:")),phase+": old integer-ID fields are removed before refresh")
	var observed_session: Node=viewer._session if is_instance_valid(viewer._session) else world._view_session
	var pending_before: int=observed_session.pending.size()
	values.control.value=.84; values.control_slider.value=-.74
	values.joint.value=.63; values.joint_slider.value=-.52
	values.equality.button_pressed=true
	values.control.emit_signal("value_changed",.91)
	values.equality.emit_signal("toggled",true)
	if is_instance_valid(values.camera):values.camera.emit_signal("item_selected",0)
	check(not viewer.ui.fields.has("camera_choice"),phase+": old model camera ID field is removed synchronously")
	check(observed_session.pending.size()==pending_before,phase+": stale drag, camera, click and text signals cannot enqueue new-world commands")
	observations.append({"phase":phase,"space":world.space.get_id(),"revision":observed_session.frame.get("revision",-1),"old_ids":identity(values),"pending_before":pending_before,"pending_after":observed_session.pending.size(),"old_focus_released":not focused.has_focus()})

func current_control(name: String, value: float) -> bool:
	return absf(float(robot.state().controls.get(name,1000))-value)<1e-8 and absf(float(viewer.ui.fields["control:0"].value)-value)<1e-8

func fresh_controls(old_ids: Dictionary, joint_name: String, control_name: String, equality_name: String, phase: String) -> void:
	check(await test.wait_for(widgets_ready),phase+": first fresh inspection repopulates model controls")
	var fresh := widgets()
	check(fresh.control.get_instance_id()!=old_ids.control and fresh.joint.get_instance_id()!=old_ids.joint and fresh.equality.get_instance_id()!=old_ids.equality and fresh.camera.get_instance_id()!=old_ids.camera,phase+": replacements are fresh widget instances")
	check(str(viewer._session.details.controls[0].name).ends_with(control_name) and str(viewer._session.details.joints[0].name).ends_with(joint_name) and str(viewer._session.details.equalities[0].name).ends_with(equality_name),phase+": controls bind the new model names at overlapping IDs")
	check(not fresh.control.is_blocking_signals() and fresh.control.editable and not fresh.equality.disabled,phase+": fresh controls are interactive")
	var baseline: float=robot.state().controls[control_name]
	fresh.control.value=.31
	check(await test.wait_for(func():return current_control(control_name,.31)),phase+": fresh actuator widget changes the actual current model")
	await test.issue({"action":"control","id":0,"value":baseline})

func run(tree) -> void:
	test=tree; viewer=tree.viewer; extras=tree.extras; world=tree.world; robot=world.get_node("Robot")
	extras.show_extras(true); extras.ui.extras_sections.Tools.button.button_pressed=true
	var output: LineEdit=extras.ui.fields.step_count.get_line_edit(); output.grab_focus()
	await test.process_frame
	var context: PopupMenu=output.get_menu(); context.popup()
	await test.process_frame
	check(context.visible,"real LineEdit context menu opens in the Godot extras viewport")
	await test.key(KEY_F11)
	check(not context.visible and not extras.ui.controls.visible,"F11 closes Godot extras and the focused built-in text context menu")
	context.hide(); extras.show_extras(false)
	for title in ["Joint","Control","Equality"]: viewer.ui.sections[title].button.button_pressed=true
	check(await test.wait_for(func():return ready() and widgets_ready()),"binding probe starts with displayed typed Joint/Control/Equality controls")
	await test.issue({"action":"control","id":0,"value":.2})
	await test.issue({"action":"joint","id":int(viewer._session.details.joints[0].id),"value":.15})
	var stable := identity(widgets())
	await test.backend_roundtrip()
	check(await test.wait_for(func():return ready() and widgets_ready()),"same-model backend refresh finishes with current controls")
	var after_backend := identity(widgets());after_backend.erase("camera");stable.erase("camera")
	check(after_backend==stable,"same-model backend refresh preserves the valid numeric widget instances")
	# Same-world rebind follows the public display stop/bind/start lifecycle.
	if test.native:
		world.stop_native_view()
		# Presentation can resume before the separate 5 Hz inspector rebuild.
		# Capture widgets only once both real delivery boundaries have completed.
		check(await test.wait_for(func():return ready() and widgets_ready() and viewer._session.last_backend=="godot"),"native transport stops before same-world bind")
	var old := widgets(); var focus: LineEdit=await focus_edit(old)
	old.camera=viewer.ui.fields.camera_choice
	check(is_instance_valid(old.camera),"same-world camera reference is current immediately before target detachment")
	var old_ids := identity(old)
	viewer.world=null;viewer.world=world
	retired(old,focus,"same-world bind")
	if test.native: check(world.start_native_view(),"native transport restarts after same-world bind")
	check(await test.wait_for(ready),"same-world rebind presents a fresh frame")
	await fresh_controls(old_ids,"hinge","drive","hold","same-world bind")
	# Stage a genuine authored revision with the SAME integer IDs and different
	# semantic targets. Hold automatic delivery to inspect the pre-5 Hz window.
	old=widgets(); focus=await focus_edit(old)
	old.camera=viewer.ui.fields.camera_choice
	check(is_instance_valid(old.camera),"current camera reference is captured after real text focus settles")
	old_ids=identity(old)
	var previous_revision: int=viewer._session.frame.revision
	var previous_joint_id: int=viewer._session.details.joints[0].id
	viewer.set_process(false);viewer._session.set_process(false)
	var adapter: Node=world.native_view if test.native else null
	if is_instance_valid(adapter): adapter.set_process(false)
	for row in [["joint","hinge","hinge_v2"],["actuator","drive","drive_v2"],["equality","hold","hold_v2"]]:
		if row[0]=="joint":
			var entities: Array=robot.design.entities().filter(func(entity):return entity.kind==row[0] and entity.name==row[1])
			check(entities.size()==1,"prepare real author rename for joint")
			if entities.size()!=1: continue
			var changed: Dictionary=Commands.execute(robot.design,{"op":"rename","id":entities[0].id,"name":row[2]})
			check(changed.has("after") and str(changed.get("error","")).is_empty(),"author rename transaction succeeds for joint")
			if changed.has("after"): robot.design.restore_author(changed.after)
		else:
			# Non-node MJCF sections are retained as author XML. Supply a real
			# candidate snapshot, without claiming a new editor rename feature.
			var candidate: Dictionary=robot.design.author_snapshot()
			var elements: Array=Xml.section(candidate.tree,row[0]).get("children",[]).filter(func(element):return element.get("attrs",{}).get("name","")==row[1])
			check(elements.size()==1,"prepare real author XML replacement for "+str(row[0]))
			if elements.size()!=1: continue
			var replaced_id: String=elements[0].id
			elements[0].id=Xml.uuid(); elements[0].attrs.name=row[2]
			if row[0]=="actuator":
				candidate.initial_controls.erase(replaced_id); candidate.initial_controls[elements[0].id]=0.
			else: elements[0].attrs.body1="arm"
			candidate.revision+=1
			check(robot.design.restore_author(candidate).is_empty(),"author snapshot replacement succeeds for "+str(row[0]))
	var definition: Dictionary=robot.author_definition()
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("binding-candidate.xml"),FileAccess.WRITE).store_string(definition.xml)
	var stage_result: Variant=PhysicsServer3D.call("scene_stage_author_model",world.space,robot.model_rid,definition)
	var started_at := Time.get_ticks_msec()
	await test.wait_for(func():return world.info().get("compile_status")=="failed" or int(world.info().get("revision",0))>previous_revision and not world.info().get("design_pending",true),30)
	var committed_info: Dictionary=world.info()
	var actual_commit: bool=int(committed_info.get("revision",0))>previous_revision and not committed_info.get("design_pending",true) and committed_info.get("compile_status")!="failed"
	var view_handshake := false
	if actual_commit and committed_info.get("compile_status")=="rendering":
		# This probe held automatic display delivery and changed no geometry.
		# Acknowledge reuse of the existing meshes via the real author-view API.
		view_handshake=PhysicsServer3D.call("scene_author_views_ready",world.space)
	check(actual_commit,"real author compiler commits a new model revision")
	var diagnostic := {"elapsed_ms":Time.get_ticks_msec()-started_at,"stage_return":str(stage_result),"definition_revision":definition.get("revision",-1),"definition_references_new_joint":str(definition.xml).contains('joint="hinge_v2"'),"views_pending":world.views_pending,"compiler_busy":world.author_compiler.busy(),"geometry_unchanged_view_handshake":view_handshake,"info":committed_info}
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("binding-stage.json"),FileAccess.WRITE).store_string(JSON.stringify(diagnostic,"  "))
	print("BINDING_STAGE ",JSON.stringify({"elapsed_ms":diagnostic.elapsed_ms,"stage_return":diagnostic.stage_return,"status":committed_info.get("compile_status"),"revision":committed_info.get("revision"),"error":committed_info.get("last_error"),"view_handshake":view_handshake}))
	if not actual_commit:
		await abort_probe(adapter); return
	var opts: Dictionary=viewer._session.frame_options("native" if test.native else "godot"); opts.inspect=true
	var packet: Dictionary=PhysicsServer3D.call("scene_viewer_frame",world.space,-1,opts)
	check(packet.has("inspect") and int(packet.get("revision",0))>previous_revision,"new revision inspection is from the actual PhysicsServer frozen frame")
	if not packet.has("inspect"):
		print("BINDING_PACKET ",JSON.stringify(packet))
		await abort_probe(adapter); return
	check(robot.state().controls.has("drive_v2") and robot.state().joints.has("hinge_v2") and str(packet.inspect.equalities[0].name).ends_with("hold_v2"),"actual compiled revision contains the replacement actuator, joint and equality targets")
	check(int(packet.inspect.controls[0].id)==0 and int(packet.inspect.equalities[0].id)==0 and int(packet.inspect.joints[0].id)==previous_joint_id,"new semantic targets overlap the stale widgets' integer IDs")
	var committed_control: float=robot.state().controls.get("drive_v2",1000)
	var committed_joint: float=robot.state().joints.get("hinge_v2",{}).get("qpos",[1000])[0]
	var committed_equality: bool=packet.get("inspect",{}).get("equalities",[{"value":false}])[0].value
	commit_evidence={"source":"actual scene_stage_author_model compiler commit and scene_viewer_frame delivery","space":world.space.get_id(),"old_revision":previous_revision,"new_revision":packet.revision,"joint_id":previous_joint_id,"control_id":packet.inspect.controls[0].id,"equality_id":packet.inspect.equalities[0].id,"joint_name":packet.inspect.joints[0].name,"control_name":packet.inspect.controls[0].name,"equality_name":packet.inspect.equalities[0].name,"replacement_actuator_uid":true,"replacement_equality_body":"arm","baseline_control":committed_control,"baseline_joint":committed_joint,"baseline_equality":committed_equality}
	check(is_instance_valid(old.control) and old.control.is_inside_tree(),"old widgets remain available immediately before new packet delivery")
	viewer._session.accept_frame(packet)
	retired(old,focus,"actual model revision")
	await test.physics_frame; await test.physics_frame
	check(absf(robot.state().controls.get("drive_v2",1000)-committed_control)<1e-8 and absf(robot.state().joints.get("hinge_v2",{}).get("qpos",[1000])[0]-committed_joint)<1e-8,"stale controls do not change the new revision's actual actuator or joint state")
	viewer.set_process(true);viewer._session.set_process(true)
	if is_instance_valid(adapter): adapter.set_process(true)
	check(await test.wait_for(ready),"new model revision resumes actual display")
	await fresh_controls(old_ids,"hinge_v2","drive_v2","hold_v2","actual model revision")
	check(viewer._session.details.equalities[0].value==committed_equality,"stale equality click does not change the new revision's real constraint")
	commit_evidence["control_after_stale_input"]=robot.state().controls.drive_v2
	commit_evidence["joint_after_stale_input"]=robot.state().joints.hinge_v2.qpos[0]
	commit_evidence["equality_after_stale_input"]=viewer._session.details.equalities[0].value
	# A saved-scene reload creates a different world/space. Observe bind itself,
	# before deferred deletion or the first new-world inspection can occur.
	old=widgets(); focus=await focus_edit(old)
	old.camera=viewer.ui.fields.camera_choice
	check(is_instance_valid(old.camera),"current camera reference is captured after real text focus settles")
	old_ids=identity(old)
	# Hold old-world display delivery during the async candidate build. Native
	# suspension can otherwise legitimately rebuild the old camera dropdown
	# before the world-bind boundary this probe is specifically inspecting.
	viewer.set_process(false); viewer._session.set_process(false)
	adapter=world.native_view if test.native else null
	if is_instance_valid(adapter): adapter.set_process(false)
	var previous_world_id: int=world.get_instance_id()
	var previous_space: RID=world.space
	var observed := {"bound":false}
	var on_world := func(new_world: Node3D):
		if new_world.get_instance_id()==previous_world_id: return
		observed.bound=true
		retired(old,focus,"different-world bind")
	viewer.target_changed.connect(on_world)
	await test.issue({"action":"reload"})
	viewer.set_process(true)
	check(await test.wait_for(func():return observed.bound and viewer._pending_reload.is_empty() and viewer.bound_world.get_instance_id()!=previous_world_id,120),"saved-source reload performs an actual different-world bind")
	viewer.target_changed.disconnect(on_world)
	world=viewer.bound_world; test.world=world; robot=world.get_node("Robot")
	check(world.space!=previous_space and await test.wait_for(ready),"replacement world owns a different authority space and displays a valid frame")
	await fresh_controls(old_ids,"hinge","drive","hold","different-world bind")
	check(absf(robot.state().controls.drive)<1e-8 and absf(robot.state().joints.hinge.qpos[0])<1e-8 and not viewer._session.details.equalities[0].value,"stale input leaves the new saved world's actual initial controls, joint and equality unchanged")
	FileAccess.open(OS.get_environment("GMJ_VIEWER_OUT").path_join("binding-observations.json"),FileAccess.WRITE).store_string(JSON.stringify({"native":test.native,"scope":"real same-world bind; actual same-space author revision delivery; saved-source different-world reload","observations":observations,"commit":commit_evidence,"final_space":world.space.get_id(),"final_revision":viewer._session.frame.revision},"  "))
	world.stop_native_view()
	if is_instance_valid(viewer.environment_host): viewer.environment_host.queue_free()
	test.game_root.queue_free()
	for unused in 5: await test.process_frame

func abort_probe(adapter: Node) -> void:
	viewer.set_process(true);viewer._session.set_process(true)
	if is_instance_valid(adapter): adapter.set_process(true)
	world.stop_native_view(); test.game_root.queue_free()
	for unused in 5: await test.process_frame
