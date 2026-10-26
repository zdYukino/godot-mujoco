extends SceneTree
const Session=preload("res://addons/godot_mujoco/map/session.gd")
var passed:=0
var failed:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var rows: Array=[]
	for depth in [3,4,6]:
		var session:=Session.new();check(session.import_file("res://assets/terrain.obj","m","Y_UP"),"convergence source import")
		for mesh in session.meshes():
			var path:=str(session.visual.get_path_to(mesh))
			check(session.configure(path,{"kind":"sdf","octree_maxdepth":depth}),"convergence depth%d config" % depth)
		var built:=session.build_scene()
		check(built.error.is_empty(),"convergence build")
		if built.error.is_empty():
			var viewport:=SubViewport.new();viewport.own_world_3d=true;root.add_child(viewport)
			var scene: Node3D=built.scene;viewport.add_child(scene)
			for i in 3:await physics_frame;await process_frame
			var space: RID=scene.get_world_3d().space;PhysicsServer3D.call("scene_pause",space,true)
			var q:=PhysicsRayQueryParameters3D.create(Vector3(0,2,0),Vector3(0,-1,0),1);q.collide_with_areas=false
			var state: PhysicsDirectSpaceState3D=scene.get_world_3d().direct_space_state
			var hit: Dictionary=state.intersect_ray(q)
			check(not hit.is_empty() and hit.position.y<-.25 and absf(hit.position.y+.35)<.07,"depth%d preserves depression with independently queried floor" % depth)
			rows.append({"depth":depth,"floor_y":hit.get("position",Vector3.INF).y,"error_m":absf(hit.get("position",Vector3.INF).y+.35)})
			viewport.queue_free()
			for i in 3:await physics_frame;await process_frame
		session.close()
	print("SDF_CONVERGENCE_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"pit_plateau_width_m":.9,"resolution_samples":rows}))
	quit(0 if failed==0 else 1)
