extends SceneTree

var passed := 0
var failed := 0
var stage := "geometry"
var counts: Dictionary = {}
var owned: Array[RID] = []
var space: RID
var state: PhysicsDirectSpaceState3D

func check(ok: bool, label: String) -> void:
 counts[stage] = int(counts.get(stage,0))+1
 if ok: passed += 1
 else: failed += 1
 print("PASS " if ok else "FAIL ",label)

func make_shape(kind: int, data: Variant) -> RID:
 var shape: RID
 match kind:
  PhysicsServer3D.SHAPE_CAPSULE: shape=PhysicsServer3D.capsule_shape_create()
  PhysicsServer3D.SHAPE_SPHERE: shape=PhysicsServer3D.sphere_shape_create()
  PhysicsServer3D.SHAPE_BOX: shape=PhysicsServer3D.box_shape_create()
  PhysicsServer3D.SHAPE_CYLINDER: shape=PhysicsServer3D.cylinder_shape_create()
  _: shape=PhysicsServer3D.world_boundary_shape_create()
 PhysicsServer3D.shape_set_data(shape,data)
 owned.append(shape)
 return shape

func capsule(radius: float, height: float) -> RID:
 return make_shape(PhysicsServer3D.SHAPE_CAPSULE,{"radius":radius,"height":height})

func make_body(shape: RID, pose: Transform3D=Transform3D.IDENTITY) -> RID:
 var body:=PhysicsServer3D.body_create()
 owned.append(body)
 PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(body,shape)
 PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
 PhysicsServer3D.body_set_space(body,space)
 return body

func remove_body(body: RID) -> void:
 PhysicsServer3D.free_rid(body)
 owned.erase(body)

func query(shape: RID, position: Vector3=Vector3.ZERO, motion: Vector3=Vector3.ZERO) -> PhysicsShapeQueryParameters3D:
 var q:=PhysicsShapeQueryParameters3D.new()
 q.shape_rid=shape
 q.transform.origin=position
 q.motion=motion
 return q

func ray(a: Vector3, b: Vector3, mask: int=1, exclude: Array[RID]=[]) -> Dictionary:
 return state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,mask,exclude))

func point(position: Vector3, mask: int=1, exclude: Array[RID]=[], max_results: int=32) -> Array:
 var q:=PhysicsPointQueryParameters3D.new()
 q.position=position;q.collision_mask=mask;q.exclude=exclude
 return state.intersect_point(q,max_results)

# Independent analytic distance to the capsule's axis segment, in Godot Y-up.
func capsule_error(p: Vector3, radius: float, height: float, pose: Transform3D) -> float:
 var local:=pose.affine_inverse()*p
 var half_segment:=height*.5-radius
 var closest:=Vector3(0,clampf(local.y,-half_segment,half_segment),0)
 return absf(local.distance_to(closest)-radius)

# Signed-distance surface formulas are independent of the narrowphase/witness code.
func primitive_error(p: Vector3, spec: Dictionary, pose: Transform3D) -> float:
 if spec.kind=="capsule":return capsule_error(p,spec.radius,spec.height,pose)
 var local:=pose.affine_inverse()*p
 if spec.kind=="sphere":return absf(local.length()-float(spec.radius))
 if spec.kind=="box":
  var delta: Vector3=local.abs()-spec.extents
  return absf(delta.max(Vector3.ZERO).length()+minf(maxf(delta.x,maxf(delta.y,delta.z)),0))
 var delta:=Vector2(Vector2(local.x,local.z).length()-float(spec.radius),absf(local.y)-float(spec.height)*.5)
 return absf(delta.max(Vector2.ZERO).length()+minf(maxf(delta.x,delta.y),0))

