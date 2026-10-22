extends SceneTree
var failed:=0
func check(ok: bool,label: String) -> void:
 if not ok:failed+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var shape:=PhysicsServer3D.capsule_shape_create()
 var valid:={"radius":.7,"height":2.0}
 PhysicsServer3D.shape_set_data(shape,valid);valid.height=9
 check(PhysicsServer3D.shape_get_data(shape)=={"radius":.7,"height":2.0},"capsule setter copies dictionary")
 var bad:=[{},1,{"height":2},{"radius":"bad","height":2},{"radius":0,"height":2},{"radius":-1,"height":2},{"radius":NAN,"height":2},{"radius":.7,"height":INF},{"radius":.7,"height":0},{"radius":.7,"height":1.3}]
 for value in bad:
  PhysicsServer3D.shape_set_data(shape,value)
  check(PhysicsServer3D.shape_get_data(shape)=={"radius":.7,"height":2.0},"invalid capsule update preserves old data")
 var body:=PhysicsServer3D.body_create()
 PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(body,shape)
 PhysicsServer3D.body_set_shape_transform(body,0,Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3.ZERO))
 check(PhysicsServer3D.body_get_shape_transform(body,0)==Transform3D.IDENTITY,"scaled capsule local pose rejected")
 var space:=PhysicsServer3D.space_create()
 var state:=PhysicsServer3D.space_get_direct_state(space)
 var ball:=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(ball,1.0)
 PhysicsServer3D.body_set_shape(body,0,ball);PhysicsServer3D.body_set_space(body,space)
 PhysicsServer3D.shape_set_data(shape,{"radius":.5,"height":3.0})
 var q:=PhysicsShapeQueryParameters3D.new();q.shape_rid=shape;q.transform.origin=Vector3(-3,2.5,0);q.motion=Vector3(10,0,0)
 check(state.cast_motion(q).is_empty(),"nonrepresentable zero-width capsule graze fails explicitly")
 var wall:=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(wall,Vector3(1e-10,1,1))
 PhysicsServer3D.body_set_shape(body,0,wall)
 PhysicsServer3D.shape_set_data(shape,{"radius":1e-10,"height":4e-10})
 q.transform.origin=Vector3(-3,0,0)
 check(state.cast_motion(q).is_empty(),"collision interval narrower than float fraction fails explicitly")
 for rid in [body,shape,ball,wall,space]:PhysicsServer3D.free_rid(rid)
 print("CAPSULE_NEGATIVE_RESULT ",JSON.stringify({"failed":failed,"expected_errors":bad.size()+1,"sweep_rejections":2,"checks":bad.size()+4}))
 quit(0 if failed==0 else 1)
