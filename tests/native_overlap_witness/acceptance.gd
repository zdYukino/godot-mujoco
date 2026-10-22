extends SceneTree

# Independent analytic surfaces; these checks do not reproduce native contact
# reconstruction or assert only that a narrowphase returned a nonempty result.
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var owned: Array[RID] = []
var space: RID
var state: PhysicsDirectSpaceState3D
const EPSILON := 0.003

func check(ok: bool, label: String, detail: Variant = "") -> void:
 checks.append({"passed": ok, "label": label, "detail": detail})
 print("PASS " if ok else "FAIL ", label, " ", detail)

func surface_error(p: Vector3, spec: Dictionary, pose: Transform3D) -> float:
 var local := pose.affine_inverse() * p
 if spec.kind == "box":
  var delta: Vector3 = local.abs() - spec.extents
  return absf(delta.max(Vector3.ZERO).length() + minf(maxf(delta.x,maxf(delta.y,delta.z)),0))
 var delta := Vector2(Vector2(local.x,local.z).length()-float(spec.radius),absf(local.y)-float(spec.height)*.5)
 return absf(delta.max(Vector2.ZERO).length()+minf(maxf(delta.x,delta.y),0))

func outward_normal(point: Vector3, normal: Vector3, spec: Dictionary, pose: Transform3D) -> bool:
 var p=pose.affine_inverse()*point
 var n=pose.basis.inverse()*normal
 if spec.kind=="box":
  for i in 3:
   if absf(absf(p[i])-spec.extents[i])<EPSILON:
    if n[i]*signf(p[i]) < -EPSILON:return false
   elif absf(n[i])>EPSILON:return false
  return true
 var radial=Vector2(p.x,p.z)
 var radial_normal=Vector2(n.x,n.z)
 if absf(radial.length()-float(spec.radius))<EPSILON:
  var direction=radial.normalized()
  if direction.dot(radial_normal)<-EPSILON or absf(Vector2(-direction.y,direction.x).dot(radial_normal))>EPSILON:return false
 elif radial_normal.length()>EPSILON:return false
 if absf(absf(p.y)-float(spec.height)*.5)<EPSILON:
  if n.y*signf(p.y)<-EPSILON:return false
 elif absf(n.y)>EPSILON:return false
 return true

func shape(spec: Dictionary) -> RID:
 var rid: RID
 if spec.kind == "box":
  rid=PhysicsServer3D.box_shape_create()
  PhysicsServer3D.shape_set_data(rid,spec.extents)
 else:
  rid=PhysicsServer3D.cylinder_shape_create()
  PhysicsServer3D.shape_set_data(rid,{"radius":spec.radius,"height":spec.height})
 owned.append(rid)
 return rid

