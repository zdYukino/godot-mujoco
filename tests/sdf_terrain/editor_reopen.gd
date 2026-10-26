extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host=load("res://TerrainHost.tscn").instantiate();root.add_child(host)
	for i in 3:await physics_frame;await process_frame
	var map=host.get_node("StaticMap");var space: RID=host.get_world_3d().space
	PhysicsServer3D.call("scene_pause",space,true)
	var q:=PhysicsRayQueryParameters3D.create(Vector3(0,2,0),Vector3(0,-1,0),1);q.collide_with_areas=false
	var state: PhysicsDirectSpaceState3D=host.get_world_3d().direct_space_state
	var hit: Dictionary=state.intersect_ray(q)
	var ok: bool=map.native_rids.size()==3 and not hit.is_empty() and absf(hit.position.y+.35)<.035 and state.call("get_query_status").ok
	for rid in map.native_rids:
		var geometry: Array=PhysicsServer3D.call("scene_geometry",space,rid)
		ok=ok and not geometry.is_empty() and geometry.all(func(g):return g.type==8)
	print("SDF_EDITOR_REOPEN_RESULT ",JSON.stringify({"passed":1 if ok else 0,"failed":0 if ok else 1,"pit_hit":hit}))
	host.free();await process_frame;quit(0 if ok else 1)