func probe_pair(query_shape: RID, query_spec: Dictionary, target_shape: RID, target_spec: Dictionary,
  query_pose: Transform3D, target_pose: Transform3D, label: String) -> void:
 var body:=make_body(target_shape,target_pose)
 var q:=query(query_shape);q.transform=query_pose
 var hits:=state.intersect_shape(q)
 check(hits.size()==1 and hits[0].rid==body and hits[0].shape==0,label+" identity")
 var contacts:=state.collide_shape(q)
 var valid:=contacts.size()>=2 and contacts.size()%2==0
 var deepest:=0.0
 for i in range(0,contacts.size()-1,2):
  valid=valid and contacts[i].is_finite() and contacts[i+1].is_finite()
  valid=valid and primitive_error(contacts[i],query_spec,query_pose)<.003 and primitive_error(contacts[i+1],target_spec,target_pose)<.003
  deepest=maxf(deepest,contacts[i].distance_to(contacts[i+1]))
 check(valid and deepest>.05,label+" both witness surfaces and nonflattened penetration")
 var rest:=state.get_rest_info(q)
 check(not rest.is_empty() and rest.rid==body and rest.shape==0 and rest.point.is_finite() and
  primitive_error(rest.point,target_spec,target_pose)<.003 and rest.normal.is_finite() and absf(rest.normal.length()-1)<.0001,
  label+" rest target surface and finite unit normal")
 remove_body(body)

func fraction(q: PhysicsShapeQueryParameters3D, expected: float, label: String) -> void:
 var hit:=state.cast_motion(q)
 check(hit.size()==2 and hit[0]<=expected+1e-7 and hit[1]>=expected-1e-7 and hit[0]<=hit[1] and absf(hit[1]-expected)<2e-6,label)

func clear(q: PhysicsShapeQueryParameters3D, label: String) -> void:
 check(state.cast_motion(q)==PackedFloat32Array([1,1]),label)

func ticks(n: int) -> void:
 for i in n:
  await physics_frame
  await process_frame

func _initialize() -> void: call_deferred("run")

