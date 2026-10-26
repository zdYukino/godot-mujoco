extends "res://query_test_base.gd"
func run() -> void:
	var space:=PhysicsServer3D.space_create()
	var state: PhysicsDirectSpaceState3D=PhysicsServer3D.space_get_direct_state(space)
	var sphere:=PhysicsServer3D.sphere_shape_create();PhysicsServer3D.shape_set_data(sphere,.5)
	var body:=PhysicsServer3D.body_create();PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_RIGID);PhysicsServer3D.body_add_shape(body,sphere);PhysicsServer3D.body_set_space(body,space)
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(-2,0,0),Vector3(2,0,0));ray.collide_with_areas=false
	check(not state.intersect_ray(ray).is_empty() and state.call("get_query_status").ok,"initial physical ray succeeds")
	var seq: int=state.call("get_query_status").sequence
	PhysicsServer3D.body_set_param(body,PhysicsServer3D.BODY_PARAM_MASS,1e-20)
	for repeat in 2:
		check(state.intersect_ray(ray).is_empty() and not state.call("get_query_status").ok and str(state.call("get_query_status").error).contains("rebuild"),"failed rebuild ray is observable on every request")
	check(state.call("get_query_status").sequence==seq+2,"failed ray sequence advances twice")
	PhysicsServer3D.body_set_param(body,PhysicsServer3D.BODY_PARAM_MASS,1)
	check(not state.intersect_ray(ray).is_empty() and state.call("get_query_status").ok,"successful ray after rebuild resets old error")
	seq=state.call("get_query_status").sequence
	for repeat in 2:
		state.call("get_closest_point_to_object_volume",body,Vector3.ZERO)
		var status: Dictionary=state.call("get_query_status")
		check(not status.ok and status.kind=="closest_point" and str(status.error).contains("closest_point"),"unsupported closest point has its own fresh status")
	check(state.call("get_query_status").sequence==seq+2,"repeated closest-point sequence is fresh")
	check(not state.intersect_ray(ray).is_empty() and state.call("get_query_status").ok and state.call("get_query_status").kind=="ray","success after repeated closest-point resets status")
	ray.from=Vector3(NAN,0,0)
	check(state.intersect_ray(ray).is_empty() and not state.call("get_query_status").ok,"non-finite ray input is observable")
	var point:=PhysicsPointQueryParameters3D.new();point.position=Vector3(NAN,0,0)
	check(state.intersect_point(point).is_empty() and not state.call("get_query_status").ok,"non-finite point input is observable")
	ray.from=Vector3(-2,0,0)
	check(not state.intersect_ray(ray).is_empty() and state.call("get_query_status").ok,"success resets non-finite input failures")
	for rid in [body,sphere,space]:PhysicsServer3D.free_rid(rid)
	print("QUERY_STATUS_RESULT ",JSON.stringify({"passed":passed,"failed":failed}));quit(0 if failed==0 else 1)
