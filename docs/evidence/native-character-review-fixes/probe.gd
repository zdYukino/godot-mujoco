extends SceneTree
func _initialize():call_deferred("run")
func run():
 var space=PhysicsServer3D.space_create()
 var sphere=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(sphere,.5)
 var plane=PhysicsServer3D.world_boundary_shape_create();PhysicsServer3D.shape_set_data(plane,Plane(Vector3.UP,0))
 var floor=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(floor,PhysicsServer3D.BODY_MODE_STATIC);PhysicsServer3D.body_add_shape(floor,plane);PhysicsServer3D.body_set_space(floor,space)
 var mover=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(mover,PhysicsServer3D.BODY_MODE_KINEMATIC);PhysicsServer3D.body_add_shape(mover,sphere);PhysicsServer3D.body_set_space(mover,space)
 for cancel in [false,true]:
  PhysicsServer3D.body_set_shape_transform(mover,0,Transform3D(Basis.IDENTITY,Vector3(-1e8,0,0) if cancel else Vector3.ZERO))
  var p=PhysicsTestMotionParameters3D.new();p.from=Transform3D(Basis.IDENTITY,Vector3(1e8,.4,0));p.margin=.001;p.motion=Vector3.ZERO;p.recovery_as_collision=true
  var result=PhysicsTestMotionResult3D.new();var hit=PhysicsServer3D.body_test_motion(mover,p,result)
  print("RECOVERY_PROBE cancel=",cancel," hit=",hit," travel=",result.get_travel()," expected_y=",.501-.4)
 for rid in [mover,floor,sphere,plane,space]:PhysicsServer3D.free_rid(rid)
 quit()
