extends SceneTree
var passed:=0
var failed:=0
var scene:Node3D
var character:CharacterBody3D
func check(ok:bool,label:String)->void:
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func ticks(n:int)->void:
 for i in n:
  await physics_frame
  await process_frame
func obstacle(size:Vector3,position:Vector3,rotation:Vector3=Vector3.ZERO)->StaticBody3D:
 var body:=StaticBody3D.new();body.position=position;body.rotation=rotation
 var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;collision.shape=box
 body.add_child(collision);scene.add_child(body);return body
func reset_player(position:Vector3)->void:
 character.position=position;character.velocity=Vector3.ZERO
 await ticks(2)
func slide(velocity:Vector3)->void:
 await physics_frame
 character.velocity=velocity
 character.move_and_slide()
 await process_frame
func _initialize()->void:call_deferred("run")
func run()->void:
 scene=Node3D.new();root.add_child(scene)
 var floor_body:=obstacle(Vector3(16,1,16),Vector3(0,-.5,0))
 var wall:=obstacle(Vector3(.2,4,6),Vector3(3,2,0))
 var ceiling:=obstacle(Vector3(6,.2,6),Vector3(0,3,0))
 character=CharacterBody3D.new();character.position=Vector3(0,1,0)
 character.safe_margin=.001;character.floor_snap_length=.3;character.floor_max_angle=deg_to_rad(45)
 var collision:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.4;capsule.height=1.8;collision.shape=capsule
 character.add_child(collision);scene.add_child(character)
 await ticks(3)
 check(PhysicsServer3D.body_get_mode(character.get_rid())==PhysicsServer3D.BODY_MODE_KINEMATIC,"CharacterBody registers native kinematic mode")
 var before:=character.position
 var test:=character.move_and_collide(Vector3(5,0,0),true)
 check(test!=null,"move_and_collide test_only reports wall")
 check(character.position==before,"test_only does not move CharacterBody")
 check(test!=null and test.get_collider()==wall and test.get_normal().dot(Vector3.LEFT)>.99,"CharacterBody collision identity and wall normal")
 check(test!=null and (test.get_travel()+test.get_remainder()).distance_to(Vector3(5,0,0))<.002,"CharacterBody travel plus remainder")
 var actual:=character.move_and_collide(Vector3(5,0,0))
 check(actual!=null and character.position.x>2.45 and character.position.x<2.51,"move_and_collide stops capsule before wall")
 # Start below the ceiling to avoid interpreting it as an initial penetration.
 await reset_player(Vector3(0,1.7,0))
 var grounded_frames:=0
 for i in 90:
  await slide(Vector3(0,character.velocity.y-9.8/60,0))
  if character.is_on_floor():grounded_frames+=1
 check(character.is_on_floor() and grounded_frames>45,"move_and_slide establishes persistent floor over many frames")
 check(absf(character.position.y-.9)<.025,"standing capsule bottom rests on floor")
 check(character.get_floor_normal().dot(Vector3.UP)>.99,"floor normal is upward")
 var wall_frames:=0
 var floor_frames:=0
 for i in 100:
  await slide(Vector3(3,character.velocity.y-9.8/60,1))
  if character.is_on_wall():wall_frames+=1
  if character.is_on_floor():floor_frames+=1
 check(wall_frames>20 and character.position.x<2.51,"multiframe floor motion blocks at wall")
 check(character.position.z>1.3,"move_and_slide preserves tangential wall motion")
 check(floor_frames>90,"wall slide retains floor classification")
 # Floor snap is an explicit requirement; do not weaken on implementation failure.
 await reset_player(Vector3(0,1.05,0))
 # Teleporting does not clear CharacterBody floor flags; reset them without snap.
 character.floor_snap_length=0
 await slide(Vector3.ZERO)
 character.floor_snap_length=.3
 character.apply_floor_snap()
 check(character.is_on_floor(),"apply_floor_snap establishes floor")
 check(character.position.y<.93 and character.position.y>.88,"floor snap closes small vertical gap")
 await slide(Vector3.ZERO)
 check(character.is_on_floor() and absf(character.position.y-.9)<.03,"floor snap survives next move_and_slide")
 await reset_player(Vector3(0,1.0,0))
 var ceiling_frames:=0
 var max_height:=character.position.y
 for i in 24:
  await slide(Vector3(0,6,0))
  if character.is_on_ceiling():ceiling_frames+=1
  max_height=maxf(max_height,character.position.y)
 check(ceiling_frames>0,"upward capsule movement classifies ceiling")
 check(max_height<2.03,"ceiling blocks capsule endcap")
 # Separate slope avoids interactions with the floor/wall/ceiling fixtures.
 var angle:=deg_to_rad(20)
 var slope:=obstacle(Vector3(8,.5,8),Vector3(20,0,0),Vector3(0,0,angle))
 await reset_player(Vector3(20,3,0))
 for i in 100:await slide(Vector3(0,character.velocity.y-9.8/60,0))
 var slope_normal:=slope.global_basis*Vector3.UP
 check(character.is_on_floor() and character.get_floor_normal().dot(slope_normal)>.99,"walkable slope is floor with geometric normal")
 var slope_start:=character.position
 for i in 30:await slide(Vector3(1,character.velocity.y-9.8/60,0))
 check(character.position.x>slope_start.x+.25 and character.position.y>slope_start.y+.05,"move_and_slide walks uphill")
 check(character.is_on_floor(),"uphill movement retains floor classification")
 # One-way interaction: a query can block on a rigid body without pushing it.
 var rigid:=RigidBody3D.new();rigid.gravity_scale=0;rigid.position=Vector3(-3,1,0)
 var rigid_collision:=CollisionShape3D.new();var rigid_box:=BoxShape3D.new();rigid_box.size=Vector3.ONE
 rigid_collision.shape=rigid_box;rigid.add_child(rigid_collision);scene.add_child(rigid)
 await reset_player(Vector3(-6,1,0))
 var rigid_before:=rigid.position
 var rigid_hit:=character.move_and_collide(Vector3(5,0,0))
 check(rigid_hit!=null and rigid_hit.get_collider()==rigid,"CharacterBody query blocks on frozen dynamic target")
 await ticks(10)
 check(rigid.position.distance_to(rigid_before)<.01 and rigid.linear_velocity.length()<.01,"kinematic character does not inject impulse into rigid target")
 # Removed obstacle cannot remain visible through stale query state.
 wall.queue_free();await ticks(3)
 await reset_player(Vector3(0,1,0))
 check(character.move_and_collide(Vector3(5,0,0),true)==null,"freed wall absent from CharacterBody motion")
 # Explicitly retain diagnostic geometry/flags in the result, even on failures.
 var diagnostic:={"position":character.position,"on_floor":character.is_on_floor(),"on_wall":character.is_on_wall(),"on_ceiling":character.is_on_ceiling(),"grounded_frames":grounded_frames,"wall_frames":wall_frames,"floor_frames":floor_frames,"ceiling_frames":ceiling_frames}
 scene.queue_free();await ticks(3)
 print("MOTION_CHARACTER_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"diagnostic":diagnostic}))
 quit(0 if failed==0 else 1)
