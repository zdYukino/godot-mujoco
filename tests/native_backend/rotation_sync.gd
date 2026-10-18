extends SceneTree
## A rotating sphere has isotropic inertia: its world angular velocity stays fixed.
## Exercise server -> Godot -> server transforms across repeated world reentry.
var failures: Array[String] = []
var checks := 0
var max_scale_error := 0.0
var max_determinant_error := 0.0
var max_orthogonality_error := 0.0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr("FAIL ",label)
func ticks(count: int) -> void:
	for unused in count:
		await physics_frame
		await process_frame
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var ball := RigidBody3D.new()
	ball.gravity_scale = 0.0
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 0.0
	ball.angular_damp = 0.0
	ball.rotation = Vector3(.31,-.72,.43)
	var collision := CollisionShape3D.new()
	collision.shape = SphereShape3D.new()
	ball.add_child(collision)
	viewport.add_child(ball)
	var omega := Vector3(.71,-.83,.57)
	for cycle in range(20):
		ball.angular_velocity = omega
		await ticks(2)
		var initial := ball.basis.get_rotation_quaternion().normalized()
		var frame_start := Engine.get_physics_frames()
		for frame in range(120):
			await ticks(1)
			var b := ball.basis
			max_scale_error = max(max_scale_error,max(abs(b.x.length()-1.0),max(abs(b.y.length()-1.0),abs(b.z.length()-1.0))))
			max_determinant_error = max(max_determinant_error,abs(b.determinant()-1.0))
			max_orthogonality_error = max(max_orthogonality_error,max(abs(b.x.dot(b.y)),max(abs(b.x.dot(b.z)),abs(b.y.dot(b.z)))))
		var elapsed := float(Engine.get_physics_frames()-frame_start)/60.0
		var expected := Quaternion(omega.normalized(),omega.length()*elapsed)*initial
		check(abs(expected.dot(ball.basis.get_rotation_quaternion().normalized()))>.99999,"world rotation and coordinate mapping "+str(cycle))
		check(ball.angular_velocity.distance_to(omega)<.0001,"world angular velocity retained "+str(cycle))
		check(max_scale_error<.000002 and max_determinant_error<.000002 and max_orthogonality_error<.000002,"unit orthogonal basis without accumulation "+str(cycle))
		var before := ball.transform
		root.remove_child(viewport)
		await process_frame
		root.add_child(viewport)
		check(ball.transform.is_equal_approx(before),"world reentry retains authored rigid pose "+str(cycle))
	viewport.free()
	await process_frame
	print("ROTATION_SYNC_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"world_reentries":20,"rotation_frames":2400,"max_scale_error":max_scale_error,"max_determinant_error":max_determinant_error,"max_orthogonality_error":max_orthogonality_error}))
	quit(0 if failures.is_empty() else 1)
