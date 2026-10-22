extends SceneTree
var detector:Area3D
var moving:RigidBody3D
var label:Label
var entered:=0
var exited:=0
func _initialize():call_deferred("setup")
func setup():
 var scene=Node3D.new();root.add_child(scene)
 detector=Area3D.new();var shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(3,3,3);shape.shape=box;detector.add_child(shape);scene.add_child(detector)
 detector.body_entered.connect(func(_b):entered+=1)
 detector.body_exited.connect(func(_b):exited+=1)
 var visual=MeshInstance3D.new();var mesh=BoxMesh.new();mesh.size=box.size;visual.mesh=mesh
 var material=StandardMaterial3D.new();material.albedo_color=Color(.2,.6,1,.2);material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;visual.material_override=material;detector.add_child(visual)
 moving=RigidBody3D.new();moving.gravity_scale=0;moving.linear_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;moving.linear_damp=0;moving.position.x=-4;moving.linear_velocity=Vector3(2,0,0)
 var collision=CollisionShape3D.new();var sphere=SphereShape3D.new();sphere.radius=.4;collision.shape=sphere;moving.add_child(collision)
 var ball=MeshInstance3D.new();var ball_mesh=SphereMesh.new();ball_mesh.radius=.4;ball_mesh.height=.8;ball.mesh=ball_mesh;moving.add_child(ball);scene.add_child(moving)
 var camera=Camera3D.new();camera.position=Vector3(7,5,9);scene.add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-60,-30,0);scene.add_child(light)
 label=Label.new();label.position=Vector2(16,16);root.add_child(label)
func _process(_dt):
 if not is_instance_valid(moving):return false
 if moving.position.x>4:moving.position.x=-4
 label.text="Area trigger (blue): %d bodies\nEnter: %d | Exit: %d | Velocity X: %.3f m/s\nSphere crosses the trigger without impulse." % [detector.get_overlapping_bodies().size(),entered,exited,moving.linear_velocity.x]
 return false
