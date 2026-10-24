extends SceneTree
var body:RigidBody3D
var label:Label
var scene:Node3D
func _initialize():call_deferred("setup")
func setup():
 scene=Node3D.new();root.add_child(scene)
 for i in 2:
  var a=Area3D.new();a.priority=i*10;a.gravity_space_override=Area3D.SPACE_OVERRIDE_REPLACE;a.gravity=1+i;a.gravity_direction=Vector3.RIGHT if i==0 else Vector3.UP
  a.linear_damp_space_override=Area3D.SPACE_OVERRIDE_REPLACE;a.linear_damp=.5
  var c=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3.ONE*(8 if i==0 else 3);c.shape=shape;a.add_child(c);scene.add_child(a)
  var v=MeshInstance3D.new();var box=BoxMesh.new();box.size=shape.size;v.mesh=box
  var material=StandardMaterial3D.new();material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.2,.4,1,.1) if i==0 else Color(1,.4,.2,.25);v.material_override=material;a.add_child(v)
 body=RigidBody3D.new();var c=CollisionShape3D.new();c.shape=SphereShape3D.new();body.add_child(c);var mesh=MeshInstance3D.new();mesh.mesh=SphereMesh.new();body.add_child(mesh);scene.add_child(body)
 var cam=Camera3D.new();cam.position=Vector3(10,7,12);scene.add_child(cam);cam.look_at(Vector3.ZERO);cam.current=true
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-60,-30,0);scene.add_child(light)
 label=Label.new();label.position=Vector2(16,16);root.add_child(label)
func _process(_dt):
 if not is_instance_valid(body):return false
 var state=PhysicsServer3D.body_get_direct_state(body.get_rid())
 label.text="Orange priority 10: gravity UP 2; blue priority 0: RIGHT 1\nGravity: %s | velocity: %s | damping: %.2f\nSpace resets the body; outside both Areas uses World gravity." % [state.total_gravity,body.linear_velocity,state.total_linear_damp]
 if Input.is_physical_key_pressed(KEY_SPACE):body.position=Vector3.ZERO;body.linear_velocity=Vector3.ZERO
 return false
