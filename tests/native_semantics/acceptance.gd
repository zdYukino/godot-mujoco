extends SceneTree
# Isolated native bodies. No G1 assets and no imported robot state.
var checks: Array[Dictionary] = []
var owned: Array[RID] = []
var callbacks := 0
var syncs := 0
var callback_step := 0.0
var manual := false
var release_in_callback := RID()
var released_callback := false
var sync_after_release := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String, detail: Variant = "") -> void:
 checks.append({"name": label, "passed": ok, "detail": str(detail)})
 print("PASS " if ok else "FAIL ", label, " ", detail)
func near(actual: Vector3, expected: Vector3, label: String, tolerance: float = .0001) -> void:
 check(actual.distance_to(expected) < tolerance, label, {"actual": actual, "expected": expected})
func frames(n: int = 1) -> void:
 for unused in n:
  await physics_frame
  await process_frame
func param(body: RID, key: int, value: Variant) -> void: PhysicsServer3D.body_set_param(body, key, value)
func velocity(body: RID) -> Vector3: return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
func angular(body: RID) -> Vector3: return PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
func set_velocity(body: RID, v: Vector3, w: Vector3 = Vector3.ZERO) -> void:
 PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
 PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, w)
func make_body(space: RID, mass: float = 2.0, half: Vector3 = Vector3(.5,.5,.5), pose: Transform3D = Transform3D.IDENTITY, offset: Vector3 = Vector3.ZERO) -> RID:
 var shape := PhysicsServer3D.box_shape_create(); owned.append(shape)
 PhysicsServer3D.shape_set_data(shape, half)
 var body := PhysicsServer3D.body_create(); owned.append(body)
 PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
 PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis.IDENTITY, offset))
 PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
 param(body, PhysicsServer3D.BODY_PARAM_MASS, mass)
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
 param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
 param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE, PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
 PhysicsServer3D.body_set_space(body, space)
 return body
func step(space: RID, n: int = 1) -> void:
 await command(space, "step", n)
func command(space: RID, action: String, n: int = 1) -> void:
 var request: int = PhysicsServer3D.call("scene_request_world_command", space, action, n)
 check(request > 0, "step queued")
 var result: Dictionary = {}
 for unused in 30:
  await frames()
  result = PhysicsServer3D.call("scene_world_command_result", request)
  if not result.is_empty(): break
 check(result.get("success", false), "step completed", result)
 await frames() # Completion is published at the step boundary; callbacks flush next frame.
func integrate(state: PhysicsDirectBodyState3D) -> void:
 callbacks += 1; callback_step = state.step
 if manual: state.integrate_forces()
func sync(_state: PhysicsDirectBodyState3D) -> void: syncs += 1
func free_callback(_state: PhysicsDirectBodyState3D) -> void:
 released_callback = true
 PhysicsServer3D.free_rid(release_in_callback)
 owned.erase(release_in_callback)
