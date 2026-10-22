extends SceneTree
var scene:Node3D
var passed:=0
var failed:=0
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func ticks(n:int):
 for i in n:
  await physics_frame
  await process_frame
func ray(a:Vector3,b:Vector3,mask:int=1,exclude:Array[RID]=[],inside:bool=false)->Dictionary:
 var q=PhysicsRayQueryParameters3D.create(a,b,mask,exclude);q.hit_from_inside=inside
 return scene.get_world_3d().direct_space_state.intersect_ray(q)
func cylinder(body:PhysicsBody3D,r:float,h:float)->CollisionShape3D:
 var c=CollisionShape3D.new();var s=CylinderShape3D.new();s.radius=r;s.height=h;c.shape=s;c.name="Collision";body.add_child(c);scene.add_child(body);return c
func run():
 scene=Node3D.new();root.add_child(scene)
 check(PhysicsServer3D.get_class()=="MjPhysicsServer3D","native backend")
 var obstacle=StaticBody3D.new();obstacle.position=Vector3(2,2,-3)
 var shape=cylinder(obstacle,.7,2.4)
 await ticks(3)
 check(PhysicsServer3D.shape_get_type(shape.shape.get_rid())==PhysicsServer3D.SHAPE_CYLINDER,"real CylinderShape3D RID")
 var data:Dictionary=PhysicsServer3D.shape_get_data(shape.shape.get_rid())
 check(is_equal_approx(data.height,2.4) and is_equal_approx(data.radius,.7),"full height and radius data")
 data.height=99
 check(is_equal_approx(PhysicsServer3D.shape_get_data(shape.shape.get_rid()).height,2.4),"getter cannot mutate stored dimensions")
 var center=obstacle.position
 for normal in [Vector3.UP,Vector3.DOWN,Vector3.RIGHT,Vector3.BACK]:
  var distance=1.2 if normal.y!=0 else .7
  var hit=ray(center+normal*3,center)
  check(hit.get("collider")==obstacle and hit.get("rid")==obstacle.get_rid() and hit.get("shape")==0,"cap/side identity "+str(normal))
  check(hit.get("position",Vector3.INF).distance_to(center+normal*distance)<.001,"cap/side position "+str(normal))
  check(hit.get("normal",Vector3.ZERO).dot(normal)>.999,"cap/side normal "+str(normal))
 check(ray(center,center+Vector3.UP*3).is_empty(),"inside default miss")
 var hit=ray(center,center+Vector3.UP*3,1,[],true)
 check(hit.get("collider")==obstacle and hit.get("normal")==Vector3.ZERO and hit.get("position")==center,"inside explicit zero normal")
 check(ray(center+Vector3.UP*3,center,1,[obstacle.get_rid()]).is_empty(),"ray exclusion")
 obstacle.collision_layer=2;obstacle.collision_mask=0;await ticks(2)
 check(ray(center+Vector3.UP*3,center).is_empty() and ray(center+Vector3.UP*3,center,2).get("collider")==obstacle,"layer filter independent of target mask")
 obstacle.collision_layer=1;obstacle.collision_mask=1
 obstacle.rotation=Vector3(.2,.3,.4);shape.rotation=Vector3(.3,-.1,.2);shape.position=Vector3(.2,.4,-.3);await ticks(2)
 var normal=shape.global_basis*Vector3.UP;var surface=shape.global_transform*Vector3(0,1.2,0)
 hit=ray(surface+normal*2,surface-normal)
 check(hit.get("collider")==obstacle and hit.get("position",Vector3.INF).distance_to(surface)<.001 and hit.get("normal",Vector3.ZERO).dot(normal)>.999,"combined body and shape rigid pose")
 shape.shape.height=3.0;shape.shape.radius=.9;await ticks(2)
 surface=shape.global_transform*Vector3(0,1.5,0)
 check(ray(surface+normal*2,surface-normal).get("position",Vector3.INF).distance_to(surface)<.001,"resource resize rebuild")
 shape.disabled=true;await ticks(2)
 check(ray(surface+normal*2,surface-normal).is_empty(),"disabled cylinder absent")
 shape.disabled=false;await ticks(2)
 check(ray(surface+normal*2,surface-normal).get("collider")==obstacle,"reenabled cylinder present")
 # Serialize actual native shape, then reload a distinct body.
 obstacle.owner=scene;shape.owner=obstacle
 var packed=PackedScene.new();check(packed.pack(obstacle)==OK and ResourceSaver.save(packed,"res://CylinderSaved.tscn")==OK,"save native cylinder")
 var reopened=load("res://CylinderSaved.tscn").instantiate();reopened.position.x+=10;scene.add_child(reopened);await ticks(2)
 var reopened_shape=reopened.get_node("Collision")
 check(is_equal_approx(reopened_shape.shape.radius,.9) and is_equal_approx(reopened_shape.shape.height,3),"reload shape dimensions")
 var p=reopened_shape.global_transform*Vector3(0,1.5,0)
 check(ray(p+normal*2,p-normal).get("collider")==reopened,"reload native collision")
 obstacle.queue_free();reopened.queue_free();await ticks(3)
 check(ray(surface+normal*2,surface-normal).is_empty(),"removed cylinders absent")
 var floor=StaticBody3D.new();var floor_shape=CollisionShape3D.new();floor_shape.shape=WorldBoundaryShape3D.new();floor.add_child(floor_shape);scene.add_child(floor)
 var falling=RigidBody3D.new();falling.position=Vector3(0,3,0);falling.mass=4
 var falling_shape=cylinder(falling,.5,1.4)
 await ticks(180)
 check(absf(falling.position.y-.7)<.04 and falling.linear_velocity.length()<.1,"rigid cylinder rests on plane")
 var state=PhysicsServer3D.body_get_direct_state(falling.get_rid())
 check(absf(state.inverse_mass-.25)<.001,"cylinder mass")
 # Solid cylinder I_y = mr^2/2, I_x=I_z=m(3r^2+h^2)/12.
 var inv=state.inverse_inertia
 check(absf(inv.y-2)<.02 and absf(inv.x-12.0/(4*(.75+1.96)))<.02,"automatic cylinder inertia")
 falling.gravity_scale=0;falling.position=Vector3(0,4,0);falling.linear_velocity=Vector3(1,0,0);await ticks(2)
 var before=falling.position;falling_shape.shape.radius=.6;await ticks(2)
 check(falling.position.x>before.x and falling.linear_velocity.x>.99 and absf(falling.position.y-before.y)<.01,"resize preserves live pose velocity")
 falling.queue_free();await ticks(2)
 # Ordinary box rests on a static cylinder obstacle, independent native body types.
 var pedestal=StaticBody3D.new();pedestal.position=Vector3(0,.6,0);cylinder(pedestal,1.2,1.2)
 var box=RigidBody3D.new();box.position=Vector3(0,3,0);var c=CollisionShape3D.new();var box_shape=BoxShape3D.new();box_shape.size=Vector3.ONE*.4;c.shape=box_shape;box.add_child(c);scene.add_child(box)
 await ticks(180)
 check(absf(box.position.y-1.4)<.04,"box contacts static cylinder")
 # Multiple-shape indices remain native Godot indices.
 var second=CollisionShape3D.new();second.shape=CylinderShape3D.new();second.position=Vector3(4,0,0);pedestal.add_child(second);await ticks(2)
 check(ray(Vector3(4,4,0),Vector3(4,.6,0)).get("shape")==1,"second cylinder shape index")
 pedestal.remove_child(second);second.free();await ticks(2)
 check(ray(Vector3(4,4,0),Vector3(4,.6,0)).is_empty(),"removed shape absent")
 scene.queue_free();await ticks(3)
 print("CYLINDER_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(0 if failed==0 else 1)
