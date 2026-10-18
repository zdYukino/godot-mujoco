extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
const SceneBuilder=preload("res://addons/godot_mujoco/model/scene_builder.gd")
func _initialize() -> void: call_deferred("run")
func box(world: Node, name_: String, size_: Vector3, pos: Vector3, friction: float) -> void:
 var body=StaticBody3D.new();body.name=name_;body.position=pos;body.collision_mask=3
 var material=PhysicsMaterial.new();material.friction=friction;body.physics_material_override=material
 var shape=BoxShape3D.new();shape.size=size_
 var collision=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
 var visual=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=size_;visual.mesh=mesh
 var color=StandardMaterial3D.new();color.albedo_color=Color(.7,.4,.15) if name_=="Barrier" else Color(.2,.24,.3);visual.material_override=color;body.add_child(visual)
 world.add_child(body);body.owner=world;collision.owner=world;visual.owner=world
func run() -> void:
 var source: RefCounted=ClassDB.instantiate("MjEditorDocument")
 if not source.import_g1("res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf",true,true):printerr(source.get_error());quit(1);return
 for mode in ["low","high","barrier"]:
  var friction=1.0 if mode=="high" else .001
  var candidate: Dictionary=source.snapshot().duplicate(true)
  var regex=RegEx.new();regex.compile(' friction="[^"]*"')
  candidate.xml=regex.sub(candidate.xml,"",true).replace("<worldbody>",'<default><geom friction="%s .005 .0001"/></default><worldbody>' % friction)
  candidate.state.erase("integration")
  var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
  if not doc.restore(candidate):printerr(doc.get_error());quit(1);return
  var collisions={}
  for e in doc.inspect().entities:
   if e.kind=="geom" and e.properties.contype!=0:collisions[e.name]=e.parent
  var lowest=INF
  for g in doc.geometry():
   if collisions.get(g.name,"").contains("ankle_roll") and g.type==2:lowest=minf(lowest,g.transform.origin.y-g.size.x)
  candidate=doc.snapshot();candidate.state.erase("integration");candidate.state.qpos[2]=.001-lowest;candidate.state.qvel[0]=1.5
  if not doc.restore(candidate):printerr(doc.get_error());quit(1);return
  var package=Builder.pack(doc,"res://models","gui_"+mode)
  if not package.error.is_empty():printerr(package.error);quit(1);return
  var world=SceneBuilder.create(load(package.path));world.start_paused=true
  box(world,"Ground",Vector3(20,.1,20),Vector3(0,-.05,0),friction)
  if mode=="barrier":box(world,"Barrier",Vector3(.1,2,4),Vector3(.55,1,0),friction)
  var camera=Camera3D.new();camera.set_script(preload("res://addons/godot_mujoco/model/orbit_camera.gd"));world.add_child(camera);camera.owner=world
  var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);world.add_child(light);light.owner=world
  var scene=PackedScene.new()
  if scene.pack(world)!=OK or ResourceSaver.save(scene,"res://Contact_"+mode+".tscn")!=OK:quit(1);return
  world.free()
 print("GUI_CONTACT_FIXTURES_PASS")
 quit(0)
