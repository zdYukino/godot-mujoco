extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
const World=preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance=preload("res://addons/godot_mujoco/model/model_instance.gd")
func _initialize(): call_deferred("run")
func run():
 var f=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
 f.store_string('<mujoco><compiler angle="radian"/><option timestep=".002"/><worldbody><body name="arm" pos="0 0 1"><joint name="hinge" axis="0 1 0" damping="1" range="-1 1"/><geom name="arm_geom" type="box" size=".1 .1 .3" mass="1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="20" ctrlrange="-.7 .7"/><velocity name="velocity" joint="hinge" kv="2" ctrlrange="-1 1"/></actuator></mujoco>');f.close()
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
 var preset=load("res://addons/mujoco_editor/control_presets.gd").capture(model.open_document().document)
 preset.drives.drive.control=.4;preset.drives.drive.kp=35;preset.drives.drive.kv=3;preset.drives.velocity.control=.2;preset.drives.velocity.kv=4
 f=FileAccess.open("res://good.json",FileAccess.WRITE);f.store_string(JSON.stringify(preset));f.close()
 preset.drives.drive.control=-.5;preset.drives.velocity.kv=0
 f=FileAccess.open("res://bad-last.json",FileAccess.WRITE);f.store_string(JSON.stringify(preset));f.close()
 var gui=load("res://Environment.tscn").instantiate();gui.set_script(load("res://gui.gd"));gui.world_model=model;gui.start_paused=true
 var camera=Camera3D.new();camera.position=Vector3(7,5,10);camera.rotation_degrees=Vector3(-22,30,0);camera.current=true;gui.add_child(camera);camera.owner=gui
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);gui.add_child(light);light.owner=gui
 var status=Label.new();status.name="Status";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.size=Vector2(1100,250);gui.add_child(status);status.owner=gui
 var packed=PackedScene.new();packed.pack(gui);ResourceSaver.save(packed,"res://RuntimePresetDemo.tscn");gui.free()
 print("RUNTIME_PRESET_PREPARE_PASS");quit()
