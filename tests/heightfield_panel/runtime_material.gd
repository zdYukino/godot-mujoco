extends SceneTree
const Terrain=preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Grid=preload("res://addons/godot_mujoco/model/heightfield_data.gd")
const Bridge=preload("res://addons/godot_mujoco/model/heightfield_bridge.gd")
var passed:=0
var failed:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func settle(node:Node,property:String):
 var until=Time.get_ticks_msec()+30000
 while Time.get_ticks_msec()<until:
  await process_frame
  if node.get(property)==0:return
 check(false,"bounded completion")
func run():
 var host=SubViewport.new();host.own_world_3d=true;root.add_child(host)
 # This protocol updates ordinary PhysicsServer worlds. Author worlds route
 # terrain design changes through the editor's atomic layout compilation.
 var authored=load("res://Environment.tscn").instantiate()
 var world=Node3D.new();host.add_child(world)
 var space:RID=world.get_world_3d().space
 PhysicsServer3D.call("scene_pause",space,true)
 check(PhysicsServer3D.call("scene_configure_world",space,authored.world_design.worker_xml()),"ordinary material world configured")
 var model:RID=PhysicsServer3D.call("scene_load_xml",space,authored.get_node("First").design.worker_xml(),{}, {},"material_probe",Transform3D.IDENTITY)
 check(model.is_valid(),"contact model loaded in ordinary world")
 authored.free()
 var terrain=Terrain.new();terrain.auto_apply=false;terrain.design=Grid.new();terrain.physics_material_override=PhysicsMaterial.new();terrain.physics_material_override.friction=.23;world.add_child(terrain)
 check(terrain.request_apply(),"runtime initial material queued");await settle(terrain,"pending_request")
 check(terrain.last_error.is_empty() and is_equal_approx(terrain.state().committed.friction,.23),"runtime initially has old friction .23")
 var file=FileAccess.open("res://panel-material-snapshot.bin",FileAccess.READ);var payload:Dictionary=file.get_var();file.close()
 check(is_equal_approx(payload.friction,.67),"loads actual editor fake-debugger payload")
 var before=terrain.revision
 Bridge.receive("apply",[{"id":terrain.live_id,"revision":before,"snapshot":payload}]);await settle(terrain,"pending_request")
 check(terrain.last_error.is_empty() and terrain.revision==before+1 and is_equal_approx(terrain.state().committed.friction,.67) and is_equal_approx(terrain.physics_material_override.friction,.67) and not terrain.dirty(),"editor payload replaces runtime material .23 with .67")
 var request:int=PhysicsServer3D.call("scene_request_world_command",space,"step",700)
 check(request!=0,"contact steps queued")
 var until=Time.get_ticks_msec()+30000
 var outcome:Dictionary={}
 while outcome.is_empty() and Time.get_ticks_msec()<until:
  await process_frame;outcome=PhysicsServer3D.call("scene_world_command_result",request)
 check(outcome.get("success",false),"contact steps completed")
 var seen=false;var correct=true
 for contact in PhysicsServer3D.call("scene_info",space).contact_details:
  for name in contact.geoms:
   if "arm_geom" in name:
    seen=true;correct=correct and absf(contact.friction-.67)<.001
 check(seen and correct,"editor-to-runtime material reaches actual MJCF contacts")
 host.queue_free();await process_frame;await process_frame
 print("PANEL_MATERIAL_RUNTIME_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(1 if failed else 0)
