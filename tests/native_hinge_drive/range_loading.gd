extends "res://acceptance.gd"
func pair(j:RID)->Vector2:return Vector2(PhysicsServer3D.hinge_joint_get_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER),PhysicsServer3D.hinge_joint_get_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER))
func set_range(j:RID,bounds:Vector2,upper_first:bool):
 if upper_first:
  hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,bounds.y);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,bounds.x)
 else:
  hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,bounds.x);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,bounds.y)
func physical_bounds(a:RID,j:RID,bounds:Vector2):
 # Node configuration derives its frame at the current pose; compare relative
 # motion from that configured reference, including after exit/reentry.
 var reference_angle=angle(a)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 motor(j,1,.05);await step(80)
 check(abs(wrapf(angle(a)-reference_angle,-PI,PI)-bounds.y)<.04,"loaded upper bound physically stops positive motor",[bounds,angle(a)])
 motor(j,-1,.05);await step(80)
 check(abs(wrapf(angle(a)-reference_angle,-PI,PI)-bounds.x)<.04,"loaded lower bound physically stops reverse motor",[bounds,angle(a)])
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,false)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,false)
func run():
 if "--negative" in OS.get_cmdline_user_args():await run_negative();return
 setup()
 var serial:=0
 for bounds in [Vector2(-2.5,-2),Vector2(-2,-2),Vector2(2,2.5),Vector2(2,2)]:
  for upper_first in [true,false]:
   var a=body(Vector3(serial*4,0,0));serial+=1
   var j=hinge(a,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,pose(a).origin))
   set_range(j,bounds,upper_first)
   check(pair(j).is_equal_approx(bounds),"inactive two-setter order preserves full same-sign pair",[bounds,upper_first,pair(j)])
   await physical_bounds(a,j,bounds)
 # Godot _configure_joint loads params in its own order, independent of authoring order.
 for bounds in [Vector2(-2.5,-2),Vector2(-2,-2),Vector2(2,2.5),Vector2(2,2)]:
  var design=Node3D.new();design.name="RangeScene"
  var bob=RigidBody3D.new();bob.name="Bob";bob.gravity_scale=0;design.add_child(bob);bob.owner=design
  var collision=CollisionShape3D.new();collision.shape=SphereShape3D.new();collision.shape.radius=.2;bob.add_child(collision);collision.owner=design
  var node=HingeJoint3D.new();node.name="Hinge";node.node_a=NodePath("../Bob")
  node.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,bounds.x);node.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,bounds.y)
  node.set_flag(HingeJoint3D.FLAG_USE_LIMIT,true);design.add_child(node);node.owner=design
  var path="res://Range_%d.tscn"%serial;serial+=1
  var packed=PackedScene.new();check(packed.pack(design)==OK and ResourceSaver.save(packed,path)==OK,"save same-sign range scene");design.free()
  var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
  var previous_space=space;space=viewport.find_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
  var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");doc.import_file("res://world.xml")
  check(PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure paused range reload world")
  var reopened=load(path).instantiate();viewport.add_child(reopened);await ticks(2)
  bob=reopened.get_node("Bob");node=reopened.get_node("Hinge")
  check(pair(node.get_rid()).is_equal_approx(bounds),"saved scene native pair exactly matches both authored limits",[bounds,pair(node.get_rid())])
  check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT),"saved enabled limit restored")
  await physical_bounds(bob.get_rid(),node.get_rid(),bounds)
  check(Vector2(node.get_param(HingeJoint3D.PARAM_LIMIT_LOWER),node.get_param(HingeJoint3D.PARAM_LIMIT_UPPER)).is_equal_approx(pair(node.get_rid())),"reopened node cache and native pair agree")
  bob.collision_layer=0;bob.collision_mask=0
  var replacement=RigidBody3D.new();replacement.name="Replacement";replacement.gravity_scale=0;replacement.collision_layer=0;replacement.collision_mask=0
  var replacement_shape=CollisionShape3D.new();replacement_shape.shape=SphereShape3D.new();replacement_shape.shape.radius=.2;replacement.add_child(replacement_shape);reopened.add_child(replacement)
  PhysicsServer3D.hinge_joint_set_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
  PhysicsServer3D.hinge_joint_set_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,true)
  check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT) and PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"endpoint replacement begins with genuinely active native drive")
  node.node_a=NodePath("../Replacement");await ticks(2)
  check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR)==node.get_flag(HingeJoint3D.FLAG_ENABLE_MOTOR) and PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT)==node.get_flag(HingeJoint3D.FLAG_USE_LIMIT),"active endpoint replacement reloads node flags without inherited old drive")
  check(pair(node.get_rid()).is_equal_approx(bounds),"changing endpoint reloads complete node range")
  await physical_bounds(replacement.get_rid(),node.get_rid(),bounds)
  PhysicsServer3D.hinge_joint_set_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
  PhysicsServer3D.hinge_joint_set_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,true)
  check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT) and PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"scene exit begins with genuinely active native drive")
  viewport.remove_child(reopened);await ticks(2);viewport.add_child(reopened);await ticks(2)
  check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR)==node.get_flag(HingeJoint3D.FLAG_ENABLE_MOTOR) and PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT)==node.get_flag(HingeJoint3D.FLAG_USE_LIMIT),"active scene reentry reloads node flags")
  check(pair(node.get_rid()).is_equal_approx(bounds),"exit and reentry reloads complete node range")
  await physical_bounds(replacement.get_rid(),node.get_rid(),bounds)
  viewport.queue_free();await ticks(3);space=previous_space
 await finish("HINGE_RANGE_LOADING_RESULT")
