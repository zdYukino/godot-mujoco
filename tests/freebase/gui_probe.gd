extends SceneTree
# 仅测试夹具：真实输入驱动产品控件；每帧观测模型与接触，不直接改 step 中的数据。
var scene: Node
var host: Node
var controls_: Node
var folder=""
var contact_seen=false
var barrier_seen=false
var deepest=0.0
var serial=0
var menu: HBoxContainer
var old_world=0
var start_x=0.0
func _initialize() -> void:call_deferred("run")
func run() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--probe-dir="):folder=arg.trim_prefix("--probe-dir=")
 scene=load("res://FreebasePlayground.tscn").instantiate();root.add_child(scene)
 host=scene.get_node("EnvironmentHost");controls_=scene.get_node("SimulationControls")
 var overlay=CanvasLayer.new();scene.add_child(overlay)
 menu=HBoxContainer.new();menu.position=Vector2(10,10);overlay.add_child(menu)
 for mode in ["low","high","barrier","invalid","original"]:
  var b=Button.new();b.text="Fixture "+mode;menu.add_child(b)
  b.pressed.connect(func():
   if mode=="invalid":
    var bad=Node.new();var packed=PackedScene.new();packed.pack(bad);bad.free();host.environment_scene=packed
   else:host.environment_scene=load("res://FreebaseEnvironment.tscn" if mode=="original" else "res://Contact_"+mode+".tscn"))
 process_frame.connect(tick)
func rect(c: Control) -> Array:
 var p=c.get_screen_transform().origin;return [p.x,p.y,c.size.x,c.size.y]
func tick() -> void:
 if not is_instance_valid(host.world) or not host.world.ready_for_models:return
 var world=host.world;var robot=world.get_node("Model");var st: Dictionary=robot.state();var info: Dictionary=world.info()
 if not st.has("joints"):return
 var q=st.joints.floating_base.qpos
 if world.get_instance_id()!=old_world:
  old_world=world.get_instance_id();start_x=q[0];contact_seen=false;barrier_seen=false;deepest=0
 for contact in info.contact_details:
  deepest=minf(deepest,contact.distance)
  for body in contact.bodies:
   if body.contains("ankle_roll"):contact_seen=true
 if world.has_node("Barrier"):
  for pair in info.contacts:
   if pair.has(world.get_node("Barrier").get_rid()) and pair.has(robot.model_rid):barrier_seen=true
 var buttons=[]
 for node in [controls_,menu]:
  for c in node.get_children():
   if c is Button:buttons.append({"text":c.text,"rect":rect(c)})
 var finite=true
 for j in st.joints.values():
  for v in j.qpos:finite=finite and is_finite(v)
  for v in j.qvel:finite=finite and is_finite(v)
 var result={"seq":serial,"time":info.time,"paused":info.paused,"game_elapsed":controls_.game_elapsed,"world_id":old_world,"qpos":q,"travel":q[0]-start_x,"contact_seen":contact_seen,"barrier_seen":barrier_seen,"deepest":deepest,"finite":finite,"warnings":info.warning_count,"status":controls_.status.text,"controls":buttons,"count":rect(controls_.count.get_line_edit())}
 serial+=1
 var f=FileAccess.open(folder.path_join("state.tmp"),FileAccess.WRITE);f.store_string(JSON.stringify(result));f.close();DirAccess.rename_absolute(folder.path_join("state.tmp"),folder.path_join("state.json"))
 if FileAccess.file_exists(folder.path_join("quit")):
  scene.queue_free();await process_frame;print("FREEBASE_GUI_PROBE_FINISHED");quit(0)
