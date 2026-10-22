extends "res://gui.gd"
var input_checks:=0
var input_failed:=0
func _initialize():call_deferred("run_input_smoke")
func verify(ok:bool,label:String):
 input_checks+=1
 if not ok:input_failed+=1
 print("PASS " if ok else "FAIL ",label)
func send_key(key:int,pressed:bool=true,echo_event:bool=false):
 var event=InputEventKey.new();event.physical_keycode=key;event.keycode=key;event.pressed=pressed;event.echo=echo_event
 # Traverse the real Viewport -> Node input dispatch, never call the handler.
 root.push_input(event)
func run_input_smoke():
 setup();await process_frame
 verify(not world_paused,"demo begins running")
 send_key(KEY_P);verify(world_paused and PhysicsServer3D.call("scene_info",world).paused,"P routes through input Node and pauses")
 send_key(KEY_P,true,true);send_key(KEY_P,false);verify(world_paused,"echo and key release do not toggle")
 var before:float=PhysicsServer3D.call("scene_info",world).time
 send_key(KEY_S);var queued:int=request;send_key(KEY_S)
 verify(queued>0 and request==queued,"S queues once while pending")
 var result:Dictionary={}
 for i in 40:
  await physics_frame;await process_frame
  result=last_step_result
  if not result.is_empty():break
 verify(result.get("success",false),"key-triggered exact step completes")
 verify(abs(float(PhysicsServer3D.call("scene_info",world).time)-before-.01)<1e-7,"duplicate S advances exactly .01s")
 send_key(KEY_C);send_key(KEY_C);verify(not is_instance_valid(pin_node),"C removes joint and repeat is safe")
 send_key(KEY_R);send_key(KEY_R);verify(is_instance_valid(pin_node) and world_paused,"R re-adds joint preserving pause")
 send_key(KEY_W)
 var saved=load("res://SavedPin.tscn") as PackedScene
 verify(saved!=null,"W saves a loadable PackedScene")
 if saved:
  var reopened=saved.instantiate();verify(reopened.get_node_or_null("WorldPin")!=null,"saved scene retains joint node");reopened.free()
 send_key(KEY_P);verify(not world_paused and not PhysicsServer3D.call("scene_info",world).paused,"P resumes")
 print("DEMO_INPUT_RESULT ",JSON.stringify({"passed":input_checks-input_failed,"failed":input_failed}))
 quit(0 if input_failed==0 else 1)
