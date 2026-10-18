extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var world: Node=ClassDB.instantiate("MjWorld")
 root.add_child(world)
 var loaded: bool=world.load_model_from_string('<mujoco><worldbody><body><joint type="hinge"/><geom type="sphere" size=".1"/></body></worldbody></mujoco>') and world.get_nq()==1
 if not loaded: world.free();printerr("Negative fixture failed to load");quit(1);return
 var before: PackedFloat64Array=world.get_qpos()
 var rejected: bool=not world.set_qpos(PackedFloat64Array([1.0,2.0,3.0]))
 var unchanged: bool=world.get_qpos()==before
 world.free();await process_frame
 var failed:=int(not rejected)+int(not unchanged)
 print("MJWORLD_NEGATIVE_RESULT ",JSON.stringify({"checks":3,"failed":failed,"rejected":rejected,"unchanged":unchanged}))
 quit(0 if failed==0 else 1)
