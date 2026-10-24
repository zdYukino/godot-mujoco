extends SceneTree
var passed=0
var failed=0
var space:RID
var ds:PhysicsDirectSpaceState3D
var owned:Array[RID]=[]
func check(ok:bool,label:String):
 if ok: passed+=1
 else: failed+=1
 print("PASS " if ok else "FAIL ",label)
func shape(kind:int,data)->RID:
 var s:RID
 match kind:
  PhysicsServer3D.SHAPE_BOX:s=PhysicsServer3D.box_shape_create()
  PhysicsServer3D.SHAPE_SPHERE:s=PhysicsServer3D.sphere_shape_create()
  PhysicsServer3D.SHAPE_CYLINDER:s=PhysicsServer3D.cylinder_shape_create()
  _:s=PhysicsServer3D.world_boundary_shape_create()
 PhysicsServer3D.shape_set_data(s,data);owned.append(s);return s
func body(s:RID,t:Transform3D=Transform3D.IDENTITY)->RID:
 var b=PhysicsServer3D.body_create();owned.append(b)
 PhysicsServer3D.body_set_mode(b,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(b,s)
 PhysicsServer3D.body_set_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM,t)
 PhysicsServer3D.body_set_space(b,space)
 return b
func point(p:Vector3,mask:int=1,exclude:Array[RID]=[],limit:int=32)->Array:
 var q=PhysicsPointQueryParameters3D.new();q.position=p;q.collision_mask=mask;q.exclude=exclude
 return ds.intersect_point(q,limit)
func query(s:RID,p:Vector3=Vector3.ZERO)->PhysicsShapeQueryParameters3D:
 var q=PhysicsShapeQueryParameters3D.new();q.shape_rid=s;q.transform.origin=p;return q
