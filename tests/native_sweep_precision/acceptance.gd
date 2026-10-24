extends SceneTree
var passed:=0
var failed:=0
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize():call_deferred("run")
func run():
 var space:=PhysicsServer3D.space_create()
 var state:=PhysicsServer3D.space_get_direct_state(space)
 var sphere:=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(sphere,.37)
 var capsule:=PhysicsServer3D.capsule_shape_create();PhysicsServer3D.shape_set_data(capsule,{"radius":.37,"height":1.5})
 var box:=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(box,Vector3(.73,1.13,.91))
 for i in 24:
  var basis:=Basis.from_euler(Vector3(.17*(i+1),-.26,.33))
  var body_pose:=Transform3D(Basis.IDENTITY,Vector3(2.3,-1.7,4.1))
  var base:=Transform3D(basis,Vector3(.4,.8,-.6))
  var frame:=body_pose*base
  var target:=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_STATIC)
  PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,body_pose)
  PhysicsServer3D.body_add_shape(target,box,Transform3D(basis,base.origin+basis*Vector3(4,0,0)))
  PhysicsServer3D.body_set_space(target,space)
  for multiple in [false,true]:
   if multiple:PhysicsServer3D.body_add_shape(target,box,Transform3D(basis,base.origin+basis*Vector3(7,0,0)))
   for margin in [0.0,.03,.1]:
    for query_shape in [sphere,capsule]:
     var q:=PhysicsShapeQueryParameters3D.new();q.shape_rid=query_shape;q.margin=margin
     q.transform.basis=frame.basis;q.transform.origin=frame*Vector3(-5,.2,-.1);q.motion=basis*Vector3(12,0,0)
     var result:=state.cast_motion(q);var expected:float=(9-.73-.37-margin)/12
     check(result.size()==2,"rotation %d multiple %s margin %s returns certified bracket"%[i,multiple,margin])
     if result.size()!=2:continue
     check(result[0]<=expected+2e-7 and result[1]>=expected-2e-7 and result[0]<=result[1] and absf(result[0]-expected)<2e-6 and absf(result[1]-expected)<2e-6,"analytic face TOI bracket")
     var local_safe:=frame.affine_inverse()*(q.transform.origin+q.motion*result[0])
     var local_unsafe:=frame.affine_inverse()*(q.transform.origin+q.motion*result[1])
     check(local_safe.x<=4-.73-.37-margin+2e-6 and local_unsafe.x>=4-.73-.37-margin-2e-6,"actual Godot float poses agree with face contact within float transform roundoff")
  PhysicsServer3D.free_rid(target)
 PhysicsServer3D.free_rid(capsule);PhysicsServer3D.free_rid(box);PhysicsServer3D.free_rid(sphere);PhysicsServer3D.free_rid(space)
 print("SWEEP_PRECISION_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(1 if failed else 0)
