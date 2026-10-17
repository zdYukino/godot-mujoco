extends Node3D
const G1 = "res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf"
var checks: Array[Dictionary] = []
var space: RID
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	print("PASS " if ok else "FAIL ", name)
func info() -> Dictionary:
	return PhysicsServer3D.call("scene_info", space)
func state(id: RID) -> Dictionary:
	return PhysicsServer3D.call("scene_state", space, id)
func pause(value: bool) -> void:
	check(PhysicsServer3D.call("scene_pause", space, value), "pause_%s" % value)
func box(label: String, position: Vector3, size: Vector3, mass: float) -> RID:
	return PhysicsServer3D.call("scene_add_box", space, label, Transform3D(Basis.IDENTITY, position), size, mass)
func robot(label: String, position: Vector3) -> RID:
	return PhysicsServer3D.call("scene_import_g1", space, G1, label, Transform3D(Basis.IDENTITY, position))
func remove(id: RID) -> bool:
	return PhysicsServer3D.call("scene_remove", space, id)
func ticks(count: int) -> void:
	for unused in count:
		await get_tree().physics_frame
		await get_tree().process_frame
func unchanged(before: Dictionary, id: RID, label: String) -> void:
	var after := state(id)
	check(before["joints"] == after["joints"], label + "_joint_pose_velocity")
	check(before["controls"] == after["controls"], label + "_controls")
	var a: Array = before["geoms"]
	var b: Array = after["geoms"]
	var same := a.size() == b.size()
	for i in mini(a.size(), b.size()):
		same = same and a[i].name == b[i].name and (a[i].transform as Transform3D).is_equal_approx(b[i].transform)
	check(same, label + "_geometry_pose_identity")
