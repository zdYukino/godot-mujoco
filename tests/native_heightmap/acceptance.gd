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
func ray(p:Vector3,n:Vector3=Vector3.UP)->Dictionary:
 return scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+n*3,p-n*3))
func run():
 scene=Node3D.new();root.add_child(scene)
 var body=StaticBody3D.new();body.name="Terrain";scene.add_child(body)
 var c=CollisionShape3D.new();c.name="Collision";var h=HeightMapShape3D.new()
 h.map_width=3;h.map_depth=2;h.map_data=PackedFloat32Array([0,1,2,3,4,5]);c.shape=h;body.add_child(c)
 body.physics_material_override=PhysicsMaterial.new();body.physics_material_override.friction=.23
 await ticks(3)
 check(PhysicsServer3D.shape_get_type(h.get_rid())==PhysicsServer3D.SHAPE_HEIGHTMAP,"native heightmap RID")
 for z in 2:
  for x in 3:
   var p=Vector3(x-1,x+z*3,z-.5)
   check(ray(p).get("position",Vector3.INF).distance_to(p)<.001,"asymmetric sample "+str(x)+","+str(z))
 var hit=ray(Vector3(0,2.5,0))
 check(hit.get("collider")==body and hit.get("rid")==body.get_rid() and hit.get("shape")==0,"ray identity")
 var data:Dictionary=PhysicsServer3D.shape_get_data(h.get_rid());data.heights[0]=999
 check(PhysicsServer3D.shape_get_data(h.get_rid()).heights[0]==0,"defensive data copy")
 body.position=Vector3(4,2,-3);body.rotation=Vector3(.2,.3,.1);c.position=Vector3(.2,.3,.4);c.rotation=Vector3(.1,-.1,.2)
 await ticks(3)
 var p=c.global_transform*Vector3(0,2.5,0);var normal=c.global_basis*Vector3.UP
 check(ray(p,normal).get("position",Vector3.INF).distance_to(p)<.001,"combined rigid transforms")
 h.map_data=PackedFloat32Array([1,1,1,1,1,1]);await ticks(3)
 p=c.global_transform*Vector3(0,1,0)
 check(ray(p,normal).get("position",Vector3.INF).distance_to(p)<.001,"flat edited grid rebuild")
 h.map_depth=3;h.map_data=PackedFloat32Array([1,1,1,1,1,1,1,1,1]);await ticks(3)
 check(ray(p,normal).get("collider")==body,"resolution change")
 c.disabled=true;await ticks(2);check(ray(p,normal).is_empty(),"disable")
 c.disabled=false;await ticks(2);check(ray(p,normal).get("collider")==body,"reenable")
 c.owner=body
 var packed=PackedScene.new();check(packed.pack(body)==OK and ResourceSaver.save(packed,"res://TerrainSaved.tscn")==OK,"save")
 var reopened=load("res://TerrainSaved.tscn").instantiate();reopened.position.x+=10;scene.add_child(reopened);await ticks(3)
 var rc=reopened.get_node("Collision");p=rc.global_transform*Vector3(0,1,0)
 check(rc.shape.map_data==h.map_data and rc.shape.map_depth==3,"reopen grid")
 check(is_equal_approx(reopened.physics_material_override.friction,.23) and ray(p,normal).get("collider")==reopened,"reopen material and collision")
 # A second collision shape sharing the same resource has independent pose and shape index.
 var shared=CollisionShape3D.new();shared.shape=h;shared.position=Vector3(8,0,0);body.add_child(shared);await ticks(3)
 p=shared.global_transform*Vector3(0,1,0);normal=shared.global_basis*Vector3.UP
 hit=ray(p,normal)
 check(hit.get("collider")==body and hit.get("shape")==1,"shared resource compound shape index")
 h.map_data=PackedFloat32Array([2,2,2,2,2,2,2,2,2]);await ticks(3)
 p=shared.global_transform*Vector3(0,2,0)
 check(ray(p,normal).get("position",Vector3.INF).distance_to(p)<.001,"shared resource update")
 body.queue_free();reopened.queue_free();await ticks(3)
 check(ray(p,normal).is_empty(),"removed heightmaps absent")
 # Flat, wide ordinary terrain: inspect actual MuJoCo contact friction before/after material edits.
 body=StaticBody3D.new();c=CollisionShape3D.new();h=HeightMapShape3D.new();h.map_width=9;h.map_depth=9;c.shape=h;body.add_child(c);scene.add_child(body)
 var material=PhysicsMaterial.new();material.friction=.23;body.physics_material_override=material
 var ball=RigidBody3D.new();ball.position.y=2;var sphere=CollisionShape3D.new();sphere.shape=SphereShape3D.new();ball.add_child(sphere);scene.add_child(ball)
 await ticks(180)
 check(absf(ball.position.y-.5)<.03,"rigid contact rests on terrain")
 var info:Dictionary=PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
 check(not info.contact_details.is_empty() and absf(info.contact_details[0].friction-.23)<.001,"material friction in compiled contacts")
 material.friction=.67;await ticks(20)
 info=PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
 check(not info.contact_details.is_empty() and absf(info.contact_details[0].friction-.67)<.001,"material changed signal rebuild")
 material.rough=true;var other=PhysicsMaterial.new();other.friction=.1;ball.physics_material_override=other;await ticks(20)
 info=PhysicsServer3D.call("scene_info",scene.get_world_3d().space)
 check(not info.contact_details.is_empty() and absf(info.contact_details[0].friction-.67)<.001,"rough combination preserved")
 # Verify observable sliding, not only reported parameters. Identical box and initial velocity.
 ball.queue_free();await ticks(3)
 var box=RigidBody3D.new();var bc=CollisionShape3D.new();var bs=BoxShape3D.new();bs.size=Vector3(.5,.5,.5);bc.shape=bs;box.add_child(bc)
 box.position=Vector3(-1,.25,0);box.linear_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;box.linear_damp=0;box.angular_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;box.angular_damp=0;scene.add_child(box)
 material.rough=false;material.friction=0;await ticks(30)
 box.linear_velocity=Vector3(1.5,0,0);var start=box.position.x;await ticks(30)
 var smooth_distance=box.position.x-start
 var smooth_speed=box.linear_velocity.x
 check(smooth_distance>.65 and smooth_speed>1.3,"zero friction retains sliding speed")
 box.position=Vector3(-1,.25,0);box.rotation=Vector3.ZERO;box.linear_velocity=Vector3.ZERO;box.angular_velocity=Vector3.ZERO
 material.friction=.8;await ticks(30)
 box.linear_velocity=Vector3(1.5,0,0);start=box.position.x;await ticks(30)
 var rough_distance=box.position.x-start
 check(rough_distance<smooth_distance*.5 and absf(box.linear_velocity.x)<.1,"higher friction stops identical sliding box")
 print("SLIDING_RESULT ",JSON.stringify({"zero_friction_distance":smooth_distance,"zero_friction_speed":smooth_speed,"friction_08_distance":rough_distance,"final_speed":box.linear_velocity.x}))
 scene.queue_free();await ticks(3)
 print("HEIGHTMAP_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(1 if failed else 0)
