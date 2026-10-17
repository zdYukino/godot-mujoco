extends Node3D
## Ordinary Godot APIs only: no MjWorld or direct MuJoCo stepping.
var passed := 0
var failed := 0
var checks: Array[Dictionary] = []
var measurements: Dictionary = {}

func check_ok(condition: bool, label: String, detail: String = "") -> void:
	checks.append({"name": label, "passed": condition, "detail": detail})
	if condition:
		passed += 1
		print("PASS ", label, " ", detail)
	else:
		failed += 1
		print("FAIL ", label, " ", detail)

func ticks(count: int) -> void:
	for _i in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func add_box(parent: Node, size: Vector3, at: Vector3, dynamic: bool, layer: int = 1) -> PhysicsBody3D:
	var body: PhysicsBody3D = RigidBody3D.new() if dynamic else StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func ray(world: World3D, from: Vector3, to: Vector3, mask: int = 0xffffffff, excluded: Array[RID] = []) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, excluded)
	return world.direct_space_state.intersect_ray(query)

func _ready() -> void:
	await ticks(2)
	var backend := PhysicsServer3D.get_class()
	check_ok(backend == "MjPhysicsServer3D", "runtime_backend_identity", backend)
	check_ok(ProjectSettings.get_setting("physics/3d/physics_engine") == "MuJoCo", "backend_setting")
	var floor_body := add_box(self, Vector3(20, 1, 20), Vector3(0, -0.5, 0), false)
	var falling := add_box(self, Vector3.ONE, Vector3(0, 3, 0), true) as RigidBody3D
	await ticks(20)
	check_ok(falling.position.y < 2.9, "ordinary_rigidbody_falls", str(falling.position))
	check_ok(falling.linear_velocity.y < -0.5, "gravity_velocity_callback", str(falling.linear_velocity))
	await ticks(220)
	measurements["rest_y"] = falling.position.y
	measurements["rest_velocity"] = str(falling.linear_velocity)
	check_ok(absf(falling.position.y - 0.5) < 0.04, "floor_rest_height", str(falling.position))
	check_ok(falling.linear_velocity.length() < 0.08, "rest_velocity", str(falling.linear_velocity))
	check_ok(falling.transform.is_finite(), "finite_transform")
	check_ok(absf(falling.basis.determinant() - 1.0) < 0.001, "rotation_determinant", str(falling.basis.determinant()))
	check_ok(falling.basis.is_equal_approx(falling.basis.orthonormalized()), "rotation_orthonormal")
	var hit := ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0))
	check_ok(not hit.is_empty(), "ray_hit_present")
	# Check every promised field even when a hit is absent; no silent skip.
	check_ok(hit.get("rid") == falling.get_rid(), "ray_hit_rid")
	check_ok(hit.get("collider_id") == falling.get_instance_id(), "ray_hit_object_id")
	check_ok(hit.get("collider") == falling, "ray_hit_object")
	check_ok((hit.get("position", Vector3.INF) as Vector3).distance_to(Vector3(0, 1, 0)) < 0.05, "ray_position", str(hit.get("position")))
	check_ok((hit.get("normal", Vector3.ZERO) as Vector3).dot(Vector3.UP) > 0.99, "ray_normal", str(hit.get("normal")))
	check_ok(ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0), 2).is_empty(), "ray_collision_mask_miss")
	check_ok(ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0), 1, [falling.get_rid()]).get("rid") == floor_body.get_rid(), "ray_exclusion_reveals_floor")
	check_ok(ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0), 1, [falling.get_rid(), floor_body.get_rid()]).is_empty(), "ray_exclusion_all_miss")
	check_ok(ray(get_world_3d(), Vector3(100, 5, 0), Vector3(100, -2, 0)).is_empty(), "ray_outside_miss")
	falling.linear_velocity = Vector3(1, 2, 0)
	check_ok(falling.linear_velocity.distance_to(Vector3(1, 2, 0)) < 0.001, "velocity_property_write_read")
	check_ok((PhysicsServer3D.body_get_state(falling.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3).distance_to(Vector3(1, 2, 0)) < 0.001, "velocity_server_write_read")
	var before_x := falling.position.x
	await ticks(6)
	check_ok(falling.position.x > before_x + 0.04, "velocity_moves_body", str(falling.position))
	for cycle in 3:
		remove_child(falling)
		await ticks(2)
		check_ok(ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, 0.1, 0)).is_empty(), "detached_body_absent_%d" % cycle)
		falling.position = Vector3(0, 2, 0)
		falling.linear_velocity = Vector3.ZERO
		add_child(falling)
		await ticks(180)
		check_ok(absf(falling.position.y - 0.5) < 0.04, "reentry_rest_%d" % cycle, str(falling.position))
	# Asymmetric, rotated and offset geometry catches Y/Z and basis conversion bugs.
	var oriented := add_box(self, Vector3(2, 1, 4), Vector3(5, 2, 3), false, 4)
	oriented.rotation = Vector3(0.31, 0.43, 0.17)
	var oriented_shape := oriented.get_child(0) as CollisionShape3D
	oriented_shape.position = Vector3(0.3, 0.2, -0.4)
	await ticks(3)
	var half_sizes := Vector3(1, 0.5, 2)
	for axis in 3:
		var local_direction := Vector3.ZERO
		local_direction[axis] = 1.0
		var surface := oriented_shape.global_transform * (local_direction * half_sizes[axis])
		var normal := oriented_shape.global_basis * local_direction
		var rotated_hit := ray(get_world_3d(), surface + normal, surface - normal * 0.2, 4)
		check_ok(rotated_hit.get("rid") == oriented.get_rid(), "oriented_box_rid_%d" % axis)
		check_ok((rotated_hit.get("position", Vector3.INF) as Vector3).distance_to(surface) < 0.005, "oriented_box_surface_%d" % axis)
		check_ok((rotated_hit.get("normal", Vector3.ZERO) as Vector3).dot(normal) > 0.999, "oriented_box_normal_%d" % axis)
	oriented.queue_free()
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var other := Node3D.new()
	viewport.add_child(other)
	var other_floor := add_box(other, Vector3(4, 1, 4), Vector3(0, 9.5, 0), false, 2)
	await ticks(3)
	check_ok(other.get_world_3d().space != get_world_3d().space, "world_space_rids_distinct")
	check_ok(ray(get_world_3d(), Vector3(0, 12, 0), Vector3(0, 8, 0), 2).is_empty(), "main_world_excludes_other_world")
	check_ok(ray(other.get_world_3d(), Vector3(0, 12, 0), Vector3(0, 8, 0), 2).get("rid") == other_floor.get_rid(), "other_world_own_hit")
	check_ok(ray(other.get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0), 1).is_empty(), "other_world_excludes_main_world")
	var old_id := other_floor.get_instance_id()
	viewport.queue_free()
	await ticks(3)
	check_ok(not is_instance_id_valid(old_id), "freed_world_object_released")
	var replacement := SubViewport.new()
	replacement.own_world_3d = true
	add_child(replacement)
	var replacement_root := Node3D.new()
	replacement.add_child(replacement_root)
	await ticks(3)
	check_ok(ray(replacement_root.get_world_3d(), Vector3(0, 12, 0), Vector3(0, -2, 0)).is_empty(), "new_world_has_no_old_references")
	replacement.queue_free()
	falling.queue_free()
	floor_body.queue_free()
	await ticks(3)
	check_ok(ray(get_world_3d(), Vector3(0, 5, 0), Vector3(0, -2, 0)).is_empty(), "freed_bodies_absent")
	var result := {"backend": backend, "passed": passed, "failed": failed, "checks": checks, "measurements": measurements, "physics_hz": Engine.physics_ticks_per_second, "godot_version": Engine.get_version_info()["string"]}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			if output:
				output.store_string(JSON.stringify(result, "\t") + "\n")
	print("NATIVE_BACKEND_RESULT ", JSON.stringify(result))
	get_tree().quit(0 if failed == 0 else 1)
