extends SceneTree
var scene:Node3D
var passed:=0
var failed:=0
var entered:=0
var exited:=0
var callback_deleted:=false
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func ticks(n:int):
 for i in n:
  await physics_frame
  await process_frame
func add_shape(b:PhysicsBody3D,p:Vector3=Vector3.ZERO):
 var c=CollisionShape3D.new();c.shape=BoxShape3D.new();c.position=p;b.add_child(c)
func run():
 scene=Node3D.new();root.add_child(scene)
 var floor=StaticBody3D.new();var cs=CollisionShape3D.new();cs.shape=WorldBoundaryShape3D.new();floor.add_child(cs);scene.add_child(floor)
 var b=RigidBody3D.new();b.position=Vector3(2,2,0);b.max_contacts_reported=16;b.contact_monitor=true;add_shape(b);scene.add_child(b)
 b.body_entered.connect(func(_other):entered+=1)
 b.body_exited.connect(func(_other):exited+=1)
 await ticks(150)
 var state=PhysicsServer3D.body_get_direct_state(b.get_rid())
 check(state.get_contact_count()==4,"box plane four manifold points")
 check(b.get_colliding_bodies().has(floor) and entered==1,"contact_monitor body_entered and list")
 var impulse:=Vector3.ZERO
 for i in state.get_contact_count():
  check(state.get_contact_collider(i)==floor.get_rid() and state.get_contact_collider_object(i)==floor and state.get_contact_collider_id(i)==floor.get_instance_id(),"collider identity")
  check(state.get_contact_local_shape(i)==0 and state.get_contact_collider_shape(i)==0,"shape indices")
  check(state.get_contact_local_normal(i).dot(Vector3.UP)>.999,"normal faces current body")
  check(absf(state.get_contact_local_position(i).y)<.02 and state.get_contact_local_position(i).x>1,"world space position")
  check(state.get_contact_local_position(i).is_equal_approx(state.get_contact_collider_position(i)),"shared midpoint")
  check(state.get_contact_local_velocity_at_position(i).length()<.1 and state.get_contact_collider_velocity_at_position(i).length()<.001,"point velocities")
  impulse+=state.get_contact_impulse(i)
 check(absf(impulse.y-9.8/540)<.003,"last substep impulse N s")
 b.max_contacts_reported=1;await ticks(3);check(state.get_contact_count()==1,"capacity truncation")
 b.max_contacts_reported=0;await ticks(3);check(state.get_contact_count()==0 and b.get_colliding_bodies().is_empty() and exited==1,"zero disables and monitor exits")
 b.max_contacts_reported=16;await ticks(3)
 b.add_collision_exception_with(floor);await ticks(3);check(state.get_contact_count()==0,"exception filters report")
 b.remove_collision_exception_with(floor);b.position=Vector3(2,.5,0);b.linear_velocity=Vector3.ZERO;await ticks(30)
 b.collision_mask=0;floor.collision_mask=0;await ticks(3);check(state.get_contact_count()==0,"bilateral masks filter report")
 b.collision_mask=1;floor.collision_mask=1;b.position=Vector3(2,.5,0);b.linear_velocity=Vector3.ZERO
 add_shape(b,Vector3(2,0,0));await ticks(100)
 var indices:={}
 for i in state.get_contact_count():indices[state.get_contact_local_shape(i)]=true
 check(indices.has(0) and indices.has(1),"multiple native shapes")
 floor.queue_free();await ticks(3);check(state.get_contact_count()==0 and b.get_colliding_bodies().is_empty(),"deleted collider cleared")
 var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
 scene.remove_child(b);viewport.add_child(b);await ticks(3);check(state.get_contact_count()==0,"cross World clears contacts")
 viewport.queue_free();await ticks(3)
 var a=RigidBody3D.new();a.gravity_scale=0;a.position=Vector3(-.51,2,0);a.linear_velocity=Vector3.RIGHT;a.max_contacts_reported=8;add_shape(a);scene.add_child(a)
 var other=RigidBody3D.new();other.gravity_scale=0;other.position=Vector3(.51,2,0);other.linear_velocity=Vector3.LEFT;other.max_contacts_reported=8;add_shape(other);scene.add_child(other)
 var hit:=false
 for frame in 20:
  await ticks(1)
  var sa=PhysicsServer3D.body_get_direct_state(a.get_rid());var sb=PhysicsServer3D.body_get_direct_state(other.get_rid())
  if sa.get_contact_count()>0 and sb.get_contact_count()>0:
   var ia:=Vector3.ZERO;var ib:=Vector3.ZERO
   for i in sa.get_contact_count():ia+=sa.get_contact_impulse(i)
   for i in sb.get_contact_count():ib+=sb.get_contact_impulse(i)
   check(sa.get_contact_collider_object(0)==other and sb.get_contact_collider_object(0)==a,"rigid pair identities")
   check(ia.x<0 and ib.x>0 and (ia+ib).length()<.00001,"equal opposite dynamic impulses")
   hit=true;break
 check(hit,"dynamic collision observed")
 a.queue_free();other.queue_free();await ticks(3)
 var shape=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(shape,Vector3.ONE*.5)
 var raw=PhysicsServer3D.body_create();PhysicsServer3D.body_add_shape(raw,shape)
 PhysicsServer3D.body_set_space(raw,scene.get_world_3d().space)
 var raw_floor=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(raw_floor,PhysicsServer3D.BODY_MODE_STATIC);PhysicsServer3D.body_add_shape(raw_floor,shape)
 PhysicsServer3D.body_set_state(raw_floor,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(0,-.9,0)))
 PhysicsServer3D.body_set_space(raw_floor,scene.get_world_3d().space)
 PhysicsServer3D.body_set_max_contacts_reported(raw,8)
 PhysicsServer3D.body_set_state_sync_callback(raw,func(raw_state):
  if raw_state.get_contact_count()==0:return
  check(true,"contact visible in sync callback")
  PhysicsServer3D.free_rid(raw_floor)
  check(raw_state.get_contact_count()==0,"peer deferred free invalidates report immediately")
  PhysicsServer3D.free_rid(raw)
  callback_deleted=true)
 await ticks(30)
 check(callback_deleted,"body deletion inside sync callback")
 if not callback_deleted:
  PhysicsServer3D.free_rid(raw_floor);PhysicsServer3D.free_rid(raw)
 PhysicsServer3D.free_rid(shape)
 var world=scene.get_world_3d().space
 check(PhysicsServer3D.call("scene_pause",world,true),"pause for imported geometry")
 var imported:RID=PhysicsServer3D.call("scene_add_box",world,"contact_boundary",Transform3D(Basis.IDENTITY,Vector3(0,-.5,0)),Vector3(4,1,4),0.0)
 check(imported.is_valid(),"imported obstacle exists")
 var probe=RigidBody3D.new();probe.position=Vector3(0,1,0);probe.max_contacts_reported=8;probe.contact_monitor=true;add_shape(probe);scene.add_child(probe)
 PhysicsServer3D.call("scene_pause",world,false)
 await ticks(120)
 var ps=PhysicsServer3D.body_get_direct_state(probe.get_rid())
 check(ps.get_contact_count()>0,"imported geometry reports physical contact")
 for i in ps.get_contact_count():
  check(not ps.get_contact_collider(i).is_valid() and ps.get_contact_collider_id(i)==0 and ps.get_contact_collider_object(i)==null and ps.get_contact_collider_shape(i)==-1,"imported geometry never impersonates native Body")
 check(probe.get_colliding_bodies().is_empty(),"monitor excludes unidentified imported collider")
 probe.queue_free();await ticks(3)
 PhysicsServer3D.call("scene_pause",world,true)
 PhysicsServer3D.call("scene_remove",world,imported)
 scene.queue_free();await ticks(3)
 print("CONTACT_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(0 if failed==0 else 1)
