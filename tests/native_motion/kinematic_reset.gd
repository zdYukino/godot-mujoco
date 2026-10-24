extends SceneTree
var checks:Array[Dictionary]=[]
var space:RID
var ds:PhysicsDirectSpaceState3D
func check(ok:bool,name:String,detail:Variant=""):checks.append({"passed":ok,"label":name,"detail":detail});print("PASS " if ok else "FAIL ",name," ",detail)
func cmd(name:String):
 var id:int=PhysicsServer3D.call("scene_request_world_command",space,name,0)
 for i in 60:
  await process_frame
  var result:Dictionary=PhysicsServer3D.call("scene_world_command_result",id)
  if not result.is_empty():check(result.get("success",false),name+" completed",result);return
 check(false,name+" timed out")
func ray(x:float)->Dictionary:return ds.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,2,0),Vector3(x,-2,0)))
func _initialize():call_deferred("run")
func run():
 space=PhysicsServer3D.space_create();PhysicsServer3D.space_set_active(space,true);PhysicsServer3D.call("scene_pause",space,true)
 var shape:=PhysicsServer3D.capsule_shape_create();PhysicsServer3D.shape_set_data(shape,{"radius":.3,"height":1.0})
 var target:=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_KINEMATIC);PhysicsServer3D.body_add_shape(target,shape);PhysicsServer3D.body_set_space(target,space)
 var mover:=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(mover,PhysicsServer3D.BODY_MODE_KINEMATIC);PhysicsServer3D.body_add_shape(mover,shape);PhysicsServer3D.body_set_state(mover,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(-10,0,0)));PhysicsServer3D.body_set_space(mover,space)
 var file:=FileAccess.open("res://world.xml",FileAccess.WRITE);file.store_string('<mujoco><option timestep=".01" gravity="0 0 0"/><worldbody/></mujoco>');file.close()
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");check(doc.import_file("res://world.xml"),"import empty world")
 check(PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure world")
 ds=PhysicsServer3D.space_get_direct_state(space)
 check(ray(0).get("rid")==target,"compile original mocap pose")
 await cmd("capture")
 var current:=Transform3D(Basis.IDENTITY,Vector3(4,0,0))
 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,current)
 check(ray(4).get("rid")==target and ray(0).is_empty(),"movement reflected before reset")
 var params:=PhysicsTestMotionParameters3D.new();params.from=Transform3D(Basis.IDENTITY,Vector3(2,0,0));params.motion=Vector3(4,0,0);params.margin=.001
 var result:=PhysicsTestMotionResult3D.new()
 check(PhysicsServer3D.body_test_motion(mover,params,result),"motion sees moved target before reset")
 await cmd("reset")
 check(PhysicsServer3D.body_get_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM)==current,"reset preserves kinematic transform cache")
 check(ray(4).get("rid")==target,"reset preserves current query geometry",ray(4))
 check(ray(0).is_empty(),"reset does not resurrect compiled original position",ray(0))
 result=PhysicsTestMotionResult3D.new()
 check(PhysicsServer3D.body_test_motion(mover,params,result),"motion sees current target after reset")
 for rid in [target,mover,shape,space]:PhysicsServer3D.free_rid(rid)
 var failed:=checks.filter(func(x):return not x.passed).size()
 print("KINEMATIC_RESET_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed,"checks":checks}))
 quit(0 if failed==0 else 1)
