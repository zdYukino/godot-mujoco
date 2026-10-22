extends SceneTree
var body:RigidBody3D
var label:Label
var markers:Array[MeshInstance3D]=[]
func _initialize():call_deferred("setup")
func setup():
 var scene=Node3D.new();root.add_child(scene)
 var floor=StaticBody3D.new();floor.position.y=-.5;scene.add_child(floor)
 var floor_shape=CollisionShape3D.new();var box=BoxShape3D.new();box.size=Vector3(8,1,8);floor_shape.shape=box;floor.add_child(floor_shape)
 var ground=MeshInstance3D.new();var ground_mesh=BoxMesh.new();ground_mesh.size=box.size;ground.mesh=ground_mesh;floor.add_child(ground)
 body=RigidBody3D.new();body.position.y=2;body.max_contacts_reported=16;body.contact_monitor=true
 var collision=CollisionShape3D.new();collision.shape=BoxShape3D.new();body.add_child(collision)
 var visual=MeshInstance3D.new();visual.mesh=BoxMesh.new();body.add_child(visual);scene.add_child(body)
 var camera=Camera3D.new();camera.position=Vector3(5,4,6);scene.add_child(camera);camera.look_at(Vector3(0,.5,0));camera.current=true
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-60,-30,0);scene.add_child(light)
 label=Label.new();label.position=Vector2(16,16);root.add_child(label)
 for i in 16:
  var marker=MeshInstance3D.new();var sphere=SphereMesh.new();sphere.radius=.06;sphere.height=.12;marker.mesh=sphere
  var material=StandardMaterial3D.new();material.albedo_color=Color.RED;material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;marker.material_override=material;scene.add_child(marker);markers.append(marker)
func _process(_delta):
 if not is_instance_valid(body):return false
 var state=PhysicsServer3D.body_get_direct_state(body.get_rid());var count=state.get_contact_count()
 label.text="Native MuJoCo contacts: %d | monitored bodies: %d\nRed spheres: reported world contact midpoints\nSpace: drop again" % [count,body.get_colliding_bodies().size()]
 for i in markers.size():
  markers[i].visible=i<count
  if i<count:markers[i].position=state.get_contact_local_position(i)
 if Input.is_physical_key_pressed(KEY_SPACE):body.position=Vector3(0,2,0);body.linear_velocity=Vector3.ZERO
 return false
