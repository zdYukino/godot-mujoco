extends SceneTree
const Presets=preload("res://addons/mujoco_editor/control_presets.gd")
const Bridge=preload("res://addons/godot_mujoco/model/live_bridge.gd")
var passed:=0
var failed:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func frames(n:int=1):
 for i in n:await process_frame
func finished(node:Node)->Dictionary:
 for i in 300:
  if node.edit_request==0:return node.last_preset_result
  await process_frame
 check(false,"bounded completion");return {}
func run():
 var world=load("res://Environment.tscn").instantiate();root.add_child(world);await frames(5)
 var a=world.get_node("First");var b=world.get_node("Second")
 var document=a.model.open_document().document
 var preset=Presets.capture(document);preset.drives.drive.control=.4;preset.drives.drive.kp=35;preset.drives.drive.kv=3;preset.drives.velocity.control=.2;preset.drives.velocity.kv=4
 var a_before=a.state();var b_before=b.state();var design=a.model.snapshot.duplicate(true)
 check(a.request_control_preset(preset,0) and a.edit_request!=0 and a.last_preset_result.status=="accepted","accepted is queued not completed")
 check(a.state()==a_before and not a.set_control("drive",-.1),"no early writes and pending single control rejected")
 check(not a.request_control_preset(preset,0),"repeat request rejected")
 preset.drives.drive.control=-.6 # Queue snapshot must be copied.
 var result=await finished(a)
 check(result.get("success",false) and result.status=="completed" and result.revision==1,"boundary completion increments revision")
 var state=a.state()
 check(state.controls.drive==.4 and state.controls.velocity==.2 and state.actuator_parameters.drive.gain==35 and state.actuator_parameters.drive.velocity_bias==-3 and state.actuator_parameters.velocity.gain==4,"all targets and PD committed together")
 check(result.state.controls==state.controls and result.state.property_revision==1,"completion snapshot coherent with revision")
 check(state.joints==a_before.joints and b.state()==b_before,"paused compatible joint state and other instance unchanged")
 check(a.model.snapshot==design,"runtime preset leaves design resource untouched")
 check(not a.cancel_control_preset(),"completed request cannot be cancelled as if uncommitted")
 # Subsequent presets validate against current native design, not stale resource cache.
 preset.drives.drive.control=.1
 check(a.request_control_preset(preset,1),"second preset accepted on updated native model")
 result=await finished(a);check(result.get("success",false) and a.state().controls.drive==.1,"normalized gains allow second commit")
 var stable=a.state()
 var bad=preset.duplicate(true);bad.drives.drive.control=.6;bad.drives.velocity.kv=0
 check(a.request_control_preset(bad,2),"invalid candidate still distinguished from queue acceptance")
 result=await finished(a);check(not result.get("success",true) and result.status=="failed" and a.state()==stable,"late invalid gain no partial model/control commit")
 for invalid in ["mapping","range","nan","schema"]:
  bad=preset.duplicate(true)
  match invalid:
   "mapping":bad.mapping="wrong"
   "range":bad.drives.velocity.control=2
   "nan":bad.drives.velocity.control=NAN
   "schema":bad.format="invalid"
  check(a.request_control_preset(bad,2),"queue "+invalid)
  result=await finished(a);check(not result.get("success",true) and a.state()==stable,"atomic rejection "+invalid)
 check(a.request_control_preset(preset,0),"stale revision enqueued")
 result=await finished(a);check(not result.get("success",true) and a.state()==stable and a.property_revision==2,"stale revision preserves state")
 check(a.request_control_preset(preset,2) and a.cancel_control_preset(),"cancel before boundary accepted")
 check(not a.cancel_control_preset(),"repeat cancel cannot fabricate another cancellation")
 result=await finished(a);check(result.status=="cancelled" and a.state()==stable,"cancel outcome no writes")
 check(b.request_control_preset(preset,0) and a.request_control_preset(preset,2),"two instances may independently queue")
 await finished(a);await finished(b)
 check(a.property_revision==3 and b.property_revision==1,"independent instance revisions")
 # Running application resumes prior pause state automatically.
 world.set_paused(false);await frames(3)
 var time_before=world.info().time
 check(a.request_control_preset(preset,3),"running instance queue")
 result=await finished(a)
 check(result.get("success",false) and not world.info().paused and world.info().time>=time_before,"running state restored after safe boundary")
 world.set_paused(true);await frames(2)
 var old_id=a.live_id;var old_rid=a.model_rid
 check(a.request_control_preset(preset,4),"queue before unload")
 a.unload_model();check(a.load_model(),"reloaded node has new instance lifetime");await frames(3)
 var fresh=a.state()
 Bridge.receive("preset",[{"id":old_id,"revision":0,"preset":preset}]);await frames(3)
 check(a.live_id!=old_id and a.model_rid!=old_rid and a.state()==fresh,"old live id cannot affect reloaded instance")
 # Actual bridge dispatch target isolation, including cancellation.
 Bridge.receive("preset",[{"id":a.live_id,"revision":0,"preset":preset}])
 check(a.edit_request!=0 and b.edit_request==0,"bridge targets only selected identity")
 Bridge.receive("cancel_preset",[{"id":a.live_id,"revision":0}]);result=await finished(a)
 check(result.status=="cancelled" and a.state()==fresh,"bridge cancellation remains scoped")
 world.queue_free();await frames(4)
 # Default-state compilation is safe at q=0; the migrated live q=2 is not.
 world=load("res://Dynamics.tscn").instantiate();root.add_child(world);await frames(5)
 a=world.get_node("First");b=world.get_node("Second")
 var numerical=Presets.capture(a.model.open_document().document)
 var numerical_before=a.state();var other_before=b.state();var clock_before=world.info()
 check(numerical_before.joints.slide.qpos[0]==2 and clock_before.paused,"slide reproducer starts paused at live qpos2")
 for gain in [1e308,1e12]:
  numerical.drives.drive.kp=gain;numerical.drives.drive.kv=0;numerical.drives.drive.control=0
  check(a.request_control_preset(numerical,0),"finite high gain queued "+str(gain))
  result=await finished(a)
  check(not result.get("success",true) and str(result.get("error","")).contains("candidate dynamics"),"unsafe migrated dynamics rejected "+str(gain))
  check(a.state()==numerical_before and b.state()==other_before and a.property_revision==0,"failure preserves full live state PD controls revision and other instance")
  check(world.info().paused and world.info().time==clock_before.time and world.info().warning_count==clock_before.warning_count,"failure preserves pause clock and active warning counters")
 check(world.step_simulation(10),"step preserved original after rejection")
 for i in 300:
  if world.info().time>clock_before.time:break
  await process_frame
 check(absf(a.state().joints.slide.qpos[0]-2)<1e-10 and world.info().warning_count==clock_before.warning_count,"next step keeps qpos2 without bad QACC warning or reset")
 numerical.drives.drive.kp=30;numerical.drives.drive.control=2
 check(a.request_control_preset(numerical,0),"safe retry accepted after dynamics failure")
 result=await finished(a);check(result.get("success",false) and a.property_revision==1 and a.state().actuator_parameters.drive.gain==30,"safe retry commits once")
 world.queue_free();await frames(4)
 print("RUNTIME_PRESET_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(0 if failed==0 else 1)
