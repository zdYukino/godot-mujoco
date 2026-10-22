extends SceneTree
var passed=0
var failed=0
var space:RID
var ds:PhysicsDirectSpaceState3D
var owned:Array[RID]=[]
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func shape(kind:int,data)->RID:
 var s:RID
 match kind:
  PhysicsServer3D.SHAPE_SPHERE:s=PhysicsServer3D.sphere_shape_create()
  PhysicsServer3D.SHAPE_BOX:s=PhysicsServer3D.box_shape_create()
  PhysicsServer3D.SHAPE_CYLINDER:s=PhysicsServer3D.cylinder_shape_create()
  _:s=PhysicsServer3D.world_boundary_shape_create()
 PhysicsServer3D.shape_set_data(s,data);owned.append(s);return s
func body(s:RID,t:Transform3D=Transform3D.IDENTITY)->RID:
 var b=PhysicsServer3D.body_create();owned.append(b)
 PhysicsServer3D.body_set_mode(b,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(b,s);PhysicsServer3D.body_set_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM,t)
 PhysicsServer3D.body_set_space(b,space);return b
func remove(b:RID):PhysicsServer3D.free_rid(b);owned.erase(b)
func query(s:RID,p:Vector3,m:Vector3)->PhysicsShapeQueryParameters3D:
 var q=PhysicsShapeQueryParameters3D.new();q.shape_rid=s;q.transform.origin=p;q.motion=m;return q
func fraction(q:PhysicsShapeQueryParameters3D,expected:float,label:String):
 var hit=ds.cast_motion(q)
 check(hit.size()==2 and hit[0]<=expected+1e-7 and hit[1]>=expected-1e-7 and absf(hit[1]-expected)<2e-6,label)
func clear(q:PhysicsShapeQueryParameters3D,label:String):
 check(ds.cast_motion(q)==PackedFloat32Array([1,1]),label)
