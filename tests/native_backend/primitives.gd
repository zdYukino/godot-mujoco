extends SceneTree
## Additional minimum-backend coverage: sphere/plane contacts and filtering.
var checks: Array[Dictionary] = []
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func check_ok(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	print("PASS " if ok else "FAIL ", label)

func ticks(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame

func ray(from: Vector3, to: Vector3, mask: int = 1, excluded: Array[RID] = [], inside: bool = false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, excluded)
	query.hit_from_inside = inside
	return scene.get_world_3d().direct_space_state.intersect_ray(query)

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	for type_name in ["MjDirectBodyState", "MjDirectSpaceState", "MjPhysicsServer3D"]:
		check_ok(not ClassDB.can_instantiate(type_name), "server_owned_" + type_name)
	var plane := StaticBody3D.new()
	var plane_collision := CollisionShape3D.new()
	plane_collision.shape = WorldBoundaryShape3D.new()
	plane.add_child(plane_collision)
	scene.add_child(plane)
	var ball := RigidBody3D.new()
	ball.position = Vector3(2, 3, -4)
	var ball_collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	ball_collision.shape = sphere
	ball.add_child(ball_collision)
	scene.add_child(ball)
	await ticks(240)
	check_ok(PhysicsServer3D.get_class() == "MjPhysicsServer3D", "primitive_backend_identity")
	check_ok(absf(ball.position.y - 0.5) < 0.04, "sphere_plane_rest_height")
	check_ok(ball.linear_velocity.length() < 0.08, "sphere_plane_rest_speed")
	var hit := ray(Vector3(2, 4, -4), Vector3(2, -1, -4))
	check_ok(hit.get("collider") == ball, "sphere_ray_collider")
	check_ok(hit.get("shape") == 0, "sphere_ray_shape_index")
	check_ok((hit.get("position", Vector3.INF) as Vector3).distance_to(Vector3(2, 1, -4)) < 0.04, "sphere_ray_surface")
	check_ok((hit.get("normal", Vector3.ZERO) as Vector3).dot(Vector3.UP) > 0.999, "sphere_ray_normal")
	hit = ray(Vector3(2000, 3, -4000), Vector3(2000, -1, -4000))
	check_ok(hit.get("collider") == plane, "plane_is_infinite")
	check_ok(absf((hit.get("position", Vector3.INF) as Vector3).y) < 0.0001, "plane_ray_height")
	check_ok((hit.get("normal", Vector3.ZERO) as Vector3).dot(Vector3.UP) > 0.999, "plane_ray_normal")
	check_ok(ray(ball.position, ball.position + Vector3.UP).is_empty(), "inside_sphere_default_miss")
	hit = ray(ball.position, ball.position + Vector3.UP, 1, [], true)
	check_ok(hit.get("collider") == ball and hit.get("normal") == Vector3.ZERO, "inside_sphere_explicit_hit")
	check_ok(ray(Vector3(2, 4, -4), Vector3(2, -1, -4), 1, [ball.get_rid()]).get("collider") == plane, "sphere_exclusion_reveals_plane")
	# Neither body accepts the other's layer, so the ball must fall through.
	ball.collision_layer = 2
	ball.collision_mask = 2
	ball.position = Vector3(2, 2, -4)
	ball.linear_velocity = Vector3.ZERO
	await ticks(90)
	check_ok(ball.position.y < -1, "contact_layers_filter_pair")
	# Rays use the target's layer, independently of its own collision mask.
	ball.gravity_scale = 0
	ball.position = Vector3(2, 2, -4)
	ball.linear_velocity = Vector3.ZERO
	ball.collision_mask = 0
	await ticks(2)
	check_ok(ray(Vector3(2, 4, -4), Vector3(2, 1, -4), 2).get("collider") == ball, "ray_ignores_target_mask")
	check_ok(ray(Vector3(2, 4, -4), Vector3(2, 1, -4), 1).is_empty(), "ray_obeys_target_layer")
	ball.collision_layer = 1
	ball.collision_mask = 1
	ball.gravity_scale = 1
	ball.add_collision_exception_with(plane)
	await ticks(90)
	check_ok(ball.position.y < -1, "body_collision_exception")
	ball.remove_collision_exception_with(plane)
	ball.position = Vector3(2, 2, -4)
	ball.linear_velocity = Vector3.ZERO
	await ticks(180)
	check_ok(absf(ball.position.y - 0.5) < 0.04, "removed_exception_restores_contact")
	ball.queue_free()
	# Plane offset and normal pass through both shape and body transforms.
	var boundary := plane_collision.shape as WorldBoundaryShape3D
	boundary.plane = Plane(Vector3.UP, 0.7)
	plane.position = Vector3(3, 2, -5)
	plane.rotation = Vector3(0.3, 0.2, -0.4)
	plane_collision.position = Vector3(0.2, -0.1, 0.4)
	await ticks(3)
	var point := plane_collision.global_transform * Vector3(0, 0.7, 0)
	var normal := plane_collision.global_basis * Vector3.UP
	hit = ray(point + normal * 2, point - normal)
	check_ok(hit.get("collider") == plane, "transformed_plane_collider")
	check_ok((hit.get("position", Vector3.INF) as Vector3).distance_to(point) < 0.001, "transformed_plane_position")
	check_ok((hit.get("normal", Vector3.ZERO) as Vector3).dot(normal) > 0.999, "transformed_plane_normal")
	plane.queue_free()
	await ticks(3)
	check_ok(ray(point + normal * 2, point - normal).is_empty(), "freed_primitives_absent")
	var passed := 0
	for check in checks:
		if check.passed:
			passed += 1
	var result := {"backend": PhysicsServer3D.get_class(), "passed": passed, "failed": checks.size() - passed, "checks": checks}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			var output := FileAccess.open(argument.trim_prefix("--report="), FileAccess.WRITE)
			output.store_string(JSON.stringify(result, "\t") + "\n")
	print("PRIMITIVE_RESULT ", JSON.stringify(result))
	scene.queue_free()
	await process_frame
	quit(0 if result.failed == 0 else 1)
