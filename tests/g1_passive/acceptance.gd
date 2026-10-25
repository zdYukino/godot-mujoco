extends SceneTree
var passed:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(count: int) -> void:
	for i in count: await physics_frame; await process_frame
func projected_robot(camera: Camera3D,robot: Node3D) -> Rect2:
	var rect:=Rect2()
	var first:=true
	for mesh in robot.visuals.values():
		var box: AABB=mesh.mesh.get_aabb()
		for i in 8:
			var point: Vector3=mesh.global_transform*box.get_endpoint(i)
			if camera.is_position_behind(point): return Rect2(-10000,-10000,0,0)
			var pixel:=camera.unproject_position(point)
			if first: rect=Rect2(pixel,Vector2.ZERO); first=false
			else: rect=rect.expand(pixel)
	return rect
func check_frame(camera: Camera3D,robot: Node3D,min_pixels: float,label: String) -> void:
	var rect:=projected_robot(camera,robot)
	var viewport:=camera.get_viewport().get_visible_rect()
	print("G1_CAMERA ",label," ",rect," viewport ",viewport.size)
	check(rect.position.x>=0 and rect.position.y>=0 and rect.end.x<=viewport.size.x and rect.end.y<=viewport.size.y and maxf(rect.size.x,rect.size.y)>=min_pixels,label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	print("G1_TEST_STAGE begin ",Time.get_ticks_msec())
	print("G1_ENGINE_CONFIG ",JSON.stringify({"version":Engine.get_version_info().string,"display":DisplayServer.get_name(),"processor_count":OS.get_processor_count(),"physics_separate_thread_setting":ProjectSettings.get_setting("physics/3d/run_on_separate_thread",false),"render_thread_model_setting":ProjectSettings.get_setting("rendering/driver/threads/thread_model",-1),"native_trace":OS.get_environment("GMJ_TRACE_SCENE_LOAD")}))
	var world=load("res://G1.tscn").instantiate(); world.start_paused=true; root.add_child(world)
	await ticks(3)
	var controls=world.get_node("DisplayControls")
	var first=world.get_node("G1_1")
	check(first.model_rid.is_valid(),"saved real G1 loads into shared runtime: "+first.last_error)
	if not first.model_rid.is_valid(): world.free(); quit(1); return
	root.size=Vector2i(1180,812); await ticks(2)
	var camera=world.get_node("Camera")
	check(is_equal_approx(camera.distance,3.2) and is_equal_approx(camera.fov,50),"saved second-example camera starts in readable single-robot framing")
	var initial: Dictionary=first.state()
	check(world.info().objects.size()==2 and initial.joints.size()==30,"one floor and actual G1 with 29 hinges plus floating base")
	check(initial.controls.is_empty() and initial.actuator_parameters.is_empty() and world.info().nu==0,"zero native actuators, no hidden PD or controls")
	check(initial.bodies.values().all(func(body): return body.gravcomp==0),"zero body gravity compensation")
	check(initial.joints.floating_base.qpos.size()==7 and initial.joints.floating_base.qvel.size()==6,"real free base has qpos7 and qvel6")
	check(not controls.help_panel.visible and controls.robots.size()==1,"compact controls default to hidden help and one robot")
	var native_geoms: Array=PhysicsServer3D.call("scene_geometry",world.space,first.model_rid)
	check(native_geoms.size()==69 and native_geoms.filter(func(geom): return geom.type==7).size()==57,"original G1 visual meshes and native collision geometry retained")
	check(controls.robot_overlays[first].size()==native_geoms.filter(func(geom): return geom.contype!=0 or geom.conaffinity!=0).size(),"all native collision shapes have verified cached line overlays")
	check(native_geoms.all(func(geom): return (geom.contype==0 and geom.conaffinity==0) or (geom.contype==2 and geom.conaffinity==1)),"existing robot mask retained; no claim of robot-robot or self collision")
	var original_y: float=initial.bodies.pelvis.transform.origin.y
	world.set_paused(false)
	var positive:=false
	for i in 360:
		await ticks(1)
		for contact in world.info().contact_details:
			if contact.geoms.any(func(name): return str(name).ends_with("floor_geom")) and contact.force_contact_frame[0]>0: positive=true
	var settled: Dictionary=first.state()
	var pelvis: Transform3D=settled.bodies.pelvis.transform
	print("G1_FALL ",JSON.stringify({"initial_y":original_y,"final_y":pelvis.origin.y,"upright_dot":absf(pelvis.basis.y.dot(Vector3.UP)),"time":world.info().time}))
	check(pelvis.origin.y<original_y-.3 and absf(pelvis.basis.y.dot(Vector3.UP))<.7,"uncontrolled G1 naturally loses upright support and collapses")
	check(positive and pelvis.origin.y>-.1 and pelvis.is_finite(),"single G1 has real positive floor contact and finite pose")
	check(world.info().warning_count==0,"single G1 produces no MuJoCo warnings")
	var bad=controls.model.model.duplicate(true)
	bad.snapshot.xml=bad.snapshot.xml.replace("<option ","<option gravity='0 0 -1' ")
	ResourceSaver.save(bad,"res://invalid_world_options.tres")
	bad=load("res://invalid_world_options.tres")
	check_frame(camera,first,160,"fallen first G1 remains readable and fully framed at 1180x812")
	var failure: Dictionary=controls.add_robot(bad)
	if failure.success:
		check(false,"failure probe must not add a model"); world.free(); quit(1); return
	check(str(failure.error).contains("conflict"),"failure probe reaches native world option conflict gate")
	check(not failure.success and failure.state_preserved and failure.first_rid_preserved and failure.objects_before==failure.objects_after and failure.time_before==failure.time_after and failure.pause_preserved,"failed hot addition preserves original native world, time and full qpos/qvel")
	# Reject after spec ownership has transferred, not only at option validation.
	world.set_paused(true)
	var rejected_before: Dictionary=first.state().joints.duplicate(true)
	var rejected_time: float=world.info().time
	var invalid_pose:=Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO)
	var floor_resource=controls.model.model
	var rejected: RID=PhysicsServer3D.call("scene_load_model",world.space,floor_resource.snapshot,floor_resource.resource_path.get_base_dir(),"invalid_pose_after_transfer",invalid_pose)
	check(not rejected.is_valid() and world.info().last_error.contains("rigid pose"),"post-transfer insertion rejection releases consumed spec safely")
	check(world.info().objects.size()==2 and first.state().joints==rejected_before and world.info().time==rejected_time,"post-transfer rejection preserves original world state and time")
	world.set_paused(false)
	print("G1_TEST_STAGE before_hot_add ",Time.get_ticks_msec())
	controls.add_button.pressed.emit()
	check(controls.busy and controls.add_button.disabled,"hot-add button enters visible busy state")
	controls.request_add()
	while controls.busy: await process_frame
	print("G1_TEST_STAGE after_hot_add ",Time.get_ticks_msec())
	var added: Dictionary=controls.last_add
	print("G1_HOT_ADD ",JSON.stringify(added))
	if not added.get("success",false):
		check(false,"second G1 did not load"); world.free(); quit(1); return
	check(added.success and controls.robots.size()==2 and world.info().objects.size()==3,"exactly one second native G1 added without replacing floor or first robot")
	check(added.state_preserved and added.first_rid_preserved and added.time_before==added.time_after and added.pause_preserved and not world.info().paused,"hot compile preserves first qpos/qvel, RID, time and running state")
	check(controls.robots[0].model_rid!=controls.robots[1].model_rid and controls.add_button.disabled,"distinct native RIDs and bounded two-robot UI")
	check(not controls.add_robot(controls.robot_model).success and world.info().objects.size()==3,"third addition rejected without native topology changes")
	check(camera.robot_count==2 and is_equal_approx(camera.distance,4.8),"successful hot-add automatically frames both spawn regions")
	var second=controls.robots[1]
	var second_initial: Dictionary=second.state().joints.duplicate(true)
	var second_start: float=second.state().bodies.pelvis.transform.origin.y
	var second_positive:=false
	for i in 360:
		await ticks(1)
		var info: Dictionary=world.info()
		for index in info.contacts.size():
			var pair: Array=info.contacts[index]
			if pair.has(second.model_rid) and pair.has(controls.model.model_rid) and info.contact_details[index].force_contact_frame[0]>0: second_positive=true
	check(second.state().bodies.pelvis.transform.origin.y<second_start-.3 and second_positive,"hot-added second G1 naturally falls and has positive normal contact force against same floor")
	check(world.info().nu==0 and world.info().warning_count==0 and world.info().time>added.time_after+4,"two passive robots continue native time with no actuators or warnings")
	world.set_paused(true)
	check_frame(camera,first,90,"fallen first G1 remains readable in pair view")
	check_frame(camera,second,90,"fallen second G1 remains readable in pair view")
	var camera_state: Dictionary=first.state().joints.duplicate(true)
	var camera_before: Transform3D=camera.transform
	camera.zoom(.9)
	check(not camera.transform.is_equal_approx(camera_before) and first.state().joints==camera_state,"camera zoom changes only view, never robot state")
	for i in 30: camera.zoom(.5)
	check(is_equal_approx(camera.distance,4.2),"pair camera zoom-in keeps both robots within the framing limit")
	check_frame(camera,first,100,"closest pair zoom keeps first robot fully visible")
	check_frame(camera,second,100,"closest pair zoom keeps second robot fully visible")
	for i in 30: camera.zoom(2.0)
	check(is_equal_approx(camera.distance,9.0),"camera zoom-out stays bounded")
	camera.frame_for_count(2)
	check(camera.transform.is_equal_approx(camera_before) and first.state().joints==camera_state,"reframing restores pair view without physics changes")
	var state_before: Dictionary=first.state().joints.duplicate(true)
	for visual in [true,false]:
		for collision in [true,false]:
			controls.entities.set_pressed_no_signal(visual); controls.collisions.set_pressed_no_signal(collision); controls.apply_display()
			check(controls.robots.all(func(robot): return robot.visuals.values().all(func(mesh): return mesh.visible==visual) and controls.robot_overlays[robot].values().all(func(node): return node.visible==collision)) and first.state().joints==state_before,"two-robot display modes leave physical state unchanged")
	controls.reset_button.pressed.emit()
	for i in 12:
		await ticks(1)
		if world.command_request==0: break
	check(world.last_error.is_empty() and first.state().joints==initial.joints and second.state().joints==second_initial and world.info().objects.size()==3,"reset after hot-add restores both load poses without removing either model")
	var memory: Array=[]
	OS.execute("cat",["/proc/"+str(OS.get_process_id())+"/status"],memory)
	for line in str(memory[0] if not memory.is_empty() else "").split("\n"):
		if line.begins_with("VmHWM:"): print("G1_MEMORY ",line)
	world.free(); await ticks(2)
	print("G1_PASSIVE_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"scope":"bounded two real G1 native runtime; actual GUI screenshots separate"}))
	quit(0 if failed==0 else 1)