func freed_sync(_state: PhysicsDirectBodyState3D) -> void: sync_after_release = true
func run() -> void:
 check(PhysicsServer3D.get_class() == "MjPhysicsServer3D", "native backend identity")
 var space := PhysicsServer3D.space_create(); owned.append(space)
 PhysicsServer3D.space_set_active(space, true)
 check(PhysicsServer3D.call("scene_pause", space, true), "pause isolated space")
 var fixture := FileAccess.open("res://semantics.xml", FileAccess.WRITE)
 fixture.store_string('<mujoco><option timestep=".01" gravity="0 0 -10" integrator="Euler"/><worldbody/></mujoco>'); fixture.close()
 var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
 check(document.import_file("res://semantics.xml"), "empty lightweight authored world")
 check(PhysicsServer3D.call("scene_configure_model", space, document.snapshot(), "res://"), "configure exact .01 second steps")
 var body := make_body(space)
 PhysicsServer3D.body_set_force_integration_callback(body, integrate)
 PhysicsServer3D.body_set_state_sync_callback(body, sync)
 await frames(3)
 check(callbacks == 0 and syncs == 0, "paused bodies do not run integration or sync callbacks")
 PhysicsServer3D.body_apply_central_impulse(body, Vector3(2,4,6))
 near(velocity(body), Vector3(1,2,3), "mass two impulse changes all world axes")
 param(body, PhysicsServer3D.BODY_PARAM_MASS, 4.0)
 PhysicsServer3D.body_apply_central_impulse(body, Vector3(4,-8,0))
 near(velocity(body), Vector3(2,0,3), "mass change affects next impulse")
 set_velocity(body, Vector3.ZERO)
 PhysicsServer3D.body_apply_central_force(body, Vector3(40,80,-120))
 await frames(3)
 near(velocity(body),Vector3.ZERO,"queued force remains unapplied while paused")
 await step(space)
 near(velocity(body), Vector3(.1,.2,-.3), "one-shot force integrates F over mass times dt")
 check(callbacks == 1 and syncs == 1 and abs(callback_step-.01)<1e-7, "single step callbacks once with actual timestep")
 var before := velocity(body)
 await frames(3)
 near(velocity(body), before, "pause retains numerical state")
 check(callbacks == 1 and syncs == 1, "paused ticks do not repeat callbacks")
 await step(space)
 near(velocity(body), before, "one-shot force cleared after simulated step")
 PhysicsServer3D.body_set_constant_force(body, Vector3(40,0,0))
 await step(space, 3)
 near(velocity(body), before+Vector3(.3,0,0), "constant force persists for three substeps")
 check(abs(callback_step-.03)<1e-7, "multi-step callback reports actual simulated span")
 PhysicsServer3D.body_set_constant_force(body, Vector3.ZERO)
 set_velocity(body, Vector3.ZERO)
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 2.0)
 await step(space)
 near(velocity(body), Vector3(0,-.2,0), "gravity scale two physical acceleration")
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, -1.0)
 set_velocity(body, Vector3.ZERO)
 await step(space)
 near(velocity(body), Vector3(0,.1,0), "negative gravity scale reverses acceleration")
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
 param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 5.0)
 param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 4.0)
 set_velocity(body, Vector3(10,0,0), Vector3(0,0,2))
 await step(space, 3)
 near(velocity(body), Vector3(8.5,0,0), "linear damping once per actual integration span")
 near(angular(body), Vector3(0,0,1.76), "angular damping once per actual integration span", .002)
 param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
 param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
 set_velocity(body, Vector3.ZERO)
 PhysicsServer3D.body_apply_torque(body, Vector3(0,0,4.0/6.0))
 await step(space)
 near(angular(body), Vector3(0,0,.01), "torque uses generated box inertia", .0001)
 PhysicsServer3D.body_set_constant_torque(body, Vector3(0,0,4.0/6.0))
 await step(space, 2)
 near(angular(body), Vector3(0,0,.03), "constant torque persists after one-shot torque clears", .0001)
 PhysicsServer3D.body_set_constant_torque(body, Vector3.ZERO)
 # Omission must exclude external forces, torque, gravity and damping together.
 PhysicsServer3D.body_set_omit_force_integration(body, true)
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
 param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 2.0)
 param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 3.0)
 set_velocity(body, Vector3(1,0,0), Vector3(0,0,2))
 PhysicsServer3D.body_apply_central_force(body, Vector3(400,0,0))
 PhysicsServer3D.body_set_constant_force(body, Vector3(400,0,0))
 PhysicsServer3D.body_apply_torque(body, Vector3(0,0,400))
 PhysicsServer3D.body_set_constant_torque(body, Vector3(0,0,400))
 await step(space)
 near(velocity(body), Vector3(1,0,0), "custom integrator omits gravity damping and both force classes")
 near(angular(body), Vector3(0,0,2), "custom integrator omits both torque classes")
 manual = true
 await step(space)
 near(velocity(body), Vector3(.98,-.098,0), "explicit direct integrate applies gravity then damping")
 near(angular(body), Vector3(0,0,1.94), "explicit direct integrate damps angular velocity")
 manual = false
 PhysicsServer3D.body_set_constant_force(body, Vector3.ZERO)
 PhysicsServer3D.body_set_constant_torque(body, Vector3.ZERO)
 PhysicsServer3D.body_set_omit_force_integration(body, false)
 param(body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
 param(body, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.0)
 param(body, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 0.0)
 set_velocity(body, Vector3.ZERO)
 await step(space)
 near(velocity(body), Vector3.ZERO, "omitted one-shot forces are consumed, not replayed on resume")
 near(angular(body), Vector3.ZERO, "omitted one-shot torques are consumed")
 # An asymmetric rotated box with offset COM tests inertia and world-axis lever arm.
 var rotation := Basis(Vector3.FORWARD, PI/2)
 var offset := Vector3(.25,-.1,.3)
 var rotated := make_body(space, 12.0, Vector3(1,2,3), Transform3D(rotation, Vector3(50,2,1)), offset)
 var state := PhysicsServer3D.body_get_direct_state(rotated)
 near(state.center_of_mass, rotation*offset, "center of mass is rotated offset, without world origin")
 near(state.center_of_mass_local, offset, "local COM follows shape offset")
 var impulse := Vector3(3,4,5)
 var lever := Vector3(2,-1,3)
 var torque := lever.cross(impulse)
 var expected_w := Vector3(torque.x/40,torque.y/52,torque.z/20)
 PhysicsServer3D.body_apply_impulse(rotated, impulse, rotation*offset+lever)
 near(velocity(rotated), impulse/12, "offset impulse linear response")
 near(angular(rotated), expected_w, "offset impulse rotated asymmetric inverse inertia")
 var saved_v := velocity(rotated); var saved_w := angular(rotated)
 param(rotated, PhysicsServer3D.BODY_PARAM_FRICTION, .4)
 check(PhysicsServer3D.call("scene_pause", space, true), "rebuild while paused")
 near(velocity(rotated), saved_v, "rebuild preserves linear state")
 near(angular(rotated), saved_w, "rebuild preserves angular state")
 # Compound shapes use a common density: volume 1 at x0, volume 8 at x3.
 var compound := make_body(space, 9, Vector3(.5,.5,.5), Transform3D(Basis.IDENTITY,Vector3(100,0,0)))
 var larger := PhysicsServer3D.box_shape_create(); owned.append(larger)
 PhysicsServer3D.shape_set_data(larger, Vector3.ONE)
 PhysicsServer3D.body_add_shape(compound, larger, Transform3D(Basis.IDENTITY,Vector3(3,0,0)))
 var compound_state := PhysicsServer3D.body_get_direct_state(compound)
 near(compound_state.center_of_mass_local, Vector3(8.0/3,0,0), "compound volume weighted center of mass")
 PhysicsServer3D.body_apply_impulse(compound,Vector3(0,9,0),Vector3(8.0/3,0,0))
 near(velocity(compound),Vector3(0,1,0),"compound COM impulse linear mass response")
 near(angular(compound),Vector3.ZERO,"compound impulse at actual COM has no angular response")
 # Body destruction inside a callback must suppress the later sync callback.
 release_in_callback = make_body(space, 2, Vector3(.5,.5,.5), Transform3D(Basis.IDENTITY, Vector3(80,0,0)))
 PhysicsServer3D.body_set_force_integration_callback(release_in_callback, free_callback)
 PhysicsServer3D.body_set_state_sync_callback(release_in_callback, freed_sync)
 await step(space)
 check(released_callback and not sync_after_release, "free inside integration callback suppresses sync and remains safe")
 var count_before := callbacks
 PhysicsServer3D.body_set_space(body, RID())
 await step(space)
 check(callbacks == count_before, "detached body has no callback")
 PhysicsServer3D.body_set_space(body, space)
 await step(space)
 check(callbacks == count_before+1, "readded body resumes exactly one callback")
 # Paused reset synchronizes state without running user force integration.
 await command(space, "capture")
 var captured_pose: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
 set_velocity(body, Vector3(1,0,0))
 await step(space, 2)
 check((PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin.distance_to(captured_pose.origin)>.01, "body moves after checkpoint")
 var integrations_before_reset := callbacks
 var syncs_before_reset := syncs
 await command(space, "reset")
 near((PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin, captured_pose.origin, "paused reset restores body pose")
 check(callbacks == integrations_before_reset and syncs == syncs_before_reset+1, "paused reset delivers sync only, no force callback")
 # Native PhysicsMaterial combination is abs(min(signed friction)).
 var sliders: Array[RID] = []
 var pairs := [[.1,.8],[.7,.8],[-.7,.1],[.1,-.8]]
 for i in pairs.size():
  var floor_body := make_body(space, 1, Vector3(10,.5,4), Transform3D(Basis.IDENTITY, Vector3(200+i*30,-.5,0)))
  PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
  param(floor_body, PhysicsServer3D.BODY_PARAM_FRICTION, pairs[i][1])
  var slider := make_body(space, 2, Vector3(.5,.5,.5), Transform3D(Basis.IDENTITY, Vector3(200+i*30,.51,0)))
  param(slider, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 1.0)
  param(slider, PhysicsServer3D.BODY_PARAM_FRICTION, pairs[i][0])
  sliders.append(slider)
 await step(space, 30)
 for slider in sliders: set_velocity(slider, Vector3(5,0,0))
 await step(space, 100)
 check(velocity(sliders[0]).x>3.0, "normal friction uses lower coefficient", velocity(sliders[0]))
 check(abs(velocity(sliders[1]).x)<1.0, "larger minimum friction physically brakes slider", velocity(sliders[1]))
 check(abs(velocity(sliders[2]).x)<1.0, "rough slider overrides low floor friction", velocity(sliders[2]))
 check(abs(velocity(sliders[3]).x)<1.0, "rough floor overrides low slider friction", velocity(sliders[3]))
 # Ordinary Godot space: internal MuJoCo subdivisions must not multiply damping.
 var ordinary_space := PhysicsServer3D.space_create(); owned.append(ordinary_space)
 PhysicsServer3D.space_set_active(ordinary_space,true)
 check(PhysicsServer3D.call("scene_pause",ordinary_space,true), "ordinary space paused for setup")
 var ordinary_body := make_body(ordinary_space)
 param(ordinary_body,PhysicsServer3D.BODY_PARAM_LINEAR_DAMP,5.0)
 set_velocity(ordinary_body,Vector3(10,0,0))
 check(PhysicsServer3D.call("scene_pause",ordinary_space,false), "ordinary space resumed")
 await frames(4)
 check(PhysicsServer3D.call("scene_pause",ordinary_space,true), "ordinary space paused after ticks")
 var elapsed: float = PhysicsServer3D.call("scene_info",ordinary_space).time
 var dt := 1.0/Engine.physics_ticks_per_second
 var tick_count := roundi(elapsed/dt)
 check(tick_count>0 and abs(elapsed-tick_count*dt)<.000001,"ordinary elapsed time is whole Godot ticks",elapsed)
 near(velocity(ordinary_body),Vector3(10*pow(1-5*dt,tick_count),0,0),"ordinary damping once per Godot tick despite MuJoCo subdivisions",.0001)
 param(ordinary_body,PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,PhysicsServer3D.BODY_DAMP_MODE_COMBINE)
 PhysicsServer3D.area_set_param(ordinary_space,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP,2.0)
 set_velocity(ordinary_body,Vector3(10,0,0))
 check(PhysicsServer3D.call("scene_pause",ordinary_space,false),"resume combine damping")
 await frames(4)
 check(PhysicsServer3D.call("scene_pause",ordinary_space,true),"pause combine damping")
 var combined_elapsed: float = PhysicsServer3D.call("scene_info",ordinary_space).time-elapsed
 tick_count = roundi(combined_elapsed/dt)
 near(velocity(ordinary_body),Vector3(10*pow(1-7*dt,tick_count),0,0),"combine damping includes space and body coefficients",.0001)
 # Free bodies/shapes before their space; no stale references survive shutdown.
 owned.reverse()
 for rid in owned: PhysicsServer3D.free_rid(rid)
 owned.clear()
 await frames(2)
 var failed := checks.filter(func(item): return not item.passed).size()
 var report := {"passed": checks.size()-failed, "failed": failed, "checks": checks, "backend": PhysicsServer3D.get_class(), "godot": Engine.get_version_info().string}
 print("NATIVE_SEMANTICS_RESULT ", JSON.stringify(report))
 quit(0 if failed==0 else 1)