func run() -> void:
 check(PhysicsServer3D.get_class()=="MjPhysicsServer3D","native backend")
 space=PhysicsServer3D.space_create()
 state=PhysicsServer3D.space_get_direct_state(space)
 var cap:=capsule(.5,3)
 var target:=make_body(cap)
 check(PhysicsServer3D.shape_get_type(cap)==PhysicsServer3D.SHAPE_CAPSULE,"native capsule shape type")
 check(PhysicsServer3D.shape_get_data(cap)=={"radius":.5,"height":3.0},"height includes both hemispheres")
 var copied: Dictionary=PhysicsServer3D.shape_get_data(cap)
 copied.height=10
 check(PhysicsServer3D.shape_get_data(cap).height==3,"capsule data getter returns independent dictionary")
 # End caps and barrel side have different extents; a cylinder stand-in fails.
 for surface in [Vector3(0,1.5,0),Vector3(0,-1.5,0),Vector3(.5,0,0),Vector3(0,0,.5)]:
  var normal: Vector3=surface.normalized()
  var hit:=ray(surface+normal*2,surface-normal*.2)
  check(hit.get("rid")==target and hit.get("shape")==0,"capsule ray identity "+str(surface))
  check(hit.get("position",Vector3.INF).distance_to(surface)<.001 and hit.get("normal",Vector3.ZERO).dot(normal)>.999,"capsule ray cap/side geometry "+str(surface))
 check(point(Vector3(0,1.49,0)).size()==1 and point(Vector3(.49,0,0)).size()==1,"capsule cap and barrel point interior")
 check(point(Vector3(.49,1.49,0)).is_empty() and point(Vector3(0,1.51,0)).is_empty(),"rounded cap point exterior")
 check(ray(Vector3.ZERO,Vector3(2,0,0)).is_empty(),"inside ray default excluded")
 var inside:=PhysicsRayQueryParameters3D.create(Vector3.ZERO,Vector3(2,0,0));inside.hit_from_inside=true
 check(state.intersect_ray(inside).get("normal",Vector3.ONE)==Vector3.ZERO,"inside ray requested zero normal")
 var pose:=Transform3D(Basis.from_euler(Vector3(.2,.3,.4)),Vector3(3,2,-1))
 var local:=Transform3D(Basis.from_euler(Vector3(-.3,.2,.1)),Vector3(1,2,-.5))
 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,pose)
 PhysicsServer3D.body_set_shape_transform(target,0,local)
 var world:=pose*local
 var up:=world.basis*Vector3.UP
 var cap_surface:=world*Vector3(0,1.5,0)
 var hit:=ray(cap_surface+up*2,cap_surface-up*.2)
 check(hit.get("rid")==target and hit.get("position",Vector3.INF).distance_to(cap_surface)<.001 and hit.get("normal",Vector3.ZERO).dot(up)>.999,"combined body rotation and local offset ray")
 check(point(world.origin).size()==1,"rotated local offset point")
 var q:=query(cap)
 q.transform=world;q.transform.origin+=world.basis*Vector3(.8,0,0)
 var hits:=state.intersect_shape(q)
 check(hits.size()==1 and hits[0].rid==target,"rotated capsule overlap")
 var contacts:=state.collide_shape(q)
 var surfaces_ok:=contacts.size()>=2 and contacts.size()%2==0
 for i in range(0,contacts.size()-1,2):
  surfaces_ok=surfaces_ok and contacts[i].is_finite() and contacts[i+1].is_finite()
  surfaces_ok=surfaces_ok and capsule_error(contacts[i],.5,3,q.transform)<.003 and capsule_error(contacts[i+1],.5,3,world)<.003
 check(surfaces_ok,"every capsule contact pair belongs to its original surface")
 var rest:=state.get_rest_info(q)
 check(not rest.is_empty() and rest.rid==target and capsule_error(rest.point,.5,3,world)<.003 and rest.normal.dot(world.basis*Vector3.RIGHT)>.99,"rest target witness and outward normal")
 q.transform.origin+=world.basis*Vector3(.25,0,0)
 check(state.intersect_shape(q).is_empty(),"separated capsule misses at zero margin")
 q.margin=.1
 check(state.intersect_shape(q).size()==1,"capsule query margin counted once")
 q.margin=0;q.transform=world
 check(state.intersect_shape(q).size()==1,"coincident capsule initial overlap")

 stage="lifecycle"
 check(point(world.origin,1,[target]).is_empty(),"capsule point exclusion")
 check(ray(cap_surface+up*2,cap_surface-up*.2,1,[target]).is_empty(),"capsule ray exclusion")
 q.exclude=[target]
 check(state.intersect_shape(q).is_empty() and state.collide_shape(q).is_empty() and state.get_rest_info(q).is_empty(),"capsule shared shape exclusion")
 q.exclude=[];q.collision_mask=2
 check(state.intersect_shape(q).is_empty(),"capsule query mask")
 PhysicsServer3D.body_set_collision_layer(target,2);PhysicsServer3D.body_set_collision_mask(target,0)
 check(state.intersect_shape(q).size()==1 and point(world.origin,2).size()==1,"target mask independent from layer visibility")
 check(ray(cap_surface+up*2,cap_surface-up*.2).is_empty() and ray(cap_surface+up*2,cap_surface-up*.2,2).get("rid")==target,"capsule ray layer filtering")
 PhysicsServer3D.body_set_shape_disabled(target,0,true)
 check(state.intersect_shape(q).is_empty(),"disabled capsule absent immediately")
 PhysicsServer3D.body_set_shape_disabled(target,0,false)
 check(state.intersect_shape(q).size()==1,"reenabled capsule visible immediately")
 PhysicsServer3D.shape_set_data(cap,{"radius":.6,"height":3.4})
 var top:=world*Vector3(0,1.7,0)
 check(ray(top+up,top-up*.1,2).get("position",Vector3.INF).distance_to(top)<.001,"capsule resize rebuild uses full height")
 var second:=Transform3D(Basis.IDENTITY,Vector3(6,0,0))
 PhysicsServer3D.body_add_shape(target,cap,second)
 var index_hits:=point(pose*second.origin,2)
 check(index_hits.size()==1 and index_hits[0].shape==1,"multiple capsule native shape index")
 PhysicsServer3D.body_remove_shape(target,0)
 index_hits=point(pose*second.origin,2)
 check(index_hits.size()==1 and index_hits[0].shape==0,"shape removal updates index")
 var another:=PhysicsServer3D.space_create()
 PhysicsServer3D.body_set_space(target,another)
 check(point(pose*second.origin,2).is_empty(),"capsule moved to other space absent")
 PhysicsServer3D.body_set_space(target,space);PhysicsServer3D.free_rid(another)
 check(point(pose*second.origin,2).size()==1,"capsule reattached to original space")
 remove_body(target)
 check(point(pose*second.origin,2).is_empty(),"freed capsule body absent")

 stage="degenerate"
 var degenerate:=capsule(.5,1)
 target=make_body(degenerate)
 for normal in [Vector3.UP,Vector3.RIGHT,Vector3.BACK]:
  hit=ray(normal*2,Vector3.ZERO)
  check(hit.get("rid")==target and hit.get("position",Vector3.INF).distance_to(normal*.5)<.001 and hit.get("normal",Vector3.ZERO).dot(normal)>.999,"h equals 2r ray is spherical "+str(normal))
 check(point(Vector3(0,.49,0)).size()==1 and point(Vector3(.4,.4,0)).is_empty(),"h equals 2r point is spherical")
 q=query(degenerate,Vector3(.8,0,0))
 check(state.intersect_shape(q).size()==1 and not state.get_rest_info(q).is_empty(),"h equals 2r overlap retained")
 remove_body(target)

 stage="sweep"
 PhysicsServer3D.shape_set_data(cap,{"radius":.5,"height":3.0})
 var sphere:=make_shape(PhysicsServer3D.SHAPE_SPHERE,1.0)
 var box:=make_shape(PhysicsServer3D.SHAPE_BOX,Vector3.ONE)
 var cylinder:=make_shape(PhysicsServer3D.SHAPE_CYLINDER,{"radius":1.0,"height":2.0})
 var plane:=make_shape(PhysicsServer3D.SHAPE_WORLD_BOUNDARY,Plane(Vector3.UP,0))
 for obstacle in [sphere,box,cylinder,cap]:
  target=make_body(obstacle)
  var expected:=.4 if obstacle==cap else .35
  q=query(cap,Vector3(-5,0,0),Vector3(10,0,0))
  fraction(q,expected,"capsule continuous primitive sweep")
  q.margin=.1;fraction(q,expected-.01,"capsule continuous sweep margin")
  q.margin=0;q.motion=Vector3.ZERO;clear(q,"capsule zero motion")
  q.motion=Vector3.LEFT*10;clear(q,"capsule moving away")
  q.transform.origin=Vector3.ZERO;q.motion=Vector3.RIGHT*10;clear(q,"initial penetration ignored per shape")
  q.transform.origin=Vector3(-5,0,0);q.exclude=[target];clear(q,"capsule sweep exclusion")
  q.exclude=[];q.collision_mask=2;clear(q,"capsule sweep mask")
  q.collision_mask=1;PhysicsServer3D.body_set_shape_disabled(target,0,true);clear(q,"capsule sweep disabled target")
  remove_body(target)
 target=make_body(plane)
 fraction(query(cap,Vector3(0,5,0),Vector3(0,-10,0)),.35,"capsule supporting endcap against plane")
 q=query(cap,Vector3(0,5,0),Vector3(0,-10,0));q.transform.basis=Basis(Vector3.FORWARD,PI/2)
 fraction(q,.45,"rotated capsule support against plane")
 remove_body(target)
 target=make_body(sphere)
 fraction(query(degenerate,Vector3(-5,0,0),Vector3(10,0,0)),.35,"degenerate capsule sweep equals sphere")
 q=query(cap,Vector3(-5,0,0),Vector3(10,0,0));q.transform.basis=Basis(Vector3.FORWARD,PI/2)
 fraction(q,.25,"horizontal capsule leading endcap continuous sweep")
 fraction(query(cap,Vector3(-5,2.5,0),Vector3(10,0,0)),.5,"representable capsule endcap grazing")
 clear(query(cap,Vector3(-5,2.501,0),Vector3(10,0,0)),"near grazing capsule misses")
 remove_body(target)
 var wall:=make_shape(PhysicsServer3D.SHAPE_BOX,Vector3(.001,5,5))
 var narrow:=capsule(.01,.08)
 target=make_body(wall)
 fraction(query(narrow,Vector3(-10,0,0),Vector3(20000,0,0)),(10-.011)/20000,"high speed capsule crosses thin wall continuously")
 remove_body(target)
 var initial:=make_body(cap)
 target=make_body(cap,Transform3D(Basis.IDENTITY,Vector3(4,0,0)))
 fraction(query(cap,Vector3.ZERO,Vector3(10,0,0)),.3,"ignore initial penetration but retain later target")
 remove_body(initial);remove_body(target)
 check(not PhysicsServer3D.space_is_active(space),"all queries preserve inactive space")
 stage="overlap_pairs"
 var cap_spec:={"kind":"capsule","radius":.5,"height":3.0}
 var other_cap:=capsule(.8,2.6)
 var pair_shapes:=[sphere,box,cylinder,other_cap]
 var pair_specs:=[{"kind":"sphere","radius":1.0},{"kind":"box","extents":Vector3.ONE},
  {"kind":"cylinder","radius":1.0,"height":2.0},{"kind":"capsule","radius":.8,"height":2.6}]
 var pair_query_pose:=Transform3D(Basis.from_euler(Vector3(.2,.4,-.3)),Vector3(3,2,-1))
 var centered_pose:=Transform3D(Basis.from_euler(Vector3(-.3,.1,.5)),pair_query_pose.origin)
 var offset_pose:=Transform3D(centered_pose.basis,centered_pose.origin+Vector3(.12,.1,-.08))
 for arrangement in [["concentric rotated",centered_pose],["offset rotated",offset_pose]]:
  for index in pair_shapes.size():
   var spec: Dictionary=pair_specs[index]
   var target_pose: Transform3D=arrangement[1]
   probe_pair(cap,cap_spec,pair_shapes[index],spec,pair_query_pose,target_pose,
    str(arrangement[0])+" capsule query against "+str(spec.kind))
   probe_pair(pair_shapes[index],spec,cap,cap_spec,target_pose,pair_query_pose,
    str(arrangement[0])+" "+str(spec.kind)+" query against capsule")

 stage="ownership"
 var first_body:=make_body(cap)
 PhysicsServer3D.body_add_shape(first_body,cap,Transform3D(Basis.IDENTITY,Vector3(.1,0,0)))
 var second_body:=make_body(cap)
 q=query(cap)
 var full:=state.intersect_shape(q)
 var ordered:=full.size()==3
 for index in range(1,full.size()):
  var previous_id: int=full[index-1].rid.get_id()
  var current_id: int=full[index].rid.get_id()
  ordered=ordered and (previous_id<current_id or (previous_id==current_id and full[index-1].shape<full[index].shape))
 check(ordered,"capsule multi-shape results sort by RID and native shape index")
 var stable:=true
 for repeat in 3:stable=stable and state.intersect_shape(q)==full
 check(stable,"capsule multi-shape repeated ordering is stable")
 check(state.intersect_shape(q,1).size()==1 and state.collide_shape(q,1).size()==2 and point(Vector3.ZERO,1,[],1).size()==1,
  "capsule max_results counts shapes versus contact pairs")
 check(state.intersect_shape(q,0).is_empty() and state.collide_shape(q,0).is_empty() and point(Vector3.ZERO,1,[],0).is_empty(),
  "capsule zero capacity returns empty")
 # Compile valid dynamic geometry, then deliberately make its candidate mass invalid.
 PhysicsServer3D.body_set_mode(first_body,PhysicsServer3D.BODY_MODE_RIGID)
 state.intersect_shape(q)
 PhysicsServer3D.body_set_param(first_body,PhysicsServer3D.BODY_PARAM_MASS,1e-20)
 check(state.intersect_shape(q).is_empty() and point(Vector3.ZERO).is_empty() and state.collide_shape(q).is_empty() and state.get_rest_info(q).is_empty(),
  "failed capsule rebuild does not expose old query geometry")
 PhysicsServer3D.body_set_param(first_body,PhysicsServer3D.BODY_PARAM_MASS,1.0)
 check(state.intersect_shape(q).size()==3,"capsule overlap recovers after rejected rebuild")
 remove_body(first_body);remove_body(second_body)
 var disposable:=capsule(.4,1.4)
 var orphan:=make_body(disposable)
 state.intersect_shape(q)
 PhysicsServer3D.free_rid(disposable);owned.erase(disposable)
 check(PhysicsServer3D.body_get_shape_count(orphan)==0 and state.intersect_shape(q).is_empty() and point(Vector3.ZERO).is_empty(),
  "free capsule shape RID clears body dependencies and old geometry")
 remove_body(orphan)

 for rid in owned: PhysicsServer3D.free_rid(rid)
 owned.clear()
 PhysicsServer3D.free_rid(space)

 # Actual scene nodes validate CapsuleShape3D, dynamics and automatic inertia.
 stage="dynamics"
 var scene:=Node3D.new();root.add_child(scene)
 var floor_body:=StaticBody3D.new()
 var floor_shape:=CollisionShape3D.new();floor_shape.shape=WorldBoundaryShape3D.new()
 floor_body.add_child(floor_shape);scene.add_child(floor_body)
 var falling:=RigidBody3D.new();falling.mass=4;falling.position=Vector3(0,4,0)
 var collision:=CollisionShape3D.new();var resource:=CapsuleShape3D.new()
 resource.height=3;resource.radius=.5;collision.shape=resource
 falling.add_child(collision);scene.add_child(falling)
 await ticks(180)
 check(PhysicsServer3D.shape_get_type(resource.get_rid())==PhysicsServer3D.SHAPE_CAPSULE and is_equal_approx(resource.height,3),"ordinary CapsuleShape3D resource uses native capsule")
 check(absf(falling.position.y-1.5)<.04 and falling.linear_velocity.length()<.1,"dynamic capsule settles at half full height")
 var body_state:=PhysicsServer3D.body_get_direct_state(falling.get_rid())
 check(absf(body_state.inverse_mass-.25)<.001,"capsule automatic mass")
 # Uniform-density cylinder plus hemispheres. L is cylinder length, not height.
 var radius:=.5;var length:=2.0;var mass:=4.0
 var cylinder_mass:=mass*length/(length+4*radius/3)
 var hemisphere_mass:=mass-cylinder_mass
 var axial:=cylinder_mass*radius*radius*.5+hemisphere_mass*radius*radius*.4
 var transverse:=cylinder_mass*(3*radius*radius+length*length)/12+hemisphere_mass*(.4*radius*radius+.25*length*length+.375*length*radius)
 var inverse:=body_state.inverse_inertia
 check(absf(inverse.y-1/axial)<.02 and absf(inverse.x-1/transverse)<.02 and absf(inverse.z-1/transverse)<.02,"automatic capsule inertia includes hemisphere offsets")
 falling.gravity_scale=0;falling.position=Vector3(0,5,0);falling.linear_velocity=Vector3.RIGHT
 await ticks(2)
 var before:=falling.position
 resource.height=3.4;await ticks(2)
 check(falling.position.x>before.x and falling.linear_velocity.x>.95 and absf(falling.position.y-before.y)<.02,"capsule resize preserves live velocity and pose")
 resource.height=1.0
 await ticks(2)
 body_state=PhysicsServer3D.body_get_direct_state(falling.get_rid())
 inverse=body_state.inverse_inertia
 check(inverse.distance_to(Vector3.ONE/(.4*4*.5*.5))<.04,"degenerate capsule automatic inertia is spherical")
 stage="area"
 var monitor:=Area3D.new();monitor.position=Vector3(20,0,0)
 var monitor_shape:=CollisionShape3D.new();var monitor_resource:=CapsuleShape3D.new()
 monitor_resource.radius=.5;monitor_resource.height=3;monitor_shape.shape=monitor_resource
 monitor.add_child(monitor_shape);scene.add_child(monitor)
 var tracked:=StaticBody3D.new();tracked.position=Vector3(20,2.5,0)
 var tracked_shape:=CollisionShape3D.new();var tracked_resource:=CapsuleShape3D.new()
 tracked_resource.radius=.5;tracked_resource.height=3;tracked_shape.shape=tracked_resource
 tracked.add_child(tracked_shape);scene.add_child(tracked)
 var other_area:=Area3D.new();other_area.position=monitor.position
 var other_shape:=CollisionShape3D.new();other_shape.shape=CapsuleShape3D.new()
 other_area.add_child(other_shape);scene.add_child(other_area)
 await ticks(4)
 check(monitor.get_overlapping_bodies().has(tracked),"capsule Area sees capsule body across rounded caps")
 check(monitor.get_overlapping_areas().has(other_area),"capsule Area sees concentric capsule Area")
 monitor_resource.height=1;await ticks(4)
 check(not monitor.get_overlapping_bodies().has(tracked),"capsule Area sphere degeneration updates exit")
 monitor_resource.height=3;await ticks(4)
 check(monitor.get_overlapping_bodies().has(tracked),"capsule Area resize reenters")
 tracked.queue_free();other_area.queue_free();await ticks(4)
 check(monitor.get_overlapping_bodies().is_empty() and monitor.get_overlapping_areas().is_empty(),"capsule Area frees retire overlaps")
 scene.queue_free();await ticks(3)
 print("CAPSULE_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"counts":counts,"godot":Engine.get_version_info().string}))
 quit(0 if failed==0 else 1)