func _initialize():call_deferred("run")
func run():
 space=PhysicsServer3D.space_create();ds=PhysicsServer3D.space_get_direct_state(space)
 var ball=shape(PhysicsServer3D.SHAPE_SPHERE,1.0)
 var box=shape(PhysicsServer3D.SHAPE_BOX,Vector3.ONE)
 var cylinder=shape(PhysicsServer3D.SHAPE_CYLINDER,{"radius":1.0,"height":2.0})
 var plane=shape(PhysicsServer3D.SHAPE_WORLD_BOUNDARY,Plane(Vector3.UP,0))
 for s in [ball,box,cylinder]:
  var b=body(s)
  var q=query(ball,Vector3(-5,0,0),Vector3(10,0,0))
  fraction(q,.3,"sphere finite primitive TOI")
  var cast=ds.cast_motion(q)
  var original=q.transform
  q.transform.origin+=q.motion*cast[1];q.margin=.0001
  var rest=ds.get_rest_info(q)
  check(not rest.is_empty() and rest.rid==b and rest.normal.dot(Vector3.LEFT)>.999 and absf(rest.point.x+1)<.001,"cast contact agrees with rest-info witness/normal")
  q.transform=original;q.margin=.25;fraction(q,.275,"margin counted once")
  q.margin=0;q.motion=Vector3.ZERO;clear(q,"zero motion")
  q.motion=Vector3(-100,0,0);clear(q,"moving away")
  q.transform.origin=Vector3.ZERO;q.motion=Vector3(10,0,0);clear(q,"initial penetration ignored per shape")
  q.transform.origin=Vector3(-2,0,0);fraction(q,0,"touching and approaching")
  q.motion=Vector3.LEFT;clear(q,"touching and separating")
  q.transform.origin=Vector3(-5,0,0);q.motion=Vector3(1000,0,0);fraction(q,.003,"high speed")
  q.exclude=[b];clear(q,"exclude")
  q.exclude=[];q.collision_mask=2;clear(q,"mask filters layer")
  PhysicsServer3D.body_set_collision_layer(b,2);PhysicsServer3D.body_set_collision_mask(b,0)
  fraction(q,.003,"target own mask ignored")
  PhysicsServer3D.body_set_shape_disabled(b,0,true);clear(q,"disabled")
  PhysicsServer3D.body_set_shape_disabled(b,0,false);fraction(q,.003,"reenabled")
  PhysicsServer3D.body_set_space(b,RID());clear(q,"detached")
  PhysicsServer3D.body_set_space(b,space);fraction(q,.003,"reattached")
  remove(b);clear(q,"freed target")
 var target=body(ball)
 fraction(query(ball,Vector3(-5,2,0),Vector3(10,0,0)),.5,"zero-width grazing sphere")
 clear(query(ball,Vector3(-5,2.001,0),Vector3(10,0,0)),"near tangent miss")
 remove(target)
 target=body(box)
 fraction(query(ball,Vector3(-5,1.6,0),Vector3(10,0,0)),.32,"rounded box corner not expanded AABB")
 remove(target)
 target=body(cylinder)
 fraction(query(ball,Vector3(-5,1.6,0),Vector3(10,0,0)),.32,"rounded cylinder cap edge")
 remove(target)
 var wall=shape(PhysicsServer3D.SHAPE_BOX,Vector3(.001,5,5));target=body(wall)
 var tiny=shape(PhysicsServer3D.SHAPE_SPHERE,.01)
 fraction(query(tiny,Vector3(-10,0,0),Vector3(20000,0,0)),(10-.011)/20000,"high speed thin wall")
 remove(target)
 var floor=body(plane)
 for s in [ball,box,cylinder]:
  fraction(query(s,Vector3(0,5,0),Vector3(0,-10,0)),.4,"finite shape plane continuous TOI")
  var q=query(s,Vector3(0,5,0),Vector3(0,-10,0));q.margin=.2;fraction(q,.38,"finite plane margin")
 remove(floor)
 target=body(ball)
 fraction(query(plane,Vector3(0,-5,0),Vector3(0,10,0)),.4,"moving plane toward finite primitive")
 remove(target)
 # Both query orientation and target body/local-shape rotations are respected.
 var pose=Transform3D(Basis.from_euler(Vector3(.2,.5,.3)),Vector3(3,2,-4))
 target=body(box,pose)
 var local=Transform3D(Basis.from_euler(Vector3(-.4,.2,.1)),Vector3(5,0,0))
 PhysicsServer3D.body_add_shape(target,cylinder,local)
 PhysicsServer3D.body_set_shape_disabled(target,0,true)
 var world=pose*local
 var rotated=query(ball,world*Vector3(-5,0,0),world.basis*Vector3(10,0,0))
 fraction(rotated,.3,"rotated body and local offset")
 var cast=ds.cast_motion(rotated);rotated.transform.origin+=rotated.motion*cast[1];rotated.margin=.0001
 var rest=ds.get_rest_info(rotated)
 check(not rest.is_empty() and rest.shape==1 and rest.normal.dot(world.basis*Vector3.LEFT)>.999,"rotated rest-info shape and normal")
 remove(target)
 floor=body(plane)
 var long_box=shape(PhysicsServer3D.SHAPE_BOX,Vector3(.2,2,.3))
 var boxq=query(long_box,Vector3(0,5,0),Vector3(0,-10,0));boxq.transform.basis=Basis(Vector3.FORWARD,PI/2)
 fraction(boxq,.48,"query box rotation support against plane")
 var cylq=query(cylinder,Vector3(0,5,0),Vector3(0,-10,0));cylq.transform.basis=Basis(Vector3.FORWARD,.4)
 fraction(cylq,(5-cos(.4)-sin(.4))/10,"rotated cylinder support against plane")
 remove(floor)
 var first=body(ball);var second=body(ball,Transform3D(Basis.IDENTITY,Vector3(4,0,0)))
 var q=query(ball,Vector3(-5,0,0),Vector3(20,0,0));fraction(q,.15,"earliest of multiple targets")
 q.exclude=[first];fraction(q,.35,"excluded nearest reveals second")
 q.exclude=[];q.transform.origin=Vector3.ZERO;fraction(q,.1,"skip initial overlap but keep later obstacle")
 var before=PhysicsServer3D.body_get_state(first,PhysicsServer3D.BODY_STATE_TRANSFORM)
 for i in 5:ds.cast_motion(q)
 check(not PhysicsServer3D.space_is_active(space) and before==PhysicsServer3D.body_get_state(first,PhysicsServer3D.BODY_STATE_TRANSFORM),"sweep does not activate or integrate")
 PhysicsServer3D.body_set_mode(first,PhysicsServer3D.BODY_MODE_RIGID)
 PhysicsServer3D.body_set_param(first,PhysicsServer3D.BODY_PARAM_MASS,1e-20)
 check(ds.cast_motion(q).is_empty(),"failed rebuild fails rather than using stale model")
 PhysicsServer3D.body_set_param(first,PhysicsServer3D.BODY_PARAM_MASS,1.0)
 fraction(q,.1,"recovery after failed rebuild")
 q.margin=-1;check(ds.cast_motion(q).is_empty(),"negative margin rejected")
 q.margin=0;q.transform.basis=Basis.from_scale(Vector3(2,1,1));check(ds.cast_motion(q).is_empty(),"scaled transform rejected")
 q.transform=Transform3D.IDENTITY;q.motion=Vector3(INF,0,0);check(ds.cast_motion(q).is_empty(),"nonfinite motion rejected")
 for r in owned:PhysicsServer3D.free_rid(r)
 PhysicsServer3D.free_rid(space)
 print("SWEEP_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(1 if failed else 0)
