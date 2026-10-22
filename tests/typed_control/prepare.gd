extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
const World=preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance=preload("res://addons/godot_mujoco/model/model_instance.gd")
func _initialize(): call_deferred("run")
func run():
 var f=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
 f.store_string('<mujoco><option timestep=".002"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0" damping="1" range="-1 1"/><geom name="arm_geom" type="box" size=".1 .1 .3" mass="1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="20"/></actuator></mujoco>');f.close()
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
 print("TYPED_PREPARE_PASS");quit()