func run_negative():
 setup()
 var a=body(Vector3.ZERO);var j=hinge(a,Transform3D.IDENTITY)
 set_range(j,Vector2(-.4,.5),true)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis(Vector3.BACK,.1),Vector3.ZERO))
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,Vector3(0,0,.2))
 var stable_pose=pose(a);var stable_angular=angular(a);var stable_info:Dictionary=PhysicsServer3D.call("scene_info",space)
 var stable=pair(j)
 print("EXPECT_RANGE_ERROR active inversion")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,-.8)
 check(pair(j)==stable and PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT),"active inverted update preserves accepted range and flag")
 print("EXPECT_RANGE_ERROR nonfinite")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,NAN)
 check(pair(j)==stable,"nonfinite update preserves pair")
 var current_info:Dictionary=PhysicsServer3D.call("scene_info",space)
 check(pose(a).is_equal_approx(stable_pose) and angular(a)==stable_angular and current_info.time==stable_info.time and current_info.paused==stable_info.paused,"active invalid updates preserve nonzero physical state and pause/time")
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,false)
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,-.8) # Inactive pending incomplete range.
 print("EXPECT_RANGE_ERROR incomplete activation")
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 check(not PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT) and pair(j)==stable,"incomplete pending range refuses activation without replacing accepted pair")
 for flag in [PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR]:
  print("EXPECT_RANGE_ERROR repeated incomplete activation")
  PhysicsServer3D.hinge_joint_set_flag(j,flag,true)
  check(not PhysicsServer3D.hinge_joint_get_flag(j,flag) and pair(j)==stable,"repeated activation cannot bypass unresolved pending range")
 print("EXPECT_RANGE_ERROR scalar out of range")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,-3.1)
 check(pair(j)==stable,"invalid scalar cannot replace accepted or pending range")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,-1)
 check(pair(j).is_equal_approx(Vector2(-1,-.8)),"correcting pending other endpoint commits valid pair")
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 check(PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT),"corrected pending range can enable normally")
 var accepted_pair=pair(j);var accepted_pose=pose(a);var accepted_velocity=angular(a)
 var accepted_info:Dictionary=PhysicsServer3D.call("scene_info",space)
 print("EXPECT_RANGE_ERROR candidate dynamics rollback")
 PhysicsServer3D.joint_make_hinge(j,a,Transform3D(Basis.IDENTITY,Vector3(1e20,0,0)),RID(),Transform3D.IDENTITY)
 check(pair(j)==accepted_pair and PhysicsServer3D.joint_get_type(j)==PhysicsServer3D.JOINT_TYPE_HINGE and PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT),"failed replacement candidate retains accepted range type and active flag")
 var rejected_info:Dictionary=PhysicsServer3D.call("scene_info",space)
 check(pose(a).is_equal_approx(accepted_pose) and angular(a)==accepted_velocity and rejected_info.time==accepted_info.time and rejected_info.paused==accepted_info.paused,"failed replacement candidate retains physics state pause and time")
 await finish("HINGE_RANGE_NEGATIVE_RESULT")
