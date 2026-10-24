extends SceneTree
func _initialize():call_deferred("run")
func run():
 var space=PhysicsServer3D.space_create()
 var ds=PhysicsServer3D.space_get_direct_state(space)
 var box=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(box,Vector3.ONE)
 var ball=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(ball,1.0)
 var b=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(b,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(b,ball);PhysicsServer3D.body_set_space(b,space)
 var q=PhysicsShapeQueryParameters3D.new();q.shape_rid=box;q.transform.origin=Vector3(-5,0,0);q.motion=Vector3(10,0,0)
 var ok=ds.cast_motion(q).is_empty()
 q.exclude=[b]
 ok=ok and ds.cast_motion(q)==PackedFloat32Array([1,1])
 q.shape_rid=ball;q.collide_with_areas=true
 ok=ok and ds.cast_motion(q).is_empty()
 q.collide_with_areas=false;q.exclude=[];q.transform.origin=Vector3(-3,2,0)
 ok=ok and ds.cast_motion(q).is_empty()
 PhysicsServer3D.shape_set_data(box,Vector3(1e-10,1,1));PhysicsServer3D.body_set_shape(b,0,box)
 PhysicsServer3D.shape_set_data(ball,1e-10);q.transform.origin=Vector3(-3,0,0)
 ok=ok and ds.cast_motion(q).is_empty()
 PhysicsServer3D.shape_set_data(ball,1.0);PhysicsServer3D.body_set_shape(b,0,ball)
 PhysicsServer3D.body_set_state(b,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(100000008,0,0)))
 q.transform.origin=Vector3(100000000,0,0)
 # Large world-coordinate ULPs now admit a wider, independently certified
 # bracket. This case must prove both continuous and actual float pose signs.
 var wide:=ds.cast_motion(q)
 var certified:=wide.size()==2
 if certified:
  var safe_gap:=absf(8.0-10.0*wide[0])-2.0
  var unsafe_gap:=absf(8.0-10.0*wide[1])-2.0
  var safe_pose:Vector3=q.transform.origin+q.motion*wide[0]
  var unsafe_pose:Vector3=q.transform.origin+q.motion*wide[1]
  certified=wide[0]<=wide[1] and safe_gap>=0 and unsafe_gap<=0 and absf(safe_pose.x-100000008.0)>=2 and absf(unsafe_pose.x-100000008.0)<=2
 print("SWEEP_LARGE_FLOAT_BRACKET ",wide," certified=",certified)
 ok=certified and ok
 for rid in [b,ball,box,space]:PhysicsServer3D.free_rid(rid)
 print("SWEEP_NEGATIVE_RESULT ","PASS" if ok else "FAIL")
 quit(0 if ok else 1)
