extends "res://pin_support.gd"
func body(at:Vector3,mode:int=PhysicsServer3D.BODY_MODE_RIGID)->RID:
 var id=super.body(at,mode)
 PhysicsServer3D.body_set_param(id,PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,0.0)
 return id
func angular(id:RID)->Vector3:return PhysicsServer3D.body_get_state(id,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)
func hinge(a:RID,fa:Transform3D,b:RID=RID(),fb:Transform3D=Transform3D.IDENTITY)->RID:
 var id=PhysicsServer3D.joint_create();joints.append(id)
 PhysicsServer3D.joint_make_hinge(id,a,fa,b,fb)
 check(PhysicsServer3D.joint_get_type(id)==PhysicsServer3D.JOINT_TYPE_HINGE,"passive hinge actual type")
 return id
func frame(axis:Vector3,anchor:Vector3)->Transform3D:
 return Transform3D(Basis(Quaternion(Vector3.BACK,axis.normalized())),anchor)
func run():
 setup()
 var a=body(Vector3.ZERO);var joint=hinge(a,Transform3D.IDENTITY)
 var defaults=[.3,PI/2,-PI/2,.3,.9,1.0,1.0,1.0]
 for parameter in defaults.size():
  PhysicsServer3D.hinge_joint_set_param(joint,parameter,defaults[parameter])
  check(abs(PhysicsServer3D.hinge_joint_get_param(joint,parameter)-defaults[parameter])<.000001,"hinge initialization compatibility default %s"%parameter)
 PhysicsServer3D.body_apply_torque_impulse(a,Vector3(0,0,.032));await step(40)
 check(abs(angular(a).z)>1.5,"world hinge retains axial spin",angular(a))
 check(abs(pose(a).basis.get_euler().z)>.3,"axial spin changes actual body orientation",pose(a))
 check(pose(a).origin.length()<.03 and pose(a).basis.z.dot(Vector3.BACK)>.999,"world hinge position and axis remain constrained")
 PhysicsServer3D.body_apply_torque_impulse(a,Vector3(.032,.032,0));await step(30)
 check(Vector2(angular(a).x,angular(a).y).length()<.05,"transverse angular motion is suppressed",angular(a))
 check(abs(angular(a).z)>1 and pose(a).basis.z.dot(Vector3.BACK)>.999,"transverse constraint preserves free axial degree")
 var old_pose=pose(a);var old_v=velocity(a);var old_w=angular(a)
 PhysicsServer3D.body_set_param(a,PhysicsServer3D.BODY_PARAM_FRICTION,.4);PhysicsServer3D.call("scene_pause",space,true)
 check(pose(a).is_equal_approx(old_pose) and velocity(a).distance_to(old_v)<.00001 and angular(a).distance_to(old_w)<.00001,"hinge rebuild preserves pose and both velocities")
 await ticks(3);check(pose(a).is_equal_approx(old_pose),"paused hinge keeps state fixed")
 var axis=Vector3(1,2,3).normalized();var rotated=body(Vector3(4,0,0));var rotated_joint=hinge(rotated,frame(axis,Vector3.ZERO),RID(),frame(-axis,Vector3(4,0,0)))
 PhysicsServer3D.body_apply_torque_impulse(rotated,axis*.032);await step(40)
 check(angular(rotated).dot(axis)>1.5 and angular(rotated).cross(axis).length()<.05,"rotated and antiparallel frame axes retain intended axial spin",angular(rotated))
 check(pose(rotated).origin.distance_to(Vector3(4,0,0))<.03,"rotated world hinge anchor stays fixed")
 var offset=body(Vector3(8,-1,0));var offset_joint=hinge(offset,Transform3D(Basis.IDENTITY,Vector3.UP),RID(),Transform3D(Basis.IDENTITY,Vector3(8,0,0)))
 PhysicsServer3D.body_apply_central_impulse(offset,Vector3.RIGHT);await step(50)
 check((pose(offset)*Vector3.UP).distance_to(Vector3(8,0,0))<.03,"offset local frame anchor remains constrained")
 check(abs(pose(offset).origin.x-8)>.05 and pose(offset).basis.z.dot(Vector3.BACK)>.999,"offset frame allows rotation around hinge axis")
 var first=body(Vector3(12,0,0));var second=body(Vector3(12,-1,0));var pair=hinge(first,Transform3D(Basis.IDENTITY,Vector3.DOWN*.5),second,Transform3D(Basis.IDENTITY,Vector3.UP*.5))
 PhysicsServer3D.body_apply_central_impulse(second,Vector3.RIGHT);PhysicsServer3D.body_apply_torque_impulse(second,Vector3(0,0,.016));await step(40)
 check((pose(first)*(Vector3.DOWN*.5)).distance_to(pose(second)*(Vector3.UP*.5))<.03,"two dynamic hinge anchors coincide")
 check((pose(first).basis.z).dot(pose(second).basis.z)>.999,"two dynamic hinge axes remain aligned")
 check(abs((pose(first).basis.inverse()*pose(second).basis).get_euler().z)>.05,"two dynamic hinge retains relative axial rotation")
 PhysicsServer3D.joint_clear(joint);PhysicsServer3D.body_apply_central_impulse(a,Vector3.RIGHT)
 var start=pose(a).origin;await step(30);check(pose(a).origin.distance_to(start)>.1,"cleared hinge releases translation")
 PhysicsServer3D.joint_make_hinge(joint,a,Transform3D.IDENTITY,RID(),pose(a));await step(20)
 check(PhysicsServer3D.joint_get_type(joint)==PhysicsServer3D.JOINT_TYPE_HINGE,"cleared hinge RID reused")
 PhysicsServer3D.free_rid(second);resources.erase(second)
 check(PhysicsServer3D.joint_get_type(pair)==PhysicsServer3D.JOINT_TYPE_MAX,"endpoint deletion clears hinge")
 # Actual HingeJoint3D scene save/reopen, with passive defaults only.
 var design=Node3D.new();design.name="SavedHingeRoot"
 var bob=RigidBody3D.new();bob.name="Bob";bob.position=Vector3(0,-1,0);design.add_child(bob);bob.owner=design
 var shape=CollisionShape3D.new();shape.shape=SphereShape3D.new();shape.shape.radius=.2;bob.add_child(shape);shape.owner=design
 var node=HingeJoint3D.new();node.name="Hinge";node.node_a=NodePath("../Bob");design.add_child(node);node.owner=design
 var packed=PackedScene.new();check(packed.pack(design)==OK and ResourceSaver.save(packed,"res://SavedHinge.tscn")==OK,"save real HingeJoint3D scene")
 design.free()
 var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
 var previous_space=space;space=viewport.find_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");doc.import_file("res://world.xml")
 check(PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure reopened hinge world")
 var reopened=load("res://SavedHinge.tscn").instantiate();viewport.add_child(reopened);await ticks(2)
 bob=reopened.get_node("Bob");node=reopened.get_node("Hinge")
 check(node.node_a==NodePath("../Bob") and PhysicsServer3D.joint_get_type(node.get_rid())==PhysicsServer3D.JOINT_TYPE_HINGE,"reopened node path creates real hinge")
 bob.apply_central_impulse(Vector3.RIGHT);await step(50)
 check((bob.global_transform*Vector3.UP).length()<.03 and abs(bob.position.x)>.05 and bob.basis.z.dot(Vector3.BACK)>.999,"reopened hinge swings while preserving anchor and axis")
 viewport.queue_free();await ticks(3);space=previous_space
 await finish("HINGE_RESULT")
