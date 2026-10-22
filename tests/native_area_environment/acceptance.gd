extends SceneTree
var passed:=0
var failed:=0
var owned:Array[RID]=[]
var space:RID
var body:RID
var field_shape:RID
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func near(actual:Vector3,expected:Vector3,label:String,tolerance:float=.0001):check(actual.distance_to(expected)<tolerance,label+" actual="+str(actual)+" expected="+str(expected))
func frames(n:int=2):
 for i in n:
  await physics_frame
  await process_frame
func step(n:int=1):
 var request:int=PhysicsServer3D.call("scene_request_world_command",space,"step",n)
 var result:Dictionary={}
 for i in 30:
  await frames(1)
  result=PhysicsServer3D.call("scene_world_command_result",request)
  if not result.is_empty():break
 check(result.get("success",false),"paused single-step completes")
 await frames(2)
func ap(a:RID,key:int,value:Variant):PhysicsServer3D.area_set_param(a,key,value)
func bp(key:int,value:Variant):PhysicsServer3D.body_set_param(body,key,value)
func velocity()->Vector3:return PhysicsServer3D.body_get_state(body,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
func reset(v:Vector3=Vector3.ZERO,w:Vector3=Vector3.ZERO,p:Vector3=Vector3.ZERO):
 PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,p))
 PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,v)
 PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,w)
func field(priority:int,g:Vector3,ld:float,ad:float)->RID:
 var a=PhysicsServer3D.area_create();owned.append(a)
 PhysicsServer3D.area_add_shape(a,field_shape);PhysicsServer3D.area_set_space(a,space)
 ap(a,PhysicsServer3D.AREA_PARAM_PRIORITY,priority)
 ap(a,PhysicsServer3D.AREA_PARAM_GRAVITY,g.length());ap(a,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,g.normalized())
 ap(a,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP,ld);ap(a,PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP,ad)
 PhysicsServer3D.area_set_monitorable(a,false)
 for mode in [PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE,PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP_OVERRIDE_MODE]:ap(a,mode,1)
 return a