func _ready() -> void:
	await ticks(2)
	space = get_world_3d().space
	check(PhysicsServer3D.get_class() == "MjPhysicsServer3D", "actual_backend")
	pause(true)
	var base := info()
	var floor_id := box("floor", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20), 0)
	check(floor_id.is_valid(), "floor_added")
	var g1 := robot("G1", Vector3(0, 1.1, 0))
	check(g1.is_valid(), "original_urdf_imported")
	if not g1.is_valid():
		print(info())
		get_tree().quit(1)
		return
	check(state(g1).joints.size() == 29 and state(g1).controls.size() == 29, "real_29_joints_and_drives")
	check(state(g1).geoms.size() == 69 and state(g1).body_count >= 29, "real_g1_bodies_geometries")
	check(info().nu == 29 and info().njnt == 29, "shared_compiled_model_counts")
	var geometry: Array = PhysicsServer3D.call("scene_geometry", space, g1)
	check(geometry.size() == 69 and geometry[0].vertices.size() > 0, "render_meshes_from_compiled_physics")
	var initial_time: float = info().time
	await ticks(5)
	check(info().time == initial_time, "paused_world_does_not_step")
	check(PhysicsServer3D.call("scene_set_control", space, g1, "left_elbow_joint", 0.2), "joint_control_accepted")
	pause(false)
	await ticks(90)
	pause(true)
	var saved := state(g1)
	check(absf(saved.joints.left_elbow_joint.qpos[0] - 0.2) < 0.01, "joint_drive_moves_real_joint")
	# A moving free body must retain its full state through topology changes.
	var falling := box("moving", Vector3(3, 4, 0), Vector3(0.4, 0.4, 0.4), 1)
	check(falling.is_valid(), "moving_box_added")
	if not falling.is_valid():
		print(info())
		get_tree().quit(1)
		return
	pause(false)
	await ticks(12)
	pause(true)
	var before_box := state(falling)
	check(absf(before_box.joints.free.qvel[2]) > 0.1, "obstacle_has_real_gravity_velocity")
	var native := RigidBody3D.new()
	native.position = Vector3(8, 3, 0)
	native.gravity_scale = 0
	native.collision_layer = 4
	native.collision_mask = 0
	var native_shape := CollisionShape3D.new()
	native_shape.shape = BoxShape3D.new()
	native.add_child(native_shape)
	add_child(native)
	native.linear_velocity = Vector3(0.1, 0.2, 0.3)
	native.angular_velocity = Vector3(0.2, 0.3, 0.1)
	pause(true)
	var native_pose: Transform3D = PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
	var native_velocity: Vector3 = PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var native_spin: Vector3 = PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
	saved = state(g1)
	var before_time: float = info().time
	var second := robot("G1-copy", Vector3(2, 1.1, 2))
	check(second.is_valid() and second != g1, "second_robot_unique_rid")
	check(info().nu == 58, "two_robots_share_one_model")
	unchanged(saved, g1, "add_robot_preserves_robot")
	unchanged(before_box, falling, "add_robot_preserves_moving_box")
	check(info().time == before_time, "transaction_preserves_time")
	check((PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).is_equal_approx(native_pose), "native_rigidbody_pose_preserved")
	check(PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) == native_velocity, "native_rigidbody_velocity_preserved")
	check(PhysicsServer3D.body_get_state(native.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) == native_spin, "native_rigidbody_angular_velocity_preserved")
	check(remove(second), "remove_second_robot")
	check(state(second).is_empty(), "removed_robot_stale_rid_empty")
	unchanged(saved, g1, "remove_robot_preserves_robot")
	unchanged(before_box, falling, "remove_robot_preserves_box")
	var revision: int = info().revision
	var objects: int = info().objects.size()
	var bad: RID = PhysicsServer3D.call("scene_import_g1", space, "res://invalid.urdf", "bad", Transform3D.IDENTITY)
	check(not bad.is_valid() and not info().last_error.is_empty(), "invalid_urdf_rejected")
	check(not box("invalid-mass", Vector3.ZERO, Vector3.ONE, 1e-20).is_valid(), "candidate_compile_failure_rejected")
	check(info().revision == revision and info().objects.size() == objects, "failed_compile_rolls_back_revision_and_objects")
	unchanged(saved, g1, "rollback_preserves_robot")
	unchanged(before_box, falling, "rollback_preserves_box")
	check(not robot("G1", Vector3.ZERO).is_valid(), "duplicate_label_rejected")
	check(not remove(second), "stale_remove_rejected")
	pause(false)
	check(not box("unpaused", Vector3.ZERO, Vector3.ONE, 1).is_valid(), "unpaused_edit_rejected")
	await ticks(150)
	pause(true)
	check(absf((state(falling).geoms[0].transform as Transform3D).origin.y - 0.2) < 0.04, "obstacle_collides_with_floor")
	# Drop a broad box onto the robot: require an actual robot/obstacle contact pair.
	var impact := box("impact", Vector3(0, 3, 0), Vector3(0.6, 0.4, 0.6), 0.5)
	pause(false)
	var contacted := false
	var no_warnings := true
	for unused in 180:
		await ticks(1)
		no_warnings = no_warnings and info().warning_count == 0
		for pair in info().contacts:
			if pair.has(g1) and pair.has(impact):
				contacted = true
	pause(true)
	check(contacted, "g1_and_obstacle_contact_in_same_world")
	check(no_warnings, "contact_simulation_no_mujoco_warnings")
	var finite := true
	for value in state(g1).joints.values():
		for q in value.qpos: finite = finite and is_finite(q)
		for v in value.qvel: finite = finite and is_finite(v)
	check(finite, "robot_state_finite_after_contact")
	check(remove(impact), "remove_impact")
	var old_rids: Array[RID] = [second]
	for cycle in 3:
		saved = state(g1)
		var added := robot("cycle", Vector3(-2, 1.1, 2))
		check(added.is_valid() and not old_rids.has(added), "cycle_unique_rid_%d" % cycle)
		old_rids.append(added)
		check(remove(added), "cycle_remove_%d" % cycle)
		check(state(added).is_empty() and info().nu == 29, "cycle_no_stale_resources_%d" % cycle)
		unchanged(saved, g1, "cycle_preserves_%d" % cycle)
	# A separate World3D cannot access or remove these instances.
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var node := Node3D.new()
	viewport.add_child(node)
	var other_space := node.get_world_3d().space
	check(PhysicsServer3D.call("scene_pause", other_space, true), "second_space_pause")
	check((PhysicsServer3D.call("scene_state", other_space, g1) as Dictionary).is_empty(), "space_identity_isolation")
	var other: RID = PhysicsServer3D.call("scene_add_box", other_space, "other", Transform3D.IDENTITY, Vector3.ONE, 1.0)
	check(other.is_valid(), "other_space_object")
	PhysicsServer3D.free_rid(other)
	check((PhysicsServer3D.call("scene_state", other_space, other) as Dictionary).is_empty(), "generic_free_obeys_transaction")
	other = PhysicsServer3D.call("scene_add_box", other_space, "disposal", Transform3D.IDENTITY, Vector3.ONE, 1.0)
	check(other.is_valid(), "other_space_replacement")
	viewport.queue_free()
	await ticks(3)
	check((PhysicsServer3D.call("scene_info", other_space) as Dictionary).is_empty(), "freed_space_resources_released")
	check(remove(g1) and remove(falling) and remove(floor_id), "remove_all")
	native.free()
	pause(true)
	check(info().objects.is_empty() and info().nbody == base.nbody and info().ngeom == base.ngeom and info().nu == 0, "world_returns_to_empty_baseline")
	var passed := 0
	for c in checks:
		if c.passed: passed += 1
	var report := {"passed": passed, "failed": checks.size()-passed, "checks": checks, "backend": PhysicsServer3D.get_class()}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			FileAccess.open(arg.trim_prefix("--report="), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DYNAMIC_RESULT ", JSON.stringify(report))
	get_tree().quit(0 if report.failed == 0 else 1)
