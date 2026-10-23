extends SceneTree
var scene:Node3D
var passed:=0
var failed:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func ticks(n:int=6):
 for i in n:
  await physics_frame
  await process_frame
func run():
 scene=Node3D.new();root.add_child(scene)
 var box=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(box,Vector3.ONE*.5)
 var sphere=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(sphere,.25)
 var far=Transform3D(Basis.IDENTITY,Vector3(8,0,0))
 # Exact reviewer reproduction first, then every mutator composed with indexing changes.
 for mode in ["remove_disable","remove_set_transform_disable","clear_add_set_transform_disable","add_set_transform_disable","nested_exit_queue"]:
  var area=PhysicsServer3D.area_create();PhysicsServer3D.area_add_shape(area,box)
  var body=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
  PhysicsServer3D.body_add_shape(body,sphere,far)
  PhysicsServer3D.body_add_shape(body,box)
  PhysicsServer3D.area_set_space(area,scene.get_world_3d().space);PhysicsServer3D.body_set_space(body,scene.get_world_3d().space)
  var events:Array=[]
  PhysicsServer3D.area_set_monitor_callback(area,func(status,_rid,_id,index,_self):
   events.append([status,index])
   if status==PhysicsServer3D.AREA_BODY_REMOVED:
    if mode=="nested_exit_queue":PhysicsServer3D.body_set_shape_transform(body,0,far)
    return
   if events.size()!=1:return
   if mode.begins_with("remove") or mode=="nested_exit_queue":
    PhysicsServer3D.body_remove_shape(body,0)
    if mode=="remove_set_transform_disable":
     PhysicsServer3D.body_set_shape(body,0,sphere)
     PhysicsServer3D.body_set_shape_transform(body,0,far)
    if mode=="nested_exit_queue":PhysicsServer3D.body_set_shape_transform(body,0,Transform3D.IDENTITY)
    PhysicsServer3D.body_set_shape_disabled(body,0,true)
   elif mode=="clear_add_set_transform_disable":
    PhysicsServer3D.body_clear_shapes(body)
    PhysicsServer3D.body_add_shape(body,box)
    PhysicsServer3D.body_set_shape(body,0,sphere)
    PhysicsServer3D.body_set_shape_transform(body,0,far)
    PhysicsServer3D.body_set_shape_disabled(body,0,true)
   else:
    PhysicsServer3D.body_add_shape(body,box)
    PhysicsServer3D.body_set_shape(body,2,sphere)
    PhysicsServer3D.body_set_shape_transform(body,2,far)
    PhysicsServer3D.body_set_shape_disabled(body,2,true)
    PhysicsServer3D.body_set_shape_disabled(body,1,true)
   check(PhysicsServer3D.body_get_shape_count(body)==2 and PhysicsServer3D.body_get_shape(body,0)==sphere and PhysicsServer3D.body_get_shape(body,1)==box and PhysicsServer3D.body_get_shape_transform(body,1)==Transform3D.IDENTITY,"no mutation partially visible during callback: "+mode))
  await ticks()
  check(events==[[PhysicsServer3D.AREA_BODY_ADDED,1],[PhysicsServer3D.AREA_BODY_REMOVED,1]],"one enter/exit, no compressed enabled shape reenter: "+mode)
  var expected_count=3 if mode.begins_with("add") else 1
  check(PhysicsServer3D.body_get_shape_count(body)==expected_count,"ordered final count: "+mode)
  var index=2 if expected_count==3 else 0
  if mode!="remove_disable":
   check(PhysicsServer3D.body_get_shape_transform(body,index)==far,"ordered final transform including nested exit callback: "+mode)
  if mode not in ["remove_disable","nested_exit_queue"]:
   check(PhysicsServer3D.body_get_shape(body,index)==sphere,"ordered final shape RID: "+mode)
  PhysicsServer3D.free_rid(area);PhysicsServer3D.free_rid(body)
 PhysicsServer3D.free_rid(box);PhysicsServer3D.free_rid(sphere)
 scene.queue_free();await ticks(2)
 print("AREA_BODY_SHAPE_ORDER_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(0 if failed==0 else 1)
