extends SceneTree
var passed:=0
var failed:=0
var space:RID
var owned:Array[RID]=[]
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func body(shape:RID,position:Vector3,mode:int)->RID:
 var b:=PhysicsServer3D.body_create();owned.append(b)
 PhysicsServer3D.body_set_mode(b,mode);PhysicsServer3D.body_add_shape(b,shape)
 PhysicsServer3D.body_set_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,position))
 PhysicsServer3D.body_set_space(b,space);return b
func rejected(b:RID,p:PhysicsTestMotionParameters3D,label:String):
 var before=PhysicsServer3D.body_get_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM)
 var result:=PhysicsTestMotionResult3D.new()
 var hit:=PhysicsServer3D.body_test_motion(b,p,result)
 check(not hit and result.get_collision_count()==0 and result.get_travel()==Vector3.ZERO and result.get_remainder()==p.motion,label+" returns explicit rejected zero travel")
 check(PhysicsServer3D.body_get_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM)==before and not PhysicsServer3D.space_is_active(space),label+" preserves body and inactive space")
func _initialize():call_deferred("run")
func run():
 space=PhysicsServer3D.space_create()
 var box:=PhysicsServer3D.box_shape_create();owned.append(box);PhysicsServer3D.shape_set_data(box,Vector3(.2,2,2))
 var sphere:=PhysicsServer3D.sphere_shape_create();owned.append(sphere);PhysicsServer3D.shape_set_data(sphere,.5)
 var moving:=body(box,Vector3.ZERO,PhysicsServer3D.BODY_MODE_KINEMATIC)
 var p:=PhysicsTestMotionParameters3D.new();p.motion=Vector3.RIGHT
 rejected(moving,p,"unsupported moving box")
 PhysicsServer3D.body_set_shape(moving,0,sphere)
 p.from=Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3.ZERO)
 rejected(moving,p,"scaled from pose")
 p.from=Transform3D.IDENTITY;p.margin=.001
 var left:=body(box,Vector3(-.3,0,0),PhysicsServer3D.BODY_MODE_STATIC)
 var right:=body(box,Vector3(.3,0,0),PhysicsServer3D.BODY_MODE_STATIC)
 rejected(moving,p,"infeasible two-wall recovery")
 PhysicsServer3D.body_set_space(left,RID());PhysicsServer3D.body_set_space(right,RID())
 var tangent:=body(sphere,Vector3(0,1,0),PhysicsServer3D.BODY_MODE_STATIC)
 p.from=Transform3D(Basis.IDENTITY,Vector3(-3,0,0));p.motion=Vector3(10,0,0);p.margin=0
 rejected(moving,p,"unrepresentable grazing unsafe fraction")
 PhysicsServer3D.body_set_space(tangent,RID())
 PhysicsServer3D.body_set_shape_transform(moving,0,Transform3D(Basis.IDENTITY,Vector3(-1e8,0,0)))
 PhysicsServer3D.body_set_state(right,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(6.5,0,0)))
 PhysicsServer3D.body_set_space(right,space)
 p.from=Transform3D(Basis.IDENTITY,Vector3(1e8,0,0));p.motion=Vector3(5,0,0)
 rejected(moving,p,"rounded actual path hits beyond ideal endpoint")
 for rid in owned:PhysicsServer3D.free_rid(rid)
 PhysicsServer3D.free_rid(space)
 print("MOTION_NEGATIVE_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(1 if failed else 0)
