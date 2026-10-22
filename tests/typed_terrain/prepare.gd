extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
const World=preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance=preload("res://addons/godot_mujoco/model/model_instance.gd")
func _initialize(): call_deferred("run")
func run():
 var f=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
 f.store_string('<mujoco><option timestep=".002"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" type="slide" axis="0 0 1" damping="0" range="-2 2"/><geom name="arm_geom" type="sphere" size=".1" mass="1"/></body></worldbody><actuator><motor name="drive" joint="hinge"/></actuator></mujoco>');f.close()
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument")
 assert(doc.import_file("res://fixture.xml"))
 var package=Builder.pack(doc,"res://models","typed");assert(package.error.is_empty())
 var model=load(package.path)
 var world=World.new();world.name="Environment";world.world_model=model;world.start_paused=true
 for n in 2:
  var instance=Instance.new();instance.name="First" if n==0 else "Second";instance.model=model;instance.position.x=n*2.0
  world.add_child(instance);instance.owner=world
 var box=RigidBody3D.new();box.name="Box";box.position=Vector3(4,2,0)
 var shape=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3.ONE*.4;box.add_child(shape)
 world.add_child(box);box.owner=world;shape.owner=world
 var floor=StaticBody3D.new();floor.name="Floor";shape=CollisionShape3D.new();shape.shape=WorldBoundaryShape3D.new();floor.add_child(shape);world.add_child(floor);floor.owner=world;shape.owner=world
 var scene=PackedScene.new();assert(scene.pack(world)==OK);assert(ResourceSaver.save(scene,"res://Environment.tscn")==OK);world.free()
 assert(doc.edit({"op":"set","kind":"body","name":"arm","values":{"mass":2.0}}))
 package=Builder.pack(doc,"res://models","edited");assert(package.error.is_empty())
 f=FileAccess.open("res://edited.txt",FileAccess.WRITE);f.store_string(package.path);f.close()
 var gui=load("res://Environment.tscn").instantiate();gui.get_node("Floor").free();gui.set_script(load("res://gui.gd"));gui.world_model=model;gui.start_paused=false
 var terrain=load("res://addons/godot_mujoco/model/static_heightfield.gd").new();terrain.name="Terrain"
 var grid=load("res://addons/godot_mujoco/model/heightfield_data.gd").new();grid.width=11;grid.depth=11;grid.heights.resize(121);grid.heights.fill(.3);grid.heights[0]=1.2;terrain.design=grid;gui.add_child(terrain);terrain.owner=gui
 var camera=Camera3D.new();camera.position=Vector3(9,8,12);camera.rotation_degrees=Vector3(-28,36,0);camera.current=true;gui.add_child(camera);camera.owner=gui
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);gui.add_child(light);light.owner=gui
 var visual=MeshInstance3D.new();visual.mesh=BoxMesh.new();visual.mesh.size=Vector3.ONE*.4;gui.get_node("Box").add_child(visual);visual.owner=gui
 var label=Label.new();label.name="Status";gui.add_child(label);label.owner=gui
 var demo=PackedScene.new();assert(demo.pack(gui)==OK);assert(ResourceSaver.save(demo,"res://HeightfieldDemo.tscn")==OK);gui.free()
 print("HEIGHTFIELD_PREPARE_PASS");quit()
