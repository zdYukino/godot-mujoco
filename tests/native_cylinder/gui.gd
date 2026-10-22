extends Node3D
func cylinder(body:PhysicsBody3D,position_value:Vector3,radius:float,height:float):
 body.position=position_value
 var collision=CollisionShape3D.new();var shape=CylinderShape3D.new();shape.radius=radius;shape.height=height;collision.shape=shape;body.add_child(collision)
 var visual=MeshInstance3D.new();var mesh=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;visual.mesh=mesh;body.add_child(visual);add_child(body)
func _ready():
 var floor=StaticBody3D.new();var collision=CollisionShape3D.new();collision.shape=WorldBoundaryShape3D.new();floor.add_child(collision);add_child(floor)
 var surface=MeshInstance3D.new();surface.mesh=PlaneMesh.new();surface.mesh.size=Vector2(12,12);add_child(surface)
 cylinder(StaticBody3D.new(),Vector3(-2,.6,0),1.2,1.2)
 cylinder(RigidBody3D.new(),Vector3(2,3,0),.5,1.4)
 var box=RigidBody3D.new();box.position=Vector3(-2,3,0);collision=CollisionShape3D.new();collision.shape=BoxShape3D.new();collision.shape.size=Vector3.ONE*.4;box.add_child(collision)
 var visual=MeshInstance3D.new();visual.mesh=BoxMesh.new();visual.mesh.size=Vector3.ONE*.4;box.add_child(visual);add_child(box)
 var camera=Camera3D.new();camera.position=Vector3(8,6,10);add_child(camera);camera.look_at(Vector3.ZERO);camera.current=true
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);add_child(light)
 var label=Label.new();label.text="原生 CylinderShape3D：左侧静态圆柱接住 box；右侧圆柱刚体落地。R 重置。";add_child(label)
func _unhandled_key_input(event):
 if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_R:get_tree().reload_current_scene()
