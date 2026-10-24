extends SceneTree
func _initialize():call_deferred("run")
func run():
 var space=PhysicsServer3D.space_create()
 var sphere=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(sphere,.5)
 var box=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(box,Vector3.ONE*.5)
 var target=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_STATIC);PhysicsServer3D.body_add_shape(target,box);PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(6,0,0)));PhysicsServer3D.body_set_space(target,space)
 var mover=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(mover,PhysicsServer3D.BODY_MODE_KINEMATIC);PhysicsServer3D.body_add_shape(mover,sphere,Transform3D(Basis.IDENTITY,Vector3(-1e8,0,0)));PhysicsServer3D.body_set_space(mover,space)
 var p=PhysicsTestMotionParameters3D.new();p.from=Transform3D(Basis.IDENTITY,Vector3(1e8,0,0));p.motion=Vector3(10,0,0);p.margin=0
 var r=PhysicsTestMotionResult3D.new();var hit=PhysicsServer3D.body_test_motion(mover,p,r)
 var unsafe_center:Vector3=p.from.origin+p.motion*r.get_collision_unsafe_fraction()+Vector3(-1e8,0,0)
 print("UNSAFE_PROBE hit=",hit," travel=",r.get_travel()," unsafe=",r.get_collision_unsafe_fraction()," actual_center=",unsafe_center," contact_interval=[5,7] count=",r.get_collision_count())
 for rid in [mover,target,sphere,box,space]:PhysicsServer3D.free_rid(rid)
 quit()
