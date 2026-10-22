extends SceneTree
var passed:=0
var failed:=0
var owned:Array[RID]=[]
var space:RID
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func shape(kind:int,data:Variant)->RID:
 var s:RID
 match kind:
  PhysicsServer3D.SHAPE_SPHERE:s=PhysicsServer3D.sphere_shape_create()
  PhysicsServer3D.SHAPE_CAPSULE:s=PhysicsServer3D.capsule_shape_create()
  PhysicsServer3D.SHAPE_BOX:s=PhysicsServer3D.box_shape_create()
  _:s=PhysicsServer3D.world_boundary_shape_create()
 PhysicsServer3D.shape_set_data(s,data);owned.append(s);return s
func body(s:RID,position:Vector3,mode:int=PhysicsServer3D.BODY_MODE_STATIC)->RID:
 var b:=PhysicsServer3D.body_create();owned.append(b)
 PhysicsServer3D.body_set_mode(b,mode);PhysicsServer3D.body_add_shape(b,s)
 PhysicsServer3D.body_set_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,position))
 PhysicsServer3D.body_set_space(b,space);return b
func remove(b:RID)->void:PhysicsServer3D.free_rid(b);owned.erase(b)
func parameters(position:Vector3,motion:Vector3)->PhysicsTestMotionParameters3D:
 var p:=PhysicsTestMotionParameters3D.new();p.from=Transform3D(Basis.IDENTITY,position);p.motion=motion;p.margin=0;return p
