extends "res://acceptance.gd"
func rejected(label:String,action:Callable):
 print("EXPECT_DRIVE_REJECTION ",label);action.call()
func run():
 setup()
 var a=body(Vector3.ZERO);var j=hinge(a,Transform3D.IDENTITY);motor(j,1,.01)
 var before=pose(a);var initial_velocity=angular(a)
 for pair in [[PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY,NAN],[PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY,101.0],[PhysicsServer3D.HINGE_JOINT_MOTOR_TARGET_VELOCITY,-101.0],[PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,-1.0],[PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,1001.0],[PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,-3.1],[PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,3.1],[PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,2.0]]:
  var parameter:int=pair[0];var value:float=pair[1];var old=PhysicsServer3D.hinge_joint_get_param(j,parameter)
  rejected("parameter %s value %s"%[parameter,value],func():hp(j,parameter,value))
  check(PhysicsServer3D.hinge_joint_get_param(j,parameter)==old,"invalid finite/range update retains accepted parameter")
 check(pose(a).is_equal_approx(before) and angular(a)==initial_velocity,"rejected parameters do not alter paused state")
 var peer=body(Vector3(3,0,0));var extra=PhysicsServer3D.joint_create();joints.append(extra)
 rejected("extra native joint on driven endpoint",func():PhysicsServer3D.joint_make_pin(extra,a,Vector3(3,0,0),peer,Vector3.ZERO))
 check(PhysicsServer3D.joint_get_type(extra)==PhysicsServer3D.JOINT_TYPE_MAX and PhysicsServer3D.hinge_joint_get_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"driven endpoint graph violation leaves old motor and graph intact")
 await step(30);check(angular(a).z>.4,"old accepted motor still acts after rejected graph change",angular(a))
 var anti_body=body(Vector3(6,0,0));var anti=hinge(anti_body,Transform3D.IDENTITY,RID(),Transform3D(Basis(Vector3.UP,PI),Vector3(6,0,0)))
 rejected("antiparallel active axis unsupported",func():PhysicsServer3D.hinge_joint_set_flag(anti,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,true))
 check(PhysicsServer3D.joint_get_type(anti)==PhysicsServer3D.JOINT_TYPE_HINGE and not PhysicsServer3D.hinge_joint_get_flag(anti,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR),"antiparallel activation rejection retains passive hinge")
 await finish("HINGE_DRIVE_NEGATIVE_RESULT")