func probe(label: String, query_spec: Dictionary, target_spec: Dictionary, query_pose: Transform3D, target_pose: Transform3D) -> void:
 var target := PhysicsServer3D.body_create()
 PhysicsServer3D.body_set_mode(target,PhysicsServer3D.BODY_MODE_STATIC)
 PhysicsServer3D.body_add_shape(target,shape(target_spec))
 PhysicsServer3D.body_set_state(target,PhysicsServer3D.BODY_STATE_TRANSFORM,target_pose)
 PhysicsServer3D.body_set_space(target,space)
 var query := PhysicsShapeQueryParameters3D.new()
 query.shape_rid=shape(query_spec)
 query.transform=query_pose
 query.margin=0
 var hits := state.intersect_shape(query)
 check(hits.size()==1 and hits[0].rid==target and hits[0].shape==0,label+" overlap identity")
 var contacts := state.collide_shape(query,32)
 check(contacts.size()>=2 and contacts.size()%2==0,label+" nonempty witness pairs",contacts.size())
 var nondegenerate:=contacts.size()>=2
 var max_query_error := 0.0
 var max_target_error := 0.0
 var finite := true
 for i in range(0,contacts.size()-1,2):
  nondegenerate=nondegenerate and contacts[i].distance_to(contacts[i+1])>.1
  finite=finite and contacts[i].is_finite() and contacts[i+1].is_finite()
  max_query_error=maxf(max_query_error,surface_error(contacts[i],query_spec,query_pose))
  max_target_error=maxf(max_target_error,surface_error(contacts[i+1],target_spec,target_pose))
 check(finite and max_query_error<EPSILON,label+" every query witness lies on query surface",max_query_error)
 check(finite and max_target_error<EPSILON,label+" every target witness lies on target surface",max_target_error)
 check(nondegenerate,label+" deep penetration retains nonzero witness separation")
 var rest := state.get_rest_info(query)
 check(not rest.is_empty() and rest.rid==target and rest.shape==0,label+" rest identity")
 if not rest.is_empty():
  check(rest.normal.is_finite() and absf(rest.normal.length()-1)<.0001,label+" finite unit rest normal",rest.normal)
  check(outward_normal(rest.point,rest.normal,target_spec,target_pose),label+" rest normal belongs to target outward normal cone",rest.normal)
  check(rest.point.is_finite() and surface_error(rest.point,target_spec,target_pose)<EPSILON,label+" rest point lies on target surface",{"point":rest.point,"error":surface_error(rest.point,target_spec,target_pose)})
 samples.append({"label":label,"contacts":contacts,"query_surface_error":max_query_error,"target_surface_error":max_target_error,"rest":rest})
 PhysicsServer3D.free_rid(target)

func _initialize() -> void: call_deferred("run")
func run() -> void:
 check(PhysicsServer3D.get_class()=="MjPhysicsServer3D","native backend identity")
 space=PhysicsServer3D.space_create()
 state=PhysicsServer3D.space_get_direct_state(space)
 var small_cylinder := {"kind":"cylinder","radius":.35,"height":.6}
 var large_cylinder := {"kind":"cylinder","radius":1.4,"height":3.4}
 var small_box := {"kind":"box","extents":Vector3(.25,.3,.2)}
 var large_box := {"kind":"box","extents":Vector3(1.6,1.8,1.5)}
 var pose := Transform3D(Basis.IDENTITY,Vector3(3,-2,5))
 var rotated := Transform3D(Basis.from_euler(Vector3(.41,-.28,.67)),pose.origin)
 var tilted := Transform3D(Basis.from_euler(Vector3(-.52,.63,-.19)),pose.origin)
 var offset=Vector3(.123,.17,-.234)
 for arrangement in [["aligned",pose,pose],["shared rotation",rotated,rotated],["different rotations",rotated,tilted],
  ["offset aligned",pose,Transform3D(pose.basis,pose.origin+offset)],
  ["offset shared rotation",rotated,Transform3D(rotated.basis,rotated.origin+offset)],
  ["offset different rotations",rotated,Transform3D(tilted.basis,tilted.origin+offset)]]:
  var name: String=arrangement[0]
  var query_pose: Transform3D=arrangement[1]
  var target_pose: Transform3D=arrangement[2]
  probe(name+" small cylinder in large cylinder",small_cylinder,large_cylinder,query_pose,target_pose)
  probe(name+" large cylinder around small cylinder",large_cylinder,small_cylinder,query_pose,target_pose)
  probe(name+" cylinder in large box",small_cylinder,large_box,query_pose,target_pose)
  probe(name+" large box around cylinder",large_box,small_cylinder,query_pose,target_pose)
  probe(name+" small box in cylinder",small_box,large_cylinder,query_pose,target_pose)
  probe(name+" cylinder around small box",large_cylinder,small_box,query_pose,target_pose)
 for rid in owned: PhysicsServer3D.free_rid(rid)
 PhysicsServer3D.free_rid(space)
 var failed := checks.filter(func(item):return not item.passed).size()
 print("OVERLAP_WITNESS_RESULT ",JSON.stringify({"passed":checks.size()-failed,"failed":failed,"checks":checks,"samples":samples,"surface_tolerance":EPSILON,"godot":Engine.get_version_info().string}))
 quit(0 if failed==0 else 1)
