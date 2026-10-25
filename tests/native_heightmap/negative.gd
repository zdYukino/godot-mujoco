extends SceneTree
func _initialize():
 var s=PhysicsServer3D.heightmap_shape_create()
 var good={"width":2,"depth":2,"heights":PackedFloat32Array([0,1,2,3])}
 PhysicsServer3D.shape_set_data(s,good)
 for bad in [null,{}, {"width":1,"depth":2,"heights":PackedFloat32Array([0,0])},{"width":257,"depth":2,"heights":PackedFloat32Array()}, {"width":2,"depth":2,"heights":PackedFloat32Array([0,NAN,0,0])},{"width":2,"depth":2,"heights":PackedFloat32Array([0,INF,0,0])},{"width":2,"depth":2,"heights":PackedFloat32Array([0,10001,0,0])}]:
  PhysicsServer3D.shape_set_data(s,bad)
  assert(PhysicsServer3D.shape_get_data(s)==good)
 var b=PhysicsServer3D.body_create()
 PhysicsServer3D.body_add_shape(b,s)
 assert(PhysicsServer3D.body_get_shape_count(b)==0)
 PhysicsServer3D.body_set_mode(b,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(b,s)
 PhysicsServer3D.body_set_mode(b,PhysicsServer3D.BODY_MODE_RIGID)
 assert(PhysicsServer3D.body_get_mode(b)==PhysicsServer3D.BODY_MODE_STATIC)
 for scale in [Vector3(2,2,2),Vector3(1,2,1),Vector3(-1,1,1)]:
  PhysicsServer3D.body_set_shape_transform(b,0,Transform3D(Basis.from_scale(scale),Vector3.ZERO))
  assert(PhysicsServer3D.body_get_shape_transform(b,0)==Transform3D.IDENTITY)
 PhysicsServer3D.free_rid(b);PhysicsServer3D.free_rid(s)
 print("HEIGHTMAP_NEGATIVE_RESULT 12 rejected inputs; old data retained");quit()
