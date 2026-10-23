extends SceneTree
var scene:Node3D
var passed:=0
var failed:=0
var events:Array=[]
var raw_events:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 if ok:passed+=1
 else:failed+=1
 print("PASS " if ok else "FAIL ",label)
func ticks(n:int=3):
 for i in n:
  await physics_frame
  await process_frame
func add_shape(node:CollisionObject3D,kind:int=0,offset:Vector3=Vector3.ZERO)->CollisionShape3D:
 var c=CollisionShape3D.new();c.position=offset
 if kind==0:c.shape=BoxShape3D.new()
 elif kind==1:c.shape=SphereShape3D.new()
 else:c.shape=CylinderShape3D.new()
 node.add_child(c);return c
func watch(a:Area3D):
 a.body_entered.connect(func(body):events.append(["be",(body.get_instance_id() if is_instance_valid(body) else 0)]))
 a.body_exited.connect(func(body):events.append(["bx",(body.get_instance_id() if is_instance_valid(body) else 0)]))
 a.area_entered.connect(func(other):events.append(["ae",(other.get_instance_id() if is_instance_valid(other) else 0)]))
 a.area_exited.connect(func(other):events.append(["ax",(other.get_instance_id() if is_instance_valid(other) else 0)]))
 a.body_shape_entered.connect(func(rid,body,other_shape,self_shape):events.append(["bse",rid,(body.get_instance_id() if is_instance_valid(body) else 0),other_shape,self_shape]))
 a.body_shape_exited.connect(func(rid,body,other_shape,self_shape):events.append(["bsx",rid,(body.get_instance_id() if is_instance_valid(body) else 0),other_shape,self_shape]))
 a.area_shape_entered.connect(func(rid,other,other_shape,self_shape):events.append(["ase",rid,(other.get_instance_id() if is_instance_valid(other) else 0),other_shape,self_shape]))
 a.area_shape_exited.connect(func(rid,other,other_shape,self_shape):events.append(["asx",rid,(other.get_instance_id() if is_instance_valid(other) else 0),other_shape,self_shape]))
func count_event(type:String)->int:
 var n:=0
 for e in events:
  if e[0]==type:n+=1
 return n
