@tool
extends RefCounted
var passed:=0
var failed:=0
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func run(plugin):
 var bridge=plugin.live_debugger;var panel=plugin.panel
 var a={"id":"A","path":"/World/A","revision":1,"resource":"res://a.tres","pending":false,"error":"","preset":{"status":"completed","request":10}}
 var b={"id":"B","path":"/World/B","revision":0,"resource":"res://b.tres","pending":true,"error":"","preset":{"status":"accepted","request":11}}
 bridge._capture("mujoco_live:instance",[a],0);bridge._capture("mujoco_live:instance",[b],1)
 panel.runtime_target_key="0:A";panel.refresh_runtime_targets();check(panel.runtime_status.text.contains("completed #10"),"A completion displayed")
 panel.runtime_target_key="1:B";panel.refresh_runtime_targets();check(panel.runtime_status.text.contains("accepted #11") and not panel.runtime_status.text.contains("completed"),"B pending does not inherit A outcome")
 a.error="invalid final gain";a.preset={"status":"failed","request":12};bridge._capture("mujoco_live:instance",[a],0)
 check(not panel.runtime_status.text.contains("invalid final gain"),"unselected failure stays isolated")
 panel.runtime_target_key="0:A";panel.refresh_runtime_targets();check(panel.runtime_status.text.contains("failed #12") and panel.runtime_status.text.contains("invalid final gain"),"switch refreshes scoped failure")
 b.pending=false;b.preset={"status":"cancelled","request":11};bridge._capture("mujoco_live:instance",[b],1)
 panel.runtime_target_key="1:B";panel.refresh_runtime_targets();check(panel.runtime_status.text.contains("cancelled #11"),"cancel has explicit outcome")
 b.preset={};bridge._capture("mujoco_live:instance",[b],1);check(not panel.runtime_status.text.contains("Preset"),"no outcome clears stale suffix")
 bridge.session_stopped(0);bridge.session_stopped(1);panel.refresh_runtime_targets()
 check(panel.runtime_target_key.is_empty() and not panel.runtime_status.text.contains("cancelled"),"stop clears scoped results")
 var report={"passed":passed,"failed":failed}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="):var f=FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE);f.store_string(JSON.stringify(report))
 print("RUNTIME_PRESET_EDITOR_RESULT ",JSON.stringify(report));plugin.get_tree().quit(0 if failed==0 else 1)
