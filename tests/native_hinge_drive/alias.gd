extends "res://pin_support.gd"
var callbacks:=0
func result_for(id:int)->Dictionary:
 for i in 30:
  await ticks()
  var result:Dictionary=PhysicsServer3D.call("scene_world_command_result",id)
  if not result.is_empty():return result
 return {}
func run():
 setup()
 var a:=body(Vector3.ZERO)
 PhysicsServer3D.body_set_param(a,PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,0.0)
 PhysicsServer3D.body_set_force_integration_callback(a,func(_state):callbacks+=1)
 var j:=PhysicsServer3D.joint_create();joints.append(j)
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis(Vector3.BACK,2.99),Vector3.ZERO))
 PhysicsServer3D.joint_make_hinge(j,a,Transform3D.IDENTITY,RID(),Transform3D.IDENTITY)
 PhysicsServer3D.hinge_joint_set_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_LOWER,-3.0)
 PhysicsServer3D.hinge_joint_set_param(j,PhysicsServer3D.HINGE_JOINT_LIMIT_UPPER,3.0)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,true)
 var initial:=pose(a)
 var before:Dictionary=PhysicsServer3D.call("scene_info",space)
 PhysicsServer3D.body_apply_torque(a,Vector3(0,0,32))
 print("EXPECT_POSTSTEP_ERROR wrap")
 var request:int=PhysicsServer3D.call("scene_request_world_command",space,"step",1)
 var result:=await result_for(request)
 var after:Dictionary=PhysicsServer3D.call("scene_info",space)
 check(not result.get("success",true) and "post-step" in str(result.get("error","")),"external torque wrap rejected after integration",result)
 check(after.time==before.time and result.get("time",-1)==before.time,"wrap rollback time and completion agree",after)
 check(after.paused and pose(a).is_equal_approx(initial),"wrap rollback preserves pose and pause",pose(a))
 check(PhysicsServer3D.body_get_state(a,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY)==Vector3.ZERO and callbacks==0,"wrap rollback preserves velocity and callbacks",callbacks)
 PhysicsServer3D.body_apply_torque(a,Vector3(0,0,-32))
 await step(1)
 check(pose(a).is_equal_approx(initial),"wrap failure retained transient torque for explicit cancellation",pose(a))
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_USE_LIMIT,false)
 PhysicsServer3D.hinge_joint_set_flag(j,PhysicsServer3D.HINGE_JOINT_FLAG_ENABLE_MOTOR,true)
 PhysicsServer3D.hinge_joint_set_param(j,PhysicsServer3D.HINGE_JOINT_MOTOR_MAX_IMPULSE,0.0)
 PhysicsServer3D.body_set_state(a,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D.IDENTITY)
 initial=pose(a);before=PhysicsServer3D.call("scene_info",space);callbacks=0
 PhysicsServer3D.body_apply_torque(a,Vector3(0,0,1005.30965))
 request=PhysicsServer3D.call("scene_request_world_command",space,"step",1)
 result=await result_for(request);after=PhysicsServer3D.call("scene_info",space)
 check(not result.get("success",true),"full revolution external torque rejected",result)
 check(after.time==before.time and pose(a).is_equal_approx(initial),"full revolution rollback",PhysicsServer3D.body_get_state(a,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY))
 await finish("HINGE_ALIAS_RESULT")
