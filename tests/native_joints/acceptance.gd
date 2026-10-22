extends SceneTree
var checks:Array[Dictionary]=[]
var resources:Array[RID]=[]
var joints:Array[RID]=[]
var space:RID
var sequence_done:=false
var collision_reports:Array[int]=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String,detail:Variant=""):
 checks.append({"name":label,"passed":ok,"detail":str(detail)})
 print("PASS " if ok else "FAIL ",label," ",detail)
func ticks(n:int=1):
 for i in n:await physics_frame;await process_frame
func body(at:Vector3,mode:int=PhysicsServer3D.BODY_MODE_RIGID)->RID:
 var shape=PhysicsServer3D.sphere_shape_create();resources.append(shape);PhysicsServer3D.shape_set_data(shape,.2)
 var id=PhysicsServer3D.body_create();resources.append(id)
 PhysicsServer3D.body_set_mode(id,mode);PhysicsServer3D.body_add_shape(id,shape)
 PhysicsServer3D.body_set_param(id,PhysicsServer3D.BODY_PARAM_LINEAR_DAMP_MODE,PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
 PhysicsServer3D.body_set_param(id,PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP_MODE,PhysicsServer3D.BODY_DAMP_MODE_REPLACE)
 PhysicsServer3D.body_set_state(id,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,at));PhysicsServer3D.body_set_space(id,space)
 return id