func run():
 space=PhysicsServer3D.space_create();owned.append(space);PhysicsServer3D.space_set_active(space,true);PhysicsServer3D.call("scene_pause",space,true)
 var file=FileAccess.open("res://environment.xml",FileAccess.WRITE);file.store_string('<mujoco><option timestep=".01" gravity="0 0 -10" integrator="Euler"/><worldbody/></mujoco>');file.close()
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");check(doc.import_file("res://environment.xml"),"import lightweight authored world")
 check(PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure .01 single steps")
 ap(space,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP,1.0);ap(space,PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP,2.0)
 field_shape=PhysicsServer3D.box_shape_create();owned.append(field_shape);PhysicsServer3D.shape_set_data(field_shape,Vector3.ONE*5)
 var ball=PhysicsServer3D.sphere_shape_create();owned.append(ball);PhysicsServer3D.shape_set_data(ball,.25)
 body=PhysicsServer3D.body_create();owned.append(body);PhysicsServer3D.body_add_shape(body,ball);PhysicsServer3D.body_set_space(body,space)
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,1);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,1)
 var low=field(0,Vector3(0,3,0),7,8);var high=field(10,Vector3(2,0,0),5,6);var top=field(20,Vector3(0,0,4),3,4)
 var expected=[Vector3(0,-7,4),Vector3(2,-7,4),Vector3(2,0,4),Vector3(2,0,0),Vector3(2,-7,0)]
 for mode in 5:
  ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,mode);reset();await step()
  near(velocity(),expected[mode]*.01,"priority gravity mode %d physical velocity"%mode)
  near(PhysicsServer3D.body_get_direct_state(body).total_gravity,expected[mode],"gravity getter agrees %d"%mode)
 ap(high,PhysicsServer3D.AREA_PARAM_PRIORITY,30);ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,2)
 reset();await step();near(velocity(),Vector3(.02,0,0),"priority edit changes processing before higher contribution")
 ap(high,PhysicsServer3D.AREA_PARAM_PRIORITY,10)
 # Disabled monitoring and monitorable never prevent environment contribution.
 check(PhysicsServer3D.area_get_shape_count(high)==1,"fields applied without monitor callbacks")
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,3)
 bp(PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,-2.0);reset();await step();near(velocity(),Vector3(-.04,0,0),"body gravity_scale applies after replacement")
 bp(PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,0.0)
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,0);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,0)
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP,.5);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP,1.0)
 var ld=[11.5,16.5,8.5,5.5,13.5];var ad=[15.0,21.0,11.0,7.0,17.0]
 for mode in 5:
  ap(high,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE,mode);ap(high,PhysicsServer3D.AREA_PARAM_ANGULAR_DAMP_OVERRIDE_MODE,mode)
  reset(Vector3(10,0,0),Vector3(0,10,0));await step()
  near(velocity(),Vector3(10*(1-ld[mode]*.01),0,0),"linear damping mode %d physical velocity"%mode)
  near(PhysicsServer3D.body_get_state(body,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),Vector3(0,10*(1-ad[mode]*.01),0),"angular damping mode %d physical velocity"%mode)
 # Damping exits/disables use the same current overlap membership as gravity.
 ap(high,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE,3)
 PhysicsServer3D.area_set_shape_disabled(high,0,true)
 reset(Vector3(10,0,0));await step();near(velocity(),Vector3(8.85,0,0),"disabled field restores lower priority damping and World")
 PhysicsServer3D.area_set_shape_disabled(high,0,false)
 reset(Vector3(10,0,0));await step();near(velocity(),Vector3(9.45,0,0),"reenabled field restores replacement damping")
 reset(Vector3(10,0,0),Vector3.ZERO,Vector3(20,0,0));await step();near(velocity(),Vector3(9.85,0,0),"leaving all fields restores default damping")
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,1);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,1)
 reset(Vector3(10,0,0),Vector3(0,10,0));await step(3)
 near(velocity(),Vector3(9.85,0,0),"body replace damping once per .03 interval")
 near(PhysicsServer3D.body_get_state(body,PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY),Vector3(0,9.7,0),"angular body replace ignores Area totals")
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP,0.0);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP,0.0);bp(PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,1.0)
 # Remove all but one field: each mutation must change actual acceleration.
 PhysicsServer3D.free_rid(top);owned.erase(top);PhysicsServer3D.free_rid(low);owned.erase(low)
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,3)
 PhysicsServer3D.area_add_shape(high,field_shape)
 reset();await step();near(velocity(),Vector3(.02,0,0),"multiple overlapping Area shapes contribute only once")
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,1)
 reset();await step();near(velocity(),Vector3(.02,-.1,0),"combine includes default world gravity")
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_OVERRIDE_MODE,3)
 reset(Vector3.ZERO,Vector3.ZERO,Vector3(20,0,0));await step();near(velocity(),Vector3(0,-.1,0),"leaving Area restores world gravity")
 PhysicsServer3D.area_set_shape_disabled(high,0,true);PhysicsServer3D.area_set_shape_disabled(high,1,true)
 reset();await step();near(velocity(),Vector3(0,-.1,0),"disabled shapes restore world gravity")
 PhysicsServer3D.area_set_shape_disabled(high,0,false)
 reset();await step();near(velocity(),Vector3(.02,0,0),"reenabled shape restores field")
 PhysicsServer3D.area_set_collision_mask(high,0);reset();await step();near(velocity(),Vector3(0,-.1,0),"field mask filters body layer")
 PhysicsServer3D.area_set_collision_mask(high,1)
 # Directional vector is world-space and unnormalized even on rotated Areas.
 PhysicsServer3D.area_set_transform(high,Transform3D(Basis(Vector3.FORWARD,.4),Vector3.ZERO));ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,Vector3(2,0,0));ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY,3.0)
 reset();await step();near(velocity(),Vector3(.06,0,0),"world directional vector is not rotated or normalized")
 PhysicsServer3D.area_set_transform(high,Transform3D(Basis.IDENTITY,Vector3(1,0,0)))
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_IS_POINT,true);ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,Vector3(1,0,0));ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY,8.0);ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_POINT_UNIT_DISTANCE,1.0)
 reset();await step();near(velocity(),Vector3(.02,0,0),"transformed point center inverse-square gravity")
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_POINT_UNIT_DISTANCE,0.0);reset();await step();near(velocity(),Vector3(.08,0,0),"zero unit distance uses constant point strength")
 reset(Vector3.ZERO,Vector3.ZERO,Vector3(2,0,0));await step();near(velocity(),Vector3.ZERO,"point center has zero gravity")
 # Queued callback changes affect the following interval, never the completed one.
 ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_IS_POINT,false);ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,Vector3.RIGHT);ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY,2.0)
 var changed=[false]
 PhysicsServer3D.body_set_force_integration_callback(body,func(_state):
  if not changed[0]:
   changed[0]=true;ap(high,PhysicsServer3D.AREA_PARAM_GRAVITY,6.0))
 reset();await step();near(velocity(),Vector3(.02,0,0),"callback change does not retroactively affect finished step")
 reset();await step();near(velocity(),Vector3(.06,0,0),"callback parameter change applies next step")
 var before=velocity();await frames(6);near(velocity(),before,"paused world does not integrate field")
 PhysicsServer3D.body_set_omit_force_integration(body,true);reset();await step();near(velocity(),Vector3.ZERO,"custom integrator suppresses automatic Area gravity")
 PhysicsServer3D.body_set_force_integration_callback(body,func(state):state.integrate_forces())
 reset();await step();near(velocity(),Vector3(.06,0,0),"explicit custom integration uses Area gravity")
 PhysicsServer3D.body_set_force_integration_callback(body,Callable())
 PhysicsServer3D.body_set_omit_force_integration(body,false)
 bp(PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,0.0);bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,0);bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP,.5)
 ap(high,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP_OVERRIDE_MODE,3);ap(high,PhysicsServer3D.AREA_PARAM_LINEAR_DAMP,5.0)
 reset(Vector3(10,0,0));await step();near(velocity(),Vector3(9.45,0,0),"replacement field damping before deletion")
 PhysicsServer3D.free_rid(high);owned.erase(high)
 reset(Vector3(10,0,0));await step();near(velocity(),Vector3(9.85,0,0),"deleting field restores actual default damping")
 bp(PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE,1.0);reset();await step();near(velocity(),Vector3(0,-.1,0),"deleting last field restores world gravity")
 # Ordinary World (no authored clock) must use its live default environment.
 space=PhysicsServer3D.space_create();owned.append(space);PhysicsServer3D.space_set_active(space,true);PhysicsServer3D.call("scene_pause",space,true)
 ap(space,PhysicsServer3D.AREA_PARAM_GRAVITY,4.0);ap(space,PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,Vector3.RIGHT)
 body=PhysicsServer3D.body_create();owned.append(body);PhysicsServer3D.body_add_shape(body,ball);PhysicsServer3D.body_set_space(body,space)
 bp(PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,1);bp(PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,1)
 field(0,Vector3.UP*2,0,0)
 PhysicsServer3D.call("scene_pause",space,false);await frames(4);PhysicsServer3D.call("scene_pause",space,true)
 var elapsed:float=PhysicsServer3D.call("scene_info",space).time
 check(elapsed>0,"ordinary World actually advanced")
 near(velocity(),Vector3(4,2,0)*elapsed,"ordinary default World plus Area actual velocity")
 owned.reverse()
 for rid in owned:PhysicsServer3D.free_rid(rid)
 await frames()
 print("AREA_ENVIRONMENT_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(0 if failed==0 else 1)
