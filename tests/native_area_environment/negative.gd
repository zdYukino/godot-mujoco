extends SceneTree
func _initialize():
 var a=PhysicsServer3D.area_create()
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY,7.0)
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY,NAN)
 var ok=PhysicsServer3D.area_get_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY)==7.0
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP,-1.0)
 ok=ok and is_equal_approx(PhysicsServer3D.area_get_param(a,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP),.1)
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,Vector3(INF,0,0))
 ok=ok and PhysicsServer3D.area_get_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR)==Vector3.DOWN
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,99)
 ok=ok and PhysicsServer3D.area_get_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE)==0
 PhysicsServer3D.free_rid(a)
 print("AREA_ENVIRONMENT_NEGATIVE_RESULT ",ok)
 quit(0 if ok else 1)