func _initialize()->void:call_deferred("run")
func run()->void:
 space=PhysicsServer3D.space_create()
 var sphere:=shape(PhysicsServer3D.SHAPE_SPHERE,.5)
 var capsule:=shape(PhysicsServer3D.SHAPE_CAPSULE,{"radius":.5,"height":2.0})
 var box:=shape(PhysicsServer3D.SHAPE_BOX,Vector3.ONE*.5)
 var plane:=shape(PhysicsServer3D.SHAPE_WORLD_BOUNDARY,Plane(Vector3.UP,0))
 var mover:=body(sphere,Vector3(0,7,0),PhysicsServer3D.BODY_MODE_KINEMATIC)
 var target:=body(box,Vector3(4,0,0))
 var p:=parameters(Vector3.ZERO,Vector3(5,0,0))
 var r:=PhysicsTestMotionResult3D.new()
 var original:Transform3D=PhysicsServer3D.body_get_state(mover,PhysicsServer3D.BODY_STATE_TRANSFORM)
 for moving_shape in [sphere,capsule]:
  PhysicsServer3D.body_set_shape(mover,0,moving_shape)
  check(PhysicsServer3D.body_test_motion(mover,p,r),"sphere/capsule body motion hits target")
  check(absf(r.get_collision_safe_fraction()-.6)<2e-5 and r.get_collision_safe_fraction()<=r.get_collision_unsafe_fraction(),"continuous body fractions bracket entry")
  check(r.get_travel().distance_to(Vector3(3,0,0))<.002 and r.get_remainder().distance_to(Vector3(2,0,0))<.002,"travel and remainder partition requested motion")
  var contact:=r.get_collision_count()>0
  check(contact and r.get_collider_rid()==target and r.get_collider_shape()==0 and r.get_collision_local_shape()==0,"body motion native ownership")
  check(contact and r.get_collision_normal().dot(Vector3.LEFT)>.999 and absf(r.get_collision_point().x-3.5)<.002,"body motion target point and outward normal")
 check(PhysicsServer3D.body_get_state(mover,PhysicsServer3D.BODY_STATE_TRANSFORM)==original and not PhysicsServer3D.space_is_active(space),"body_test_motion neither moves actual body nor activates space")
 p.motion=Vector3(-2,0,0)
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"clear motion returns false")
 check(r.get_travel()==p.motion and r.get_remainder()==Vector3.ZERO and r.get_collision_count()==0,"clear motion result travels full distance")
 p.motion=Vector3(5,0,0)
 PhysicsServer3D.body_set_collision_mask(mover,2)
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"moving body's mask filters obstacle layer")
 PhysicsServer3D.body_set_collision_layer(target,2);PhysicsServer3D.body_set_collision_mask(target,0)
 check(PhysicsServer3D.body_test_motion(mover,p,r),"target own collision mask does not hide query target")
 p.exclude_bodies=[target]
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"motion exclude_bodies")
 p.exclude_bodies=[]
 var object:=Node3D.new();root.add_child(object)
 PhysicsServer3D.body_attach_object_instance_id(target,object.get_instance_id())
 p.exclude_objects=[object.get_instance_id()]
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"motion exclude_objects")
 p.exclude_objects=[]
 check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_collision_count()>0 and r.get_collider()==object,"motion collider engine Object identity")
 PhysicsServer3D.body_add_collision_exception(mover,target)
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"moving body exception")
 PhysicsServer3D.body_remove_collision_exception(mover,target)
 PhysicsServer3D.body_add_collision_exception(target,mover)
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"target reciprocal exception")
 PhysicsServer3D.body_remove_collision_exception(target,mover)
 PhysicsServer3D.body_set_shape_disabled(target,0,true)
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"disabled target absent")
 PhysicsServer3D.body_set_shape_disabled(target,0,false)
 PhysicsServer3D.body_set_space(target,RID())
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"detached target absent")
 PhysicsServer3D.body_set_space(target,space)
 PhysicsServer3D.body_set_collision_mask(mover,1);PhysicsServer3D.body_set_collision_layer(target,1)
 # Both shape indices must survive the moving body's compound geometry.
 PhysicsServer3D.body_add_shape(mover,sphere,Transform3D(Basis.IDENTITY,Vector3(1,0,0)))
 check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_collision_count()>0 and r.get_collision_local_shape()==1 and absf(r.get_collision_safe_fraction()-.4)<2e-5,"compound moving shape chooses earliest local index")
 p.max_collisions=1;PhysicsServer3D.body_test_motion(mover,p,r)
 check(r.get_collision_count()==1,"max_collisions one")
 p.max_collisions=32;PhysicsServer3D.body_test_motion(mover,p,r)
 check(r.get_collision_count()>=1 and r.get_collision_count()<=32,"max_collisions thirty-two bounds output")
 PhysicsServer3D.body_remove_shape(mover,1)
 PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_KINEMATIC)
 check(PhysicsServer3D.body_test_motion(mover,p,r),"kinematic target blocks body query")
 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,Vector3(2,0,0))
 check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_collider_velocity().distance_to(Vector3(2,0,0))<.00001,"kinematic target reports explicit linear velocity")
 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,Vector3(0,0,3))
 var kine_hit:=PhysicsServer3D.body_test_motion(mover,p,r)
 var kine_expected:=Vector3(2,0,0)+Vector3(0,0,3).cross(r.get_collision_point()-Vector3(4,0,0))
 check(kine_hit and r.get_collider_velocity().distance_to(kine_expected)<.00001,"kinematic target explicit angular point velocity")
 var rest_query:=PhysicsShapeQueryParameters3D.new();rest_query.shape_rid=sphere;rest_query.transform.origin=Vector3(3.3,0,0)
 var rest:=PhysicsServer3D.space_get_direct_state(space).get_rest_info(rest_query)
 check(not rest.is_empty() and rest.linear_velocity.distance_to(Vector3(2,0,0)+Vector3(0,0,3).cross(rest.point-Vector3(4,0,0)))<.00001,"kinematic rest info shares explicit point velocity")

 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(7,0,0)))
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"updated kinematic target pose visible without step")
 remove(target);object.free()
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"freed target absent and mover excludes itself")
 # A shallow initial penetration should be recovered without advancing simulation.
 var floor:=body(plane,Vector3.ZERO)
 p=parameters(Vector3(0,.8,0),Vector3.ZERO);p.margin=.001;p.recovery_as_collision=false
 check(not PhysicsServer3D.body_test_motion(mover,p,r),"zero motion recovery alone is not collision by default")
 var recovery:=r.get_travel()
 check(recovery.y>.19 and recovery.y<.23 and r.get_remainder()==Vector3.ZERO,"zero motion returns recovery travel")
 p.recovery_as_collision=true
 check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_collision_count()>0,"recovery_as_collision reports initial penetration")
 check(r.get_travel().distance_to(recovery)<.005 and r.get_collision_count()>0 and r.get_collision_normal().dot(Vector3.UP)>.99,"recovery travel and floor normal are stable")
 p.motion=Vector3.DOWN
 check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_travel().y>.18 and r.get_remainder().y<-.98,"travel includes recovery while remainder excludes it")
 check(PhysicsServer3D.body_get_state(mover,PhysicsServer3D.BODY_STATE_TRANSFORM)==original and not PhysicsServer3D.space_is_active(space),"recovery queries preserve real pose and active state")
 remove(floor)
 # Offset COM and angular velocity: expected point velocity is analytic.
 var moving_target:=body(sphere,Vector3(4,0,0),PhysicsServer3D.BODY_MODE_RIGID)
 PhysicsServer3D.body_set_shape_transform(moving_target,0,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
 PhysicsServer3D.body_set_state(moving_target,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,Vector3(2,0,0))
 PhysicsServer3D.body_set_state(moving_target,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,Vector3(0,0,3))
 PhysicsServer3D.body_set_shape(mover,0,sphere)
 p=parameters(Vector3(0,1.2,0),Vector3(5,0,0))
 var collided:=PhysicsServer3D.body_test_motion(mover,p,r)
 check(collided and r.get_collision_count()>0 and r.get_collider_rid()==moving_target,"dynamic target frozen-pose collision")
 var velocity_ok:=false
 if collided and r.get_collision_count()>0:
  var expected:=Vector3(2,0,0)+Vector3(0,0,3).cross(r.get_collision_point()-Vector3(4,1,0))
  velocity_ok=r.get_collider_velocity().distance_to(expected)<.005
 check(velocity_ok,"collider point velocity includes angular motion and offset COM")
 check(PhysicsServer3D.body_get_state(moving_target,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)==Vector3(2,0,0),"query applies no impulse to dynamic target")
 PhysicsServer3D.body_set_mode(moving_target,PhysicsServer3D.BODY_MODE_KINEMATIC)
 collided=PhysicsServer3D.body_test_motion(mover,p,r)
 check(collided and r.get_collider_velocity().distance_to(Vector3(2,0,0)+Vector3(0,0,3).cross(r.get_collision_point()-Vector3(4,1,0)))<.00001,"kinematic explicit velocity uses offset shape COM")
 remove(moving_target)
 # Large unrelated coordinates must not inflate normal recovery.
 var recovery_floor:=body(plane,Vector3.ZERO)
 for cancel in [false,true]:
  for origin in [Vector3(1e8,.4,0),Vector3(-1e8,.4,1e8)]:
   var offset:=Vector3(-origin.x,0,-origin.z) if cancel else Vector3.ZERO
   PhysicsServer3D.body_set_shape_transform(mover,0,Transform3D(Basis.IDENTITY,offset))
   p=parameters(origin,Vector3.ZERO);p.margin=.001;p.recovery_as_collision=true
   check(PhysicsServer3D.body_test_motion(mover,p,r) and r.get_collision_count()>0,"large tangent coordinates retain recovery contact")
   check(absf(r.get_travel().y-.101)<.00001 and r.get_travel().x==0 and r.get_travel().z==0 and r.get_remainder()==Vector3.ZERO,"recovery follows normal without unrelated coordinate slop")
 remove(recovery_floor)
 PhysicsServer3D.body_set_shape_transform(mover,0,Transform3D(Basis.IDENTITY,Vector3(-1e8,0,0)))
 p=parameters(Vector3(1e8,0,0),Vector3(5,0,0))
 check(not PhysicsServer3D.body_test_motion(mover,p,r) and r.get_travel()==p.motion and r.get_remainder()==Vector3.ZERO,"clear large-coordinate travel reports requested vector, not rounded-origin subtraction")
 var thin_wall:=body(box,Vector3(7.5,0,0))
 collided=PhysicsServer3D.body_test_motion(mover,p,r)
 check(collided and r.get_collision_count()>0 and r.get_collider_rid()==thin_wall,"float-only endpoint contact retains real collision metadata")
 var unsafe_center:Vector3=(p.from.origin+p.motion*r.get_collision_unsafe_fraction())+Vector3(-1e8,0,0)
 check(r.get_travel()==Vector3.ZERO and r.get_remainder()==p.motion and absf(unsafe_center.x-7.5)<=1.0,"float-only endpoint collision returns certified safe travel and unsafe pose")
 for rid in owned:PhysicsServer3D.free_rid(rid)
 PhysicsServer3D.free_rid(space)
 print("MOTION_RID_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(0 if failed==0 else 1)
