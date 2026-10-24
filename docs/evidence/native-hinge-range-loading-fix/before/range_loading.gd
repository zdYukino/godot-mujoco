extends "res://acceptance.gd"
func pair(j:RID)->Vector2:return Vector2(PhysicsServer3D.hinge_joint_get_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER),PhysicsServer3D.hinge_joint_get_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER))
func set_range(j:RID,bounds:Vector2,upper_first:bool):
 if upper_first:
  hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,bounds.y);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,bounds.x)
 else:
  hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,bounds.x);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,bounds.y)
func physical_bounds(a:RID,j:RID,bounds:Vector2):
 # Use a safe simulation starting angle to isolate range loading from the
 # independently tested large-error angular-step guard.
 var current=pose(a);current.basis=Basis(Vector3.BACK,(bounds.x+bounds.y)*.5)
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_TRANSFORM,current)
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,Vector3.ZERO)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 motor(j,1,.05);await step(80)
 check(abs(angle(a)-bounds.y)<.04,"loaded upper bound physically stops positive motor",[bounds,angle(a)])
 motor(j,-1,.05);await step(80)
 check(abs(angle(a)-bounds.x)<.04,"loaded lower bound physically stops reverse motor",[bounds,angle(a)])
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,false)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,false)
func run():
 if "--negative" in OS.get_cmdline_user_args():await run_negative();return
 setup()
 var serial:=0
 for bounds in [Vector2(-2.5,-2),Vector2(2,2.6),Vector2(-.7,-.2),Vector2(.2,.9)]:
  for upper_first in [true,false]:
   var a=body(Vector3(serial*4,0,0));serial+=1
   var j=hinge(a,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,pose(a).origin))
   set_range(j,bounds,upper_first)
   check(pair(j).is_equal_approx(bounds),"inactive two-setter order preserves full same-sign pair",[bounds,upper_first,pair(j)])
   await physical_bounds(a,j,bounds)
 # Godot _configure_joint loads params in its own order, independent of authoring order.
 for bounds in [Vector2(-2.5,-2),Vector2(2,2.6)]:
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
  viewport.queue_free();await ticks(3);space=previous_space
 await finish("HINGE_RANGE_LOADING_RESULT")
func run_negative():
 setup()
 var a=body(Vector3.ZERO);var j=hinge(a,Transform3D.IDENTITY)
 set_range(j,Vector2(-.4,.5),true)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 var stable=pair(j)
 print("EXPECT_RANGE_ERROR active inversion")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,-.8)
 check(pair(j)==stable and PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT),"active inverted update preserves accepted range and flag")
 print("EXPECT_RANGE_ERROR nonfinite")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,NAN)
 check(pair(j)==stable,"nonfinite update preserves pair")
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,false)
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,-.8) # Inactive pending incomplete range.
 print("EXPECT_RANGE_ERROR incomplete activation")
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 check(not PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT) and pair(j)==stable,"incomplete pending range refuses activation without replacing accepted pair")
 await finish("HINGE_RANGE_NEGATIVE_RESULT")