func run():
 scene=Node3D.new();root.add_child(scene)
 check(PhysicsServer3D.get_class()=="MjPhysicsServer3D","native backend")
 var a=Area3D.new();var ac=add_shape(a);watch(a);scene.add_child(a)
 check(a.get_rid().is_valid() and PhysicsServer3D.area_get_object_instance_id(a.get_rid())==a.get_instance_id(),"Area RID and object identity")
 var b=StaticBody3D.new();b.position=Vector3(4,0,0);add_shape(b);scene.add_child(b);await ticks()
 check(events.is_empty(),"no initial false overlap")
 b.position=Vector3.ZERO;await ticks()
 check(count_event("be")==1 and count_event("bse")==1 and a.get_overlapping_bodies()==[b],"body enters once and real list")
 var found:=false
 for e in events:
  if e[0]=="bse":found=e[1]==b.get_rid() and e[2]==b.get_instance_id() and e[3]==0 and e[4]==0
 check(found,"body shape callback RID object and indices")
 PhysicsServer3D.body_set_space(b.get_rid(),scene.get_world_3d().space);PhysicsServer3D.area_set_space(a.get_rid(),scene.get_world_3d().space)
 await ticks(10);check(count_event("be")==1 and count_event("bse")==1,"persistent pair no repeated enters")
 b.position=Vector3(4,0,0);await ticks();check(count_event("bx")==1 and count_event("bsx")==1 and a.get_overlapping_bodies().is_empty(),"body exits once")
 # All supported pairs, including concentric cylinder degeneracy.
 for kind_a in 3:
  ac.shape=BoxShape3D.new() if kind_a==0 else (SphereShape3D.new() if kind_a==1 else CylinderShape3D.new())
  for kind_b in 3:
   b.get_child(0).shape=BoxShape3D.new() if kind_b==0 else (SphereShape3D.new() if kind_b==1 else CylinderShape3D.new())
   b.position=Vector3.ZERO;await ticks();check(a.overlaps_body(b),"primitive overlap %d/%d" % [kind_a,kind_b])
   b.position=Vector3(4,0,0);await ticks();check(not a.overlaps_body(b),"primitive separated %d/%d" % [kind_a,kind_b])
 ac.shape=BoxShape3D.new();b.get_child(0).shape=BoxShape3D.new();b.position=Vector3.ZERO;await ticks()
 events.clear();b.collision_layer=2;await ticks();check(count_event("bx")==1,"mask filters body layer")
 a.collision_mask=2;b.collision_mask=0;await ticks();check(a.overlaps_body(b),"target body mask does not filter detector")
 events.clear();a.monitoring=false;await ticks();check(not a.monitoring and count_event("bx")==1,"monitoring off clears once")
 a.monitoring=true;await ticks();check(a.overlaps_body(b) and count_event("be")==1,"monitoring on reenters once")
 events.clear();ac.disabled=true;await ticks();check(count_event("bx")==1,"disabled shape exits")
 ac.disabled=false;await ticks();check(count_event("be")==1,"reenabled shape enters")
 # Two shape pairs share a single body enter/exit.
 events.clear();var ac2=add_shape(a,0,Vector3(.2,0,0));await ticks()
 check(count_event("be")==0 and count_event("bse")==1,"second local shape adds only shape event")
 var index_one:=false
 for e in events:
  if e[0]=="bse" and e[4]==1:index_one=true
 check(index_one,"native local shape index")
 var bc2=add_shape(b,1,Vector3(.1,0,0));await ticks()
 var other_index_one:=false
 for e in events:
  if e[0]=="bse" and e[3]==1:other_index_one=true
 check(other_index_one,"native target shape index")
 bc2.disabled=true;await ticks();check(a.overlaps_body(b),"disabled target shape preserves other pair")
 bc2.queue_free();await ticks()
 events.clear();ac2.queue_free();await ticks();check(count_event("bsx")==1 and count_event("bx")==0,"shape deletion preserves other pair")
 # Removing lower indices retires old shape identities before indices compact.
 ac2=add_shape(a,0,Vector3(.2,0,0));await ticks();events.clear()
 ac.queue_free();await ticks()
 check(count_event("bsx")==2 and count_event("bse")==1 and a.overlaps_body(b),"shape index compaction exits old pairs and enters new index")
 ac=ac2
 ac.position=Vector3(2,0,0);a.rotation.z=PI/2;b.position=Vector3(0,2,0);await ticks()
 check(a.overlaps_body(b),"rotated area and local shape offset")
 a.rotation=Vector3.ZERO;ac.position=Vector3.ZERO;b.position=Vector3.ZERO;await ticks()
 events.clear();b.queue_free();await ticks();check(count_event("bx")==1 and a.get_overlapping_bodies().is_empty(),"body deletion exit exactly once")
 a.collision_mask=1
 var other=Area3D.new();other.monitoring=false;add_shape(other,2);scene.add_child(other);await ticks()
 check(a.get_overlapping_areas()==[other] and count_event("ae")==1 and count_event("ase")==1,"monitorable area detected without its monitoring")
 events.clear();other.monitorable=false;await ticks();check(count_event("ax")==1 and count_event("asx")==1,"monitorable off exits")
 other.monitorable=true;await ticks();check(count_event("ae")==1,"monitorable on enters")
 events.clear();var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
 other.reparent(viewport);await ticks();check(count_event("ax")==1 and a.get_overlapping_areas().is_empty(),"cross World exits")
 other.reparent(scene);await ticks();check(count_event("ae")==1,"return World enters")
 events.clear();a.reparent(viewport);await ticks()
 check(count_event("ax")==1 and a.get_overlapping_areas().is_empty(),"monitoring area moves World without stale pair")
 a.reparent(scene);await ticks();check(count_event("ae")==1,"monitoring area returns World with one enter")
 events.clear();other.queue_free();await ticks();check(count_event("ax")==1,"area deletion exit exactly once")
 viewport.queue_free()
 # Trigger must not change a rigid body's free-flight velocity or contacts.
 var moving=RigidBody3D.new();moving.gravity_scale=0;moving.linear_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;moving.linear_damp=0;moving.angular_damp_mode=RigidBody3D.DAMP_MODE_REPLACE;moving.angular_damp=0
 moving.position=Vector3(-2,0,0);moving.linear_velocity=Vector3(2,0,0);moving.max_contacts_reported=8;add_shape(moving);scene.add_child(moving)
 var seen:=false
 for i in 120:
  await ticks(1)
  seen=seen or a.overlaps_body(moving)
 check(seen and absf(moving.linear_velocity.x-2)<.0001 and absf(moving.position.x-2)<.1,"trigger overlap never applies impulse")
 check(PhysicsServer3D.body_get_direct_state(moving.get_rid()).get_contact_count()==0,"trigger absent from physical contacts")
 moving.queue_free();await ticks()
 # Raw callbacks exercise backend queue independently of Area3D node's own lock.
 var raw=PhysicsServer3D.area_create();var target=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_STATIC)
 var shape=PhysicsServer3D.box_shape_create();PhysicsServer3D.shape_set_data(shape,Vector3.ONE*.5)
 PhysicsServer3D.area_add_shape(raw,shape);PhysicsServer3D.body_add_shape(target,shape)
 PhysicsServer3D.area_set_space(raw,scene.get_world_3d().space);PhysicsServer3D.body_set_space(target,scene.get_world_3d().space)
 PhysicsServer3D.area_set_monitor_callback(raw,func(status,rid,id,other_index,self_index):
  raw_events.append([status,rid,id,other_index,self_index])
  if status==PhysicsServer3D.AREA_BODY_ADDED:PhysicsServer3D.area_set_shape_disabled(raw,0,true))
 await ticks(6)
 check(raw_events.size()==2 and raw_events[0]==[PhysicsServer3D.AREA_BODY_ADDED,target,0,0,0] and raw_events[1]==[PhysicsServer3D.AREA_BODY_REMOVED,target,0,0,0],"callback mutation queued with balanced shape pair")
 raw_events.clear();PhysicsServer3D.area_set_shape_disabled(raw,0,false)
 PhysicsServer3D.area_set_monitor_callback(raw,func(status,rid,_id,_other,_self):
  raw_events.append(status)
  if status==PhysicsServer3D.AREA_BODY_ADDED:PhysicsServer3D.free_rid(rid))
 await ticks(6)
 check(raw_events==[PhysicsServer3D.AREA_BODY_ADDED,PhysicsServer3D.AREA_BODY_REMOVED],"target free inside callback balanced once")
 PhysicsServer3D.free_rid(raw)
 raw=PhysicsServer3D.area_create();target=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.area_add_shape(raw,shape);PhysicsServer3D.body_add_shape(target,shape)
 PhysicsServer3D.area_set_space(raw,scene.get_world_3d().space);PhysicsServer3D.body_set_space(target,scene.get_world_3d().space)
 raw_events.clear()
 PhysicsServer3D.area_set_monitor_callback(raw,func(status,_rid,_id,_other,_self):
  raw_events.append(status)
  if status==PhysicsServer3D.AREA_BODY_ADDED:PhysicsServer3D.free_rid(raw))
 await ticks(6)
 check(raw_events==[PhysicsServer3D.AREA_BODY_ADDED],"receiver free inside callback stops further delivery")
 raw=PhysicsServer3D.area_create();PhysicsServer3D.area_add_shape(raw,shape);PhysicsServer3D.area_set_space(raw,scene.get_world_3d().space)
 raw_events.clear()
 PhysicsServer3D.area_set_monitor_callback(raw,func(status,_rid,_id,_other,_self):raw_events.append(status))
 await ticks();PhysicsServer3D.free_rid(shape);await ticks()
 check(raw_events==[PhysicsServer3D.AREA_BODY_ADDED,PhysicsServer3D.AREA_BODY_REMOVED] and PhysicsServer3D.area_get_shape_count(raw)==0 and PhysicsServer3D.body_get_shape_count(target)==0,"shared shape RID free clears dependencies once")
 PhysicsServer3D.free_rid(raw);PhysicsServer3D.free_rid(target)
 a.queue_free();scene.queue_free();await ticks()
 print("AREA_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
 quit(0 if failed==0 else 1)
