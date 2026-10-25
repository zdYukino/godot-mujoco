extends SceneTree
var failed:=0
var passed:=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var host=load("res://MovedMap.tscn").instantiate(); root.add_child(host)
	await process_frame
	var map=host.get_node("StaticMap")
	check(map.last_error.is_empty() and map.native_rids.size()>0,"saved moved map reopens with real native collisions")
	for path in map.get_meta("expected_visual_transforms"):
		check(map.get_node(path).global_transform.is_equal_approx(map.get_meta("expected_visual_transforms")[path]),"saved visual retains transformed world position "+path)
	for body in map.get_node("Physics").get_children():
		check(PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM).is_equal_approx(body.global_transform),"ordinary backend body matches moved authored physics node")
	for i in map.native_collisions.size():
		var entry: Dictionary=map.native_collisions[i]
		var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
		check(doc.restore(entry.snapshot),"native collision snapshot restores")
		var actual: Array=PhysicsServer3D.call("scene_geometry",map.get_world_3d().space,map.native_rids[i])
		for geom in doc.geometry():
			var matches=actual.filter(func(item): return str(item.name).ends_with(str(geom.name)))
			check(matches.size()==1 and matches[0].transform.is_equal_approx(map.global_transform*entry.pose*geom.transform),"actual native mjModel geometry follows saved moved root "+str(geom.name))
	host.free(); await process_frame
	print("MAP_GIZMO_RUNTIME_RESULT ",JSON.stringify({"passed":passed,"failed":failed}))
	quit(0 if failed==0 else 1)
