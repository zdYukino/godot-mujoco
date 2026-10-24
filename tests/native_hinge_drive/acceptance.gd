extends "res://hinge_support.gd"
var drive_callback_stage:=0
func hp(j:RID,p:int,v:float):PhysicsServer3D.hinge_joint_set_param(j,p,v)
func motor(j:RID,target:float,budget:float):
 hp(j,PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY,target)
 hp(j,PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,budget)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,true)
func angle(a:RID,b:RID=RID())->float:
 var relative=pose(b).basis.inverse()*pose(a).basis if b.is_valid() else pose(a).basis
 return atan2(relative.x.y,relative.x.x)
func world_command(action:String):
 var request:int=PhysicsServer3D.call("scene_request_world_command",space,action,1)
 var result:Dictionary={}
 for i in 30:
  await ticks();result=PhysicsServer3D.call("scene_world_command_result",request)
  if not result.is_empty():break
 check(result.get("success",false),"world command "+action,result);await ticks()
func run():
 setup()
 # Analytic budget: unit sphere radius .2 has Iz=.016 kg m^2.
 var speeds:Array[float]=[]
 for n in [1,10]:
  var sphere=body(Vector3(10*n,0,0))
  var j=hinge(sphere,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,pose(sphere).origin))
  motor(j,100,.001)
  await step(n)
  speeds.append(angular(sphere).z)
  check(abs(angular(sphere).z-.0625)<.002,"motor impulse budget is per actual span with %d substeps"%n,angular(sphere))
  PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,false)
 check(abs(speeds[0]-speeds[1])<.002,"subdividing a span does not multiply motor impulse")
 var zero_body=body(Vector3(15,0,0));var zero_joint=hinge(zero_body,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,Vector3(15,0,0)))
 motor(zero_joint,2,0);await step(20)
 check(angular(zero_body).length()<.0001,"zero impulse budget does not secretly drive body")
 var a=body(Vector3.ZERO);var j=hinge(a,Transform3D.IDENTITY)
 motor(j,2,.1);await step(50)
 check(abs(angular(a).z-2)<.05 and angle(a)>.5,"positive radian target reaches actual speed and angle",angular(a))
 motor(j,-2,.1);await step(50)
 check(abs(angular(a).z+2)<.05,"negative target reverses actual angular velocity",angular(a))
 # Limit and motor act simultaneously; Godot frame-Z sign sets A relative to B.
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,-.3);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,.4)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 motor(j,2,.1);await step(100)
 check(abs(angle(a)-.4)<.04,"positive drive reaches upper angle bound",angle(a))
 motor(j,-2,.1);await step(100)
 check(abs(angle(a)+.3)<.04,"reverse drive reaches lower angle bound",angle(a))
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,false)
 PhysicsServer3D.body_set_constant_torque(a,Vector3(0,0,-.02));await step(100)
 check(angle(a)>=-.34 and angle(a)<=.44,"limit resists external torque with motor off",angle(a))
 PhysicsServer3D.body_set_constant_torque(a,Vector3.ZERO)
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,0);hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,0)
 await step(100);check(abs(angle(a))<.04,"equal limits lock angle",angle(a))
 await world_command("capture")
 hp(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,.6);motor(j,1,.02)
 var frozen=pose(a);await ticks(4);check(pose(a).is_equal_approx(frozen),"paused drive updates do not advance state")
 await step(30);await world_command("reset")
 check(PhysicsServer3D.hinge_joint_get_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER)>.59 and PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"checkpoint reset preserves newer joint design")
 # Two independent moving bodies: internal motor reaction conserves angular momentum.
 var b=body(Vector3(5,0,0));var c=body(Vector3(5,0,0));PhysicsServer3D.body_set_param(c,PhysicsServer3D.BODY_PARAM_MASS,2.0);var pair=hinge(b,Transform3D.IDENTITY,c,Transform3D.IDENTITY)
 motor(pair,100,.001);await step(10)
 check(abs(angular(b).z-.0625)<.003 and abs(angular(c).z+.03125)<.003,"unequal-mass two-body motor delivers equal opposite impulse",[angular(b),angular(c)])
 check(abs(.016*angular(b).z+.032*angular(c).z)<.00002,"unequal-mass weighted angular momentum conserved")
 # True eccentric anchor: sphere COM is one metre from the world hinge axis.
 var eccentric=body(Vector3(40,-1,0));var eccentric_joint=hinge(eccentric,Transform3D(Basis.IDENTITY,Vector3.UP),RID(),Transform3D(Basis.IDENTITY,Vector3(40,0,0)))
 motor(eccentric_joint,100,.001);await step(1)
 var expected_eccentric=.001/(.016+1.0)
 check(abs(angular(eccentric).z-expected_eccentric)<.00003,"eccentric anchor uses parallel-axis inertia not COM inertia",angular(eccentric))
 check(abs(velocity(eccentric).x-expected_eccentric)<.00003,"eccentric motor induces matching COM tangential velocity",velocity(eccentric))
 check((pose(eccentric)*Vector3.UP).distance_to(Vector3(40,0,0))<.0005,"eccentric driven anchor remains constrained")
 PhysicsServer3D.hinge_joint_set_flag(eccentric_joint,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,false)
 # Separate driven pairs: callback parameter changes apply next span, then clear.
 var callback_body=body(Vector3(50,0,0));var callback_joint=hinge(callback_body,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,Vector3(50,0,0)))
 var independent_body=body(Vector3(55,0,0));var independent_joint=hinge(independent_body,Transform3D.IDENTITY,RID(),Transform3D(Basis.IDENTITY,Vector3(55,0,0)))
 motor(callback_joint,1,.001);motor(independent_joint,-2,.001)
 PhysicsServer3D.body_set_force_integration_callback(callback_body,func(_state):
  if drive_callback_stage==0:
   drive_callback_stage=1
   hp(callback_joint,PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY,-3)
   hp(callback_joint,PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,.002)
  elif drive_callback_stage==1:
   drive_callback_stage=2
   hp(callback_joint,PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,.004)
   PhysicsServer3D.joint_clear(callback_joint))
 await step(1)
 check(drive_callback_stage==1 and abs(angular(callback_body).z-.0625)<.002,"callback update does not retroactively change completed span")
 check(PhysicsServer3D.hinge_joint_get_param(callback_joint,PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY)==-3 and PhysicsServer3D.hinge_joint_get_param(independent_joint,PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY)==-2,"callback target update isolated from second pair")
 check(abs(angular(independent_body).z+.0625)<.002,"second pair keeps independent first-span physical response")
 await step(1)
 check(drive_callback_stage==2 and abs(angular(callback_body).z+.0625)<.002,"next span consumes callback-updated target and impulse budget")
 check(PhysicsServer3D.joint_get_type(callback_joint)==PhysicsServer3D.JOINT_TYPE_MAX and PhysicsServer3D.hinge_joint_get_flag(independent_joint,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"same-callback parameter update then clear removes only its own pair")
 await step(1)
 check(abs(angular(callback_body).z+.0625)<.002 and abs(angular(independent_body).z+.1875)<.003,"cleared body stays free while independent motor continues")
 # Rotated asymmetric inertia with anchor at an offset COM.
 var shape=PhysicsServer3D.box_shape_create();resources.append(shape);PhysicsServer3D.shape_set_data(shape,Vector3(1,.5,.25))
 var custom=PhysicsServer3D.body_create();resources.append(custom)
 PhysicsServer3D.body_add_shape(custom,shape,Transform3D(Basis.IDENTITY,Vector3(.2,0,0)))
 PhysicsServer3D.body_set_param(custom,PhysicsServer3D.BODY_PARAM_MASS,2.0)
 PhysicsServer3D.body_set_param(custom,PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,0.0)
 PhysicsServer3D.body_set_param(custom,PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,1)
 PhysicsServer3D.body_set_param(custom,PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,1)
 var basis=Basis(Vector3(1,2,3).normalized(),.7);var origin=Vector3(20,0,0)
 PhysicsServer3D.body_set_state(custom,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(basis,origin));PhysicsServer3D.body_set_space(custom,space)
 var static_body=body(Vector3(20,2,0),PhysicsServer3D.BODY_MODE_STATIC)
 var anchor=origin+basis*Vector3(.2,0,0)
 var rotated=hinge(custom,Transform3D(Basis.IDENTITY,Vector3(.2,0,0)),static_body,Transform3D(basis,anchor-pose(static_body).origin))
 motor(rotated,100,.001);await step(10)
 check(abs(angular(custom).dot(basis.z)-.001/(2.0*(4+1)/12))<.0002,"rotated frame offset COM asymmetric inertia motor response",angular(custom))
 check((pose(custom)*Vector3(.2,0,0)).distance_to(anchor)<.02,"static endpoint holds offset COM anchor")
 PhysicsServer3D.joint_clear(rotated);PhysicsServer3D.body_apply_torque_impulse(custom,basis.x*.001);await step(10)
 check(abs(angular(custom).dot(basis.x))>.001,"clear driven hinge releases transverse rotation")
 var phased_body=body(Vector3(30,0,0));var phased=hinge(phased_body,Transform3D(Basis(Vector3.BACK,.3),Vector3.ZERO),RID(),Transform3D(Basis.IDENTITY,Vector3(30,0,0)))
 hp(phased,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,0);hp(phased,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,0)
 PhysicsServer3D.hinge_joint_set_flag(phased,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true);await step(80)
 check(abs(angle(phased_body)+.3)<.04,"limit angle includes relative frame phase",angle(phased_body))
 var design=Node3D.new();design.name="DriveDesign"
 var bob=RigidBody3D.new();bob.name="Bob";bob.gravity_scale=0;design.add_child(bob);bob.owner=design
 var collision=CollisionShape3D.new();collision.shape=SphereShape3D.new();collision.shape.radius=.2;bob.add_child(collision);collision.owner=design
 var node=HingeJoint3D.new();node.name="DrivenHinge";node.node_a=NodePath("../Bob")
 node.set_param(HingeJoint3D.PARAM_LIMIT_LOWER,-.8);node.set_param(HingeJoint3D.PARAM_LIMIT_UPPER,.8)
 node.set_param(HingeJoint3D.PARAM_MOTOR_TARGET_VELOCITY,1.5);node.set_param(HingeJoint3D.PARAM_MOTOR_MAX_IMPULSE,.1)
 node.set_flag(HingeJoint3D.FLAG_USE_LIMIT,true);node.set_flag(HingeJoint3D.FLAG_ENABLE_MOTOR,true)
 design.add_child(node);node.owner=design
 var packed=PackedScene.new();check(packed.pack(design)==OK and ResourceSaver.save(packed,"res://SavedDrivenHinge.tscn")==OK,"save actual driven HingeJoint3D design")
 design.free()
 var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
 var previous_space=space;space=viewport.find_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");doc.import_file("res://world.xml")
 check(PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure saved drive world")
 var reopened=load("res://SavedDrivenHinge.tscn").instantiate();viewport.add_child(reopened);await ticks(2)
 bob=reopened.get_node("Bob");node=reopened.get_node("DrivenHinge")
 check(PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT) and PhysicsServer3D.hinge_joint_get_flag(node.get_rid(),PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"reopened native flags match saved design")
 await step(50)
 check(abs(bob.angular_velocity.z-1.5)<.05 and bob.basis.get_euler().z>.4,"reopened motor reaches saved physical target velocity",bob.angular_velocity)
 viewport.queue_free();await ticks(3);space=previous_space
 await finish("HINGE_DRIVE_RESULT")
