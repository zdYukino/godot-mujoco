extends SceneTree
func _initialize():call_deferred("run")
func run():
 var shape=PhysicsServer3D.cylinder_shape_create()
 var valid={"radius":.7,"height":2.0};PhysicsServer3D.shape_set_data(shape,valid);valid.height=9
 assert(PhysicsServer3D.shape_get_data(shape).height==2.0)
 var bad=[{},1,{"radius":"bad","height":2},{"radius":0,"height":2},{"radius":-1,"height":2},{"radius":NAN,"height":2},{"radius":1,"height":INF},{"radius":1,"height":0}]
 for value in bad:
  PhysicsServer3D.shape_set_data(shape,value)
  assert(PhysicsServer3D.shape_get_data(shape)=={"radius":.7,"height":2.0})
 var body=PhysicsServer3D.body_create();PhysicsServer3D.body_add_shape(body,shape)
 PhysicsServer3D.body_set_shape_transform(body,0,Transform3D(Basis.IDENTITY.scaled(Vector3(2,1,1)),Vector3.ZERO))
 assert(PhysicsServer3D.body_get_shape_transform(body,0)==Transform3D.IDENTITY)
 PhysicsServer3D.free_rid(body);PhysicsServer3D.free_rid(shape)
 print("CYLINDER_NEGATIVE_RESULT 9 rejected inputs; old data retained")
 quit()