func _initialize():call_deferred("run")
func run():
 space=PhysicsServer3D.space_create();ds=PhysicsServer3D.space_get_direct_state(space)
 var ball=shape(PhysicsServer3D.SHAPE_SPHERE,1.0)
 var box=shape(PhysicsServer3D.SHAPE_BOX,Vector3.ONE)
 var cylinder=shape(PhysicsServer3D.SHAPE_CYLINDER,{"radius":1.0,"height":2.0})
 var plane=shape(PhysicsServer3D.SHAPE_WORLD_BOUNDARY,Plane(Vector3.UP,0))
 var shapes=[ball,box,cylinder]
 for target in shapes:
  var b=body(target)
  check(point(Vector3.ZERO).size()==1,"point inside primitive")
  check(point(Vector3(1,0,0)).is_empty(),"point boundary excluded")
  check(point(Vector3(2,0,0)).is_empty(),"point outside primitive")
  check(point(Vector3.ZERO,1,[b]).is_empty(),"point exclusion")
  for probe in shapes:
   var q=query(probe,Vector3(1.5,0,0))
   var hits=ds.intersect_shape(q)
   check(hits.size()==1 and hits[0].rid==b and hits[0].shape==0,"primitive pair identity")
   var contacts=ds.collide_shape(q)
   check(contacts.size()>=2 and contacts.size()%2==0,"primitive contact pairs")
   check(contacts.size()>=2 and absf(contacts[0].x-.5)<.03 and absf(contacts[1].x-1)<.03,"query then target contact witnesses")
   var rest=ds.get_rest_info(q)
   check(not rest.is_empty() and rest.normal.dot(Vector3.RIGHT)>.95,"primitive outward rest normal")
   check(not rest.is_empty() and absf(rest.point.x-1)<.03,"rest on target surface")
   q.transform.origin=Vector3(3,0,0);q.motion=Vector3(-3,0,0)
   check(ds.intersect_shape(q).is_empty() and ds.collide_shape(q).is_empty() and ds.get_rest_info(q).is_empty(),"overlap ignores motion; separated")
   q.transform.origin=Vector3.ZERO
   check(ds.intersect_shape(q).size()==1,"initial penetration included")
   q.transform.origin=Vector3(2.05,0,0);q.margin=.1
   check(ds.intersect_shape(q).size()==1,"pair positive margin")
   q.margin=.01
   check(ds.intersect_shape(q).is_empty(),"pair below separation margin")
  var plane_q=query(plane,Vector3(0,.5,0))
  var plane_rest=ds.get_rest_info(plane_q)
  check(not plane_rest.is_empty() and plane_rest.normal.dot(Vector3.DOWN)>.99,"plane as query reversed ownership")
  plane_q.transform.origin=Vector3(0,-2,0)
  check(ds.intersect_shape(plane_q).is_empty(),"plane query separated")
  var q=query(ball,Vector3(2.05,0,0));q.margin=.1
  check(ds.intersect_shape(q).size()==1,"positive margin detects separation")
  q.margin=0;check(ds.intersect_shape(q).is_empty(),"zero margin misses separation")
  q.transform.origin=Vector3.ZERO;q.collision_mask=2
  check(ds.intersect_shape(q).is_empty(),"shape layer mask")
  PhysicsServer3D.body_set_collision_layer(b,2);PhysicsServer3D.body_set_collision_mask(b,0)
  check(ds.intersect_shape(q).size()==1,"body mask does not hide query target")
  q.exclude=[b];check(ds.intersect_shape(q).is_empty() and ds.collide_shape(q).is_empty() and ds.get_rest_info(q).is_empty(),"exclude shared by shape APIs")
  q.exclude=[]
  PhysicsServer3D.body_set_shape_disabled(b,0,true)
  check(ds.intersect_shape(q).is_empty(),"disabled absent immediately")
  PhysicsServer3D.body_set_shape_disabled(b,0,false)
  check(ds.intersect_shape(q).size()==1,"reenabled present immediately")
  PhysicsServer3D.body_set_space(b,RID())
  check(ds.intersect_shape(q).is_empty(),"detached absent immediately")
  PhysicsServer3D.free_rid(b);owned.erase(b)
 var floor=body(plane)
 check(point(Vector3(0,-100,0)).size()==1 and point(Vector3.ZERO).is_empty(),"plane negative half space open boundary")
 for probe in shapes:
  var q=query(probe,Vector3(0,.5,0));var rest=ds.get_rest_info(q)
  check(not rest.is_empty() and rest.normal.dot(Vector3.UP)>.99 and absf(rest.point.y)<.002,"primitive against plane normal and witness")
 PhysicsServer3D.free_rid(floor);owned.erase(floor)
 var compound=body(box,Transform3D(Basis.from_euler(Vector3(.2,.4,.3)),Vector3(3,2,1)))
 var local=Transform3D(Basis.from_euler(Vector3(.3,-.2,.1)),Vector3(4,0,0))
 PhysicsServer3D.body_add_shape(compound,cylinder,local)
 var world:Transform3D=PhysicsServer3D.body_get_state(compound,PhysicsServer3D.BODY_STATE_TRANSFORM)*local
 var q=query(ball,world.origin)
 check(point(world.origin)[0].shape==1 and ds.intersect_shape(q)[0].shape==1,"rotated local offset shape index")
 q.transform.origin=world*Vector3(0,1.5,0)
 var cap=ds.get_rest_info(q)
 check(not cap.is_empty() and cap.normal.dot(world.basis*Vector3.UP)>.99 and cap.point.distance_to(world*Vector3.UP)<.02,"rotated offset cylinder cap geometry")
 q.shape_rid=cylinder;q.transform=world
 check(not ds.intersect_shape(q).is_empty() and ds.intersect_shape(q)[0].shape==1,"rotated query cylinder")
 PhysicsServer3D.body_remove_shape(compound,0)
 check(not ds.intersect_shape(q).is_empty() and ds.intersect_shape(q)[0].shape==0,"shape index updated after removal")
 PhysicsServer3D.free_rid(compound);owned.erase(compound)
 check(ds.intersect_shape(q).is_empty(),"freed owner absent")
 # Collider pointer must cross the native ABI as engine Object*, not wrapper Object*.
 var object=Node3D.new();root.add_child(object)
 var attached=body(ball);PhysicsServer3D.body_attach_object_instance_id(attached,object.get_instance_id())
 var attached_hits=ds.intersect_shape(query(ball))
 check(attached_hits.size()==1 and attached_hits[0].collider==object and attached_hits[0].collider_id==object.get_instance_id(),"engine collider Object identity")
 PhysicsServer3D.free_rid(attached);owned.erase(attached);object.free()
 var thin=shape(PhysicsServer3D.SHAPE_BOX,Vector3(.2,2,.3))
 var target_ball=body(ball)
 var rotated_query=query(thin,Vector3(1.6,0,0))
 check(ds.intersect_shape(rotated_query).is_empty(),"asymmetric unrotated box separated")
 rotated_query.transform.basis=Basis(Vector3.FORWARD,PI/2)
 check(ds.intersect_shape(rotated_query).size()==1,"asymmetric rotated query box overlaps")
 PhysicsServer3D.free_rid(target_ball);owned.erase(target_ball)
 var b1=body(box);var b2=body(ball)
 PhysicsServer3D.body_add_shape(b1,ball)
 q=query(ball)
 var huge=shape(PhysicsServer3D.SHAPE_SPHERE,1e100)
 check(ds.intersect_shape(query(huge)).is_empty() and ds.collide_shape(query(huge)).is_empty() and ds.get_rest_info(query(huge)).is_empty(),"unrepresentable unattached query size rejected")
 var all=ds.intersect_shape(q)
 check(ds.intersect_shape(q,0).is_empty() and ds.collide_shape(q,0).is_empty() and point(Vector3.ZERO,1,[],0).is_empty(),"zero capacity")
 q.margin=-1
 check(ds.intersect_shape(q).is_empty(),"negative margin rejected")
 q.margin=NAN
 check(ds.intersect_shape(q).is_empty(),"nonfinite margin rejected")
 q.margin=0;q.transform.basis=Basis.from_scale(Vector3(2,1,1))
 check(ds.intersect_shape(q).is_empty(),"scaled query rejected")
 q.transform=Transform3D.IDENTITY
 check(all.size()==3,"deduplicate manifold but preserve multiple shapes")
 check(ds.intersect_shape(q,1).size()==1 and ds.collide_shape(q,1).size()==2 and point(Vector3.ZERO,1,[],1).size()==1,"max_results counts shapes or contact pairs")
 for i in 5:
  var hits=ds.intersect_shape(q)
  check(hits==all,"deterministic RID shape sorting")
 check(not PhysicsServer3D.space_is_active(space),"queries do not activate space")
 PhysicsServer3D.body_set_mode(b1,PhysicsServer3D.BODY_MODE_RIGID)
 PhysicsServer3D.body_set_state(b1,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,Vector3(2,0,0))
 PhysicsServer3D.body_set_state(b1,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,Vector3(0,0,1))
 q=query(ball,Vector3(0,1.5,0));q.exclude=[b2]
 var before=PhysicsServer3D.body_get_state(b1,PhysicsServer3D.BODY_STATE_TRANSFORM)
 var rest=ds.get_rest_info(q)
 check(not rest.is_empty() and rest.linear_velocity.distance_to(Vector3(2,0,0)+Vector3(0,0,1).cross(rest.point))<.01,"rest velocity at contact includes angular velocity")
 for i in 10:ds.collide_shape(q)
 check(PhysicsServer3D.body_get_state(b1,PhysicsServer3D.BODY_STATE_TRANSFORM)==before and PhysicsServer3D.body_get_state(b1,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)==Vector3(2,0,0),"repeated queries do not integrate")
 # A dirty model that cannot compile must never expose last successful geometry.
 PhysicsServer3D.body_set_param(b1,PhysicsServer3D.BODY_PARAM_MASS,1e-20)
 check(ds.intersect_shape(q).is_empty() and point(Vector3.ZERO).is_empty() and ds.collide_shape(q).is_empty() and ds.get_rest_info(q).is_empty(),"failed rebuild hides stale geometry")
 PhysicsServer3D.body_set_param(b1,PhysicsServer3D.BODY_PARAM_MASS,1.0)
 check(not ds.intersect_shape(q).is_empty(),"recovery after failed rebuild")
 var other=PhysicsServer3D.space_create()
 PhysicsServer3D.body_set_space(b1,other)
 check(ds.intersect_shape(q).is_empty(),"moved to another space absent")
 PhysicsServer3D.body_set_space(b1,space);PhysicsServer3D.free_rid(other)
 check(not ds.intersect_shape(q).is_empty(),"reattach after space switch")
 for r in owned:PhysicsServer3D.free_rid(r)
 PhysicsServer3D.free_rid(space)
 print("OVERLAP_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(1 if failed else 0)
