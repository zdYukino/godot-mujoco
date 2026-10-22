extends SceneTree
# Input callbacks belong to Nodes, not SceneTree/MainLoop.
class DemoInput extends Node:
 var receiver:Callable
 func _input(event:InputEvent):receiver.call(event)
var scene:Node3D
var bob:RigidBody3D
var pin_node:PinJoint3D
var status:Label
var world:RID
var world_paused:=false
var request:=0
var last_step_result:Dictionary={}
func _initialize():call_deferred("setup")
func setup():
 var input_node=DemoInput.new();input_node.name="DemoInput";input_node.receiver=_handle_input;root.add_child(input_node)
 scene=Node3D.new();scene.name="PinDemo";root.add_child(scene);world=scene.get_world_3d().space
 PhysicsServer3D.call("scene_pause",world,true)
 var file=FileAccess.open("res://gui_world.xml",FileAccess.WRITE);file.store_string('<mujoco><option timestep=".01"/><worldbody/></mujoco>');file.close()
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument");doc.import_file("res://gui_world.xml")
 PhysicsServer3D.call("scene_configure_model",world,doc.snapshot(),"res://")
 bob=RigidBody3D.new();bob.name="Bob";bob.position=Vector3(0,1,0)
 var collider=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.6,.8,.5);collider.shape=shape;bob.add_child(collider)
 var mesh=MeshInstance3D.new();var box=BoxMesh.new();box.size=shape.size;mesh.mesh=box;bob.add_child(mesh);scene.add_child(bob)
 var marker=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=.07;sphere.height=.14;marker.mesh=sphere;marker.position=Vector3(0,2,0);scene.add_child(marker)
 var camera=Camera3D.new();camera.position=Vector3(4,3,6);scene.add_child(camera);camera.look_at(Vector3(0,1,0));camera.current=true
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-20,0);scene.add_child(light)
 status=Label.new();status.position=Vector2(16,16);root.add_child(status)
 make_pin();bob.apply_central_impulse(Vector3(1,0,.3));PhysicsServer3D.call("scene_pause",world,false)
func make_pin():
 pin_node=PinJoint3D.new();pin_node.name="WorldPin";pin_node.position=Vector3(0,2,0);pin_node.node_a=NodePath("../Bob");scene.add_child(pin_node)
func reset():
 PhysicsServer3D.call("scene_pause",world,true)
 if is_instance_valid(pin_node):pin_node.free()
 bob.transform=Transform3D(Basis.IDENTITY,Vector3(0,1,0));bob.linear_velocity=Vector3.ZERO;bob.angular_velocity=Vector3.ZERO
 make_pin();bob.apply_central_impulse(Vector3(1,0,.3));PhysicsServer3D.call("scene_pause",world,world_paused)
func own_children(node:Node):
 for child in node.get_children():child.owner=scene;own_children(child)
func _process(_delta):
 if not is_instance_valid(bob):return false
 if request:
  var result:Dictionary=PhysicsServer3D.call("scene_world_command_result",request)
  if not result.is_empty():last_step_result=result;request=0
 status.text="Native Pin: free rotation, soft positional constraint\nP pause/resume | S exact .01s step | C remove joint | R reset/re-add | W save scene\nPaused: %s | Joint: %s | World anchor error: %.5f m"%[world_paused,is_instance_valid(pin_node),(bob.global_transform*Vector3.UP).distance_to(Vector3(0,2,0))]
 return false
func _handle_input(event):
 if not event is InputEventKey or not event.pressed or event.echo:return
 match event.physical_keycode:
  KEY_P:world_paused=not world_paused;PhysicsServer3D.call("scene_pause",world,world_paused)
  KEY_S:
   if world_paused and not request:last_step_result={};request=PhysicsServer3D.call("scene_request_world_command",world,"step",1)
  KEY_C:
   if is_instance_valid(pin_node):pin_node.free()
  KEY_R:reset()
  KEY_W:
   own_children(scene);var packed=PackedScene.new()
   if packed.pack(scene)==OK:print("Saved Pin scene: ",ResourceSaver.save(packed,"res://SavedPin.tscn"))
