extends SceneTree
func _initialize():
 var a=PhysicsServer3D.area_create()
 var plane=PhysicsServer3D.world_boundary_shape_create()
 PhysicsServer3D.area_add_shape(a,plane)
 var ok=PhysicsServer3D.area_get_shape_count(a)==0
 PhysicsServer3D.area_set_transform(a,Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO))
 ok=ok and PhysicsServer3D.area_get_transform(a)==Transform3D.IDENTITY
 PhysicsServer3D.area_set_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,PhysicsServer3D.AREA_SPACE_OVERRIDE_COMBINE)
 ok=ok and PhysicsServer3D.area_get_param(a,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE)==PhysicsServer3D.AREA_SPACE_OVERRIDE_DISABLED
 PhysicsServer3D.free_rid(a);PhysicsServer3D.free_rid(plane)
 print("AREA_NEGATIVE_RESULT ",ok)
 quit(0 if ok else 1)