func pose(id:RID)->Transform3D:return PhysicsServer3D.body_get_state(id,PhysicsServer3D.BODY_STATE_TRANSFORM)
func velocity(id:RID)->Vector3:return PhysicsServer3D.body_get_state(id,PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
func pin(a:RID,anchor_a:Vector3,b:RID=RID(),anchor_b:Vector3=Vector3.ZERO)->RID:
 var id=PhysicsServer3D.joint_create();joints.append(id)
 PhysicsServer3D.joint_make_pin(id,a,anchor_a,b,anchor_b)
 check(PhysicsServer3D.joint_get_type(id)==PhysicsServer3D.JOINT_TYPE_PIN,"make Pin returns actual type")
 return id
func step(n:int):
 var request:int=PhysicsServer3D.call("scene_request_world_command",space,"step",n)
 var result:Dictionary={}
 for i in 30:
  await ticks()
  result=PhysicsServer3D.call("scene_world_command_result",request)
  if not result.is_empty():break
 check(request>0 and result.get("success",false),"bounded exact step completes",result)
 await ticks()
func setup():
 check(PhysicsServer3D.get_class()=="MjPhysicsServer3D","native backend identity")
 space=PhysicsServer3D.space_create();resources.append(space);PhysicsServer3D.space_set_active(space,true)
 check(PhysicsServer3D.call("scene_pause",space,true),"pause isolated world")
 var file=FileAccess.open("res://world.xml",FileAccess.WRITE);file.store_string('<mujoco><option timestep=".01" gravity="0 0 -10"/><worldbody/></mujoco>');file.close()
 var doc:RefCounted=ClassDB.instantiate("MjEditorDocument")
 check(doc.import_file("res://world.xml") and PhysicsServer3D.call("scene_configure_model",space,doc.snapshot(),"res://"),"configure lightweight exact-step world")
func finish(prefix:String="PIN_RESULT"):
 for joint in joints:PhysicsServer3D.free_rid(joint)
 joints.clear();resources.reverse()
 for id in resources:PhysicsServer3D.free_rid(id)
 resources.clear();await ticks(2)
 var failed=checks.filter(func(item):return not item.passed).size()
 print(prefix," ",JSON.stringify({"passed":checks.size()-failed,"failed":failed,"checks":checks}))
 quit(0 if failed==0 else 1)
func run():
 setup()
 var a=body(Vector3(0,-1,0));var fixed=pin(a,Vector3.UP)
 check(PhysicsServer3D.pin_joint_get_local_a(fixed)==Vector3.UP and PhysicsServer3D.pin_joint_get_local_b(fixed)==Vector3.ZERO,"local/world anchor readback")
 check(abs(PhysicsServer3D.pin_joint_get_param(fixed,PhysicsServer3D.PIN_JOINT_BIAS)-.3)<1e-6 and PhysicsServer3D.pin_joint_get_param(fixed,PhysicsServer3D.PIN_JOINT_DAMPING)==1 and PhysicsServer3D.pin_joint_get_param(fixed,PhysicsServer3D.PIN_JOINT_IMPULSE_CLAMP)==0,"fixed compatibility parameter defaults")
 var before=pose(a);await ticks(4);check(pose(a)==before,"paused Pin does not advance")
 PhysicsServer3D.body_apply_central_impulse(a,Vector3.RIGHT)
 await step(50)
 var anchor=pose(a)*Vector3.UP
 check(anchor.length()<.03,"world Pin constrains anchor under gravity",anchor)
 check(abs(pose(a).origin.x)>.05 and not pose(a).basis.is_equal_approx(Basis.IDENTITY),"Pin preserves pendulum rotation rather than welding",pose(a))
 var old_v=velocity(a);var old_pose=pose(a)
 PhysicsServer3D.body_set_param(a,PhysicsServer3D.BODY_PARAM_FRICTION,.4)
 check(PhysicsServer3D.call("scene_pause",space,true),"rebuild paused joint world")
 check(velocity(a).distance_to(old_v)<.00001 and pose(a).is_equal_approx(old_pose),"rebuild preserves body pose and velocity")
 await step(10);check((pose(a)*Vector3.UP).length()<.03,"constraint survives unrelated rebuild")
 var updated=Vector3(.2,1,0);var world_anchor=pose(a)*updated
 PhysicsServer3D.pin_joint_set_local_a(fixed,updated);PhysicsServer3D.pin_joint_set_local_b(fixed,world_anchor)
 await step(10)
 check((pose(a)*updated).distance_to(world_anchor)<.03,"updated local and world anchors physically constrain")
 var a2=body(Vector3(5,1,0));var b2=body(Vector3(5,0,0));var paired=pin(a2,Vector3.DOWN*.5,b2,Vector3.UP*.5)
 PhysicsServer3D.body_apply_central_impulse(b2,Vector3(1,0,.4));await step(40)
 check((pose(a2)*(Vector3.DOWN*.5)).distance_to(pose(b2)*(Vector3.UP*.5))<.03,"dynamic pair anchor positions agree")
 check(pose(a2).origin.y<1 and pose(b2).origin.y<0,"dynamic pair remains free to fall")
 var support=body(Vector3(10,1,0),PhysicsServer3D.BODY_MODE_STATIC);var bob=body(Vector3(10,0,0));var supported=pin(bob,Vector3.UP,support)
 await step(20);check((pose(bob)*Vector3.UP).distance_to(pose(support).origin)<.03,"static endpoint constrains dynamic anchor")
 PhysicsServer3D.body_set_state(support,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,Vector3(10.2,1,0)))
 await step(40);check((pose(bob)*Vector3.UP).distance_to(pose(support).origin)<.03,"moving static endpoint updates constraint")
 var c=body(Vector3(15,0,0));var d=body(Vector3(15,0,0));var collision_pin=pin(c,Vector3.ZERO,d)
 PhysicsServer3D.body_set_max_contacts_reported(c,8)
 PhysicsServer3D.body_set_state_sync_callback(c,func(state):collision_reports.append(state.get_contact_count()))
 PhysicsServer3D.joint_disable_collisions_between_bodies(collision_pin,true);await step(3)
 check(collision_reports.size()==1 and collision_reports[0]==0,"joint collision disable suppresses real pair contacts")
 collision_reports.clear()
 PhysicsServer3D.joint_disable_collisions_between_bodies(collision_pin,false);await step(3)
 check(collision_reports.size()==1 and collision_reports[0]>0,"reenabling joint pair collision restores contact")
 PhysicsServer3D.joint_disable_collisions_between_bodies(collision_pin,true)
 PhysicsServer3D.joint_clear(fixed)
 check(PhysicsServer3D.joint_get_type(fixed)==PhysicsServer3D.JOINT_TYPE_MAX,"clear returns unconfigured joint")
 var released=pose(a).origin;PhysicsServer3D.body_apply_central_impulse(a,Vector3(0,-2,0));await step(30)
 check(pose(a).origin.distance_to(released)>.1,"cleared joint no longer constrains body")
 var new_world_anchor=pose(a)*Vector3.UP
 PhysicsServer3D.joint_make_pin(fixed,a,Vector3.UP,RID(),new_world_anchor);await step(30)
 check((pose(a)*Vector3.UP).distance_to(new_world_anchor)<.03,"cleared joint RID can be reconfigured")
 PhysicsServer3D.free_rid(support);resources.erase(support)
 check(PhysicsServer3D.joint_get_type(supported)==PhysicsServer3D.JOINT_TYPE_MAX,"deleted endpoint clears joint without destroying its RID")
 var bob_y=pose(bob).origin.y;await step(30);check(pose(bob).origin.y<bob_y-.05,"deleted endpoint leaves dynamic body free")
 PhysicsServer3D.body_set_space(b2,RID())
 check(PhysicsServer3D.joint_get_type(paired)==PhysicsServer3D.JOINT_TYPE_MAX,"endpoint detachment clears joint")
 PhysicsServer3D.body_set_space(b2,space)
 var point=pose(a2)*(Vector3.DOWN*.5)
 PhysicsServer3D.joint_make_pin(paired,a2,Vector3.DOWN*.5,b2,pose(b2).affine_inverse()*point)
 await step(20)
 check((pose(a2)*(Vector3.DOWN*.5)).distance_to(pose(b2)*PhysicsServer3D.pin_joint_get_local_b(paired))<.03,"readded endpoint and reused joint constrain again")
 var callback_body=body(Vector3(30,-1,0));var callback_joint=PhysicsServer3D.joint_create();joints.append(callback_joint)
 PhysicsServer3D.body_set_force_integration_callback(callback_body,func(_state):
  if sequence_done:return
  sequence_done=true
  PhysicsServer3D.joint_make_pin(callback_joint,callback_body,Vector3.UP,RID(),Vector3(30,0,0))
  PhysicsServer3D.body_set_mode(callback_body,PhysicsServer3D.BODY_MODE_STATIC))
 await step(1);await ticks(2)
 check(sequence_done and PhysicsServer3D.body_get_mode(callback_body)==PhysicsServer3D.BODY_MODE_STATIC and PhysicsServer3D.joint_get_type(callback_joint)==PhysicsServer3D.JOINT_TYPE_MAX,"callback make then mode change executes FIFO and clears joint")
 # Persist actual Godot joint nodes, not just server RIDs, then reopen.
 var design=Node3D.new();design.name="SavedPinRoot"
 var saved_bob=RigidBody3D.new();saved_bob.name="SavedBob";saved_bob.position=Vector3(0,-1,0);design.add_child(saved_bob);saved_bob.owner=design
 var saved_shape=CollisionShape3D.new();saved_shape.shape=SphereShape3D.new();saved_shape.shape.radius=.2;saved_bob.add_child(saved_shape);saved_shape.owner=design
 var saved_pin=PinJoint3D.new();saved_pin.name="SavedPin";saved_pin.node_a=NodePath("../SavedBob");design.add_child(saved_pin);saved_pin.owner=design
 var packed=PackedScene.new();check(packed.pack(design)==OK and ResourceSaver.save(packed,"res://SavedPin.tscn")==OK,"save real PinJoint3D scene")
 design.free()
 var viewport=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
 var previous_space=space;space=viewport.find_world_3d().space
 PhysicsServer3D.call("scene_pause",space,true)
 var saved_doc:RefCounted=ClassDB.instantiate("MjEditorDocument");saved_doc.import_file("res://world.xml")
 check(PhysicsServer3D.call("scene_configure_model",space,saved_doc.snapshot(),"res://"),"configure reopened scene world")
 var reopened=load("res://SavedPin.tscn").instantiate();viewport.add_child(reopened);await ticks(2)
 saved_bob=reopened.get_node("SavedBob");saved_pin=reopened.get_node("SavedPin")
 check(saved_pin.node_a==NodePath("../SavedBob") and PhysicsServer3D.joint_get_type(saved_pin.get_rid())==PhysicsServer3D.JOINT_TYPE_PIN,"reopened node paths create real Pin")
 check(PhysicsServer3D.pin_joint_get_local_a(saved_pin.get_rid()).is_equal_approx(Vector3.UP),"reopened node derives correct local anchor")
 saved_bob.apply_central_impulse(Vector3.RIGHT);await step(50)
 check((saved_bob.global_transform*Vector3.UP).length()<.03 and abs(saved_bob.position.x)>.05,"reopened Pin remains constrained while rotating")
 viewport.queue_free();await ticks(3);space=previous_space
 await finish()
