extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Collision = preload("res://addons/godot_mujoco/model/collision_settings.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
var checks := 0
var failures := []
var service: Node
var observed_model_stats := []
var observed_runtime_stats := []
var observed_open_surface_error := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ",label)

func edit(design: Resource, id: String, field: String, value: Variant) -> void:
	var result := Commands.execute(design,{"op":"collision","id":id,"field":field,"value":value})
	check(result.error.is_empty(), "edit " + field + ": " + result.error)
	if result.error.is_empty(): check(design.restore_author(result.after).is_empty(),"restore collision snapshot")

func compile_design(design: Resource, overrides := {}) -> Dictionary:
	var context := Collision.context(null,design)
	context.collision_options.merge(overrides,true)
	var output := {}
	var listener := func(result): output.merge(result)
	service.completed.connect(listener)
	service.submit({"author":design.author_snapshot(),"generation":design.document_id,"context":context})
	var until := Time.get_ticks_msec()+30000
	while output.is_empty() and Time.get_ticks_msec()<until: await process_frame
	service.completed.disconnect(listener)
	return output

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var file := FileAccess.open("res://depth-shared.obj",FileAccess.WRITE)
	file.store_string("v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n");file.close()
	var source := '<mujoco><asset><mesh name="shared" file="res://depth-shared.obj" scale=".005 .005 .005"/></asset><worldbody><geom name="first" type="mesh" mesh="shared"/><geom name="second" type="mesh" mesh="shared" pos=".01 0 0"/></worldbody></mujoco>'
	var design: Resource = Author.from_xml(source).design
	design.dependencies = {"res://depth-shared.obj":FileAccess.get_sha256("res://depth-shared.obj")}
	var first: String = design.entities()[0].id
	var second: String = design.entities()[1].id
	edit(design,first,"mode","sdf");edit(design,second,"mode","sdf")
	edit(design,first,"sdf_depth",3);edit(design,second,"sdf_depth",5)
	var a := Collision.mesh_asset(design,Xml.find(design.tree,first))
	var b := Collision.mesh_asset(design,Xml.find(design.tree,second))
	check(a.id != b.id and a.attrs.file == b.attrs.file,"independent collision assets share the same immutable source file")
	check(design.native_mesh_options()[a.attrs.name].octree_maxdepth == 3 and design.native_mesh_options()[b.attrs.name].octree_maxdepth == 5,"stable IDs resolve native mesh names")
	check(not design.xml().contains("octree_maxdepth"),"native-only depth never enters MJCF XML")
	check(ResourceSaver.save(design,"res://collision-design.tres") == OK,"save precision in Godot resource")
	design = ResourceLoader.load("res://collision-design.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(design.mesh_options.size() == 2,"reopen retains both depths")
	service = Service.new();root.add_child(service)
	var result := await compile_design(design,{"nativeccd":false,"ccd_iterations":12})
	check(result.get("success",false),"same-file SDF depths compile with millimeter parts: " + str(result.get("error","timeout")))
	if result.get("success",false):
		observed_model_stats = result.collision_stats.duplicate(true)
		var stats := {}
		for stat in result.collision_stats: stats[stat.mesh]=stat
		check(stats[a.attrs.name].depth == 3 and stats[b.attrs.name].depth == 5,"actual octree depths bypass the MuJoCo asset-cache collision")
		check(stats[a.attrs.name].cells < stats[b.attrs.name].cells,"higher depth produces more actual octree cells")
		var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
		check(document.restore_compiled(result.snapshot,result.compiled_path),"MJB restores custom-depth candidate")
		var xml: String = result.snapshot.xml
		check(xml.contains('nativeccd="disable"') and xml.contains('ccd_iterations="12"'),"model compiler uses effective world collision options")
	var copied := Commands.execute(design,{"op":"duplicate","id":first})
	design.restore_author(copied.after)
	var duplicate: String = copied.selected
	edit(design,first,"sdf_depth",4)
	check(Collision.mesh_asset(design,Xml.find(design.tree,first)).id != Collision.mesh_asset(design,Xml.find(design.tree,duplicate)).id,"editing original after duplicate isolates mesh options")
	edit(design,duplicate,"sdf_depth",6)
	check(design.mesh_options[Collision.mesh_asset(design,Xml.find(design.tree,first)).id].octree_maxdepth == 4,"editing duplicate does not change original")
	var scaled := Commands.execute(design,{"op":"mesh_scale","id":first,"value":Vector3(.006,.006,.006)})
	design.restore_author(scaled.after)
	check(design.mesh_options[Collision.mesh_asset(design,Xml.find(design.tree,first)).id].octree_maxdepth == 4,"mesh scale preserves precision metadata")
	edit(design,first,"mode","hull");edit(design,first,"maxhullvert",8)
	check(design.entity(first).attrs.type == "mesh" and Collision.mesh_asset(design,Xml.find(design.tree,first)).attrs.maxhullvert == "8","convex mode and vertex budget are standard MJCF")
	var before: Dictionary = design.author_snapshot()
	var invalid := Commands.execute(design,{"op":"collision","id":first,"field":"sdf_depth","value":2})
	check(not invalid.error.is_empty() and before == design.author_snapshot(),"invalid depth rejected without editing source")
	var budget := Collision.limits();budget.triangles_per_mesh=3
	var context := Collision.context(null,design);context.limits=budget
	check(not Collision.validate_stats([{ "mesh":"test","triangles":4,"cells":20,"depth":3,"query_valid":true}],budget).is_empty(),"triangle budget enforced separately from texture/model memory")
	check(not Collision.validate_stats([{ "mesh":"test","triangles":4,"cells":500001,"depth":8,"query_valid":false}],Collision.limits()).is_empty(),"per-mesh query limit enforced")
	await runtime_collision_checks()
	service.queue_free();await process_frame
	print("NODE_COLLISION_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures,"native_model_stats":observed_model_stats,"native_runtime_stats":observed_runtime_stats,"open_surface_error":observed_open_surface_error}))
	quit(0 if failures.is_empty() else 1)

func settled(world: Node) -> bool:
	var until := Time.get_ticks_msec()+30000
	await process_frame; await process_frame
	while Time.get_ticks_msec()<until:
		if world.info().get("compile_status") in ["ready","failed"] and not world.author_compiler.busy(): return world.info().compile_status=="ready"
		await process_frame
	return false

func runtime_collision_checks() -> void:
	var World := preload("res://addons/godot_mujoco/model/runtime_world.gd")
	var Model := preload("res://addons/godot_mujoco/model/model_instance.gd")
	var path := ProjectSettings.globalize_path("res://depth-shared.obj")
	var source := '<mujoco><asset><mesh name="tetra" file="%s" scale=".005 .005 .005"/></asset><worldbody><geom name="static_sdf" type="sdf" mesh="tetra"/><body name="falling" pos="0 0 .05"><freejoint name="free"/><geom name="dynamic_sdf" type="sdf" mesh="tetra" mass="1"/></body></worldbody></mujoco>' % path
	var design: Resource = Author.from_xml(source).design
	var static_id: String = design.entities()[0].id
	var dynamic_id: String = design.entities()[3].id
	edit(design,static_id,"sdf_depth",3);edit(design,dynamic_id,"sdf_depth",5)
	var world: Node = World.new();world.start_paused=true
	world.world_design=Author.from_xml('<mujoco><worldbody/></mujoco>').design
	var values := {"nativeccd":false,"multiccd":false,"ccd_iterations":18,"ccd_tolerance":.000003,"sdf_iterations":13,"sdf_initpoints":22}
	check(Collision.write_world(world.world_design.tree,values).is_empty(),"write all six world collision settings")
	var model: Node = Model.new();model.design=design;world.add_child(model);root.add_child(world)
	check(await settled(world),"static and dynamic SDF compile into one shared world")
	var stats: Array = PhysicsServer3D.call("scene_collision_stats",world.space)
	observed_runtime_stats = stats.duplicate(true)
	var depths := stats.map(func(item):return item.depth);depths.sort()
	check(depths==[3,5] and stats.all(func(item):return item.query_valid),"loaded runtime MJB retains distinct actual depths for the same file")
	var options: Dictionary = world.info().runtime_options
	check((int(options.disableflags) & ((1<<17)|(1<<19))) == ((1<<17)|(1<<19)),"shared world applies nativeccd and multiccd disable flags")
	check(options.ccd_iterations==18 and is_equal_approx(options.ccd_tolerance,.000003) and options.sdf_iterations==13 and options.sdf_initpoints==22,"shared world applies the four numerical settings")
	check(model.state().joints.has("free"),"dynamic SDF retains its free joint")
	var retained: Dictionary = model.state();var total := 0
	for item in stats: total+=int(item.cells)
	ProjectSettings.set_setting("mujoco/authoring/sdf_max_cells_per_world",total-1)
	PhysicsServer3D.call("scene_stage_author_model",world.space,model.model_rid,model.author_definition())
	check(not await settled(world) and world.info().last_error.contains("world budget"),"actual combined cell total enforces the configured world budget")
	check(model.state()==retained and world.info().paused and not world.set_paused(false),"budget failure retains the last valid physical world and refuses stale resume")
	ProjectSettings.set_setting("mujoco/authoring/sdf_max_cells_per_world",2000000)
	PhysicsServer3D.call("scene_stage_author_model",world.space,model.model_rid,model.author_definition())
	check(await settled(world),"correcting the budget recovers without discarding the author draft")
	# A non-collision option remains a strict composition conflict.
	var option := Xml.section(model.design.tree,"option",true);option.attrs.gravity="0 0 -4";model.design.touch()
	PhysicsServer3D.call("scene_stage_author_model",world.space,model.model_rid,model.author_definition())
	check(not await settled(world) and world.info().last_error.contains("gravity"),"world override is limited to the six selected collision fields")
	check(ResourceSaver.save(model.design,"res://failed-collision-draft.tres")==OK,"failed compilation remains saveable")
	world.queue_free();await process_frame;await process_frame
	# Quality checks use a relative size scale; an open surface is still rejected.
	var open: Resource = Author.from_xml(source).design
	var data := FileAccess.get_file_as_string("res://depth-shared.obj").replace("f 2 3 4\n", "")
	var file := FileAccess.open("res://open.obj",FileAccess.WRITE);file.store_string(data);file.close()
	for asset in Xml.section(open.tree,"asset").children: asset.attrs.file="res://open.obj"
	open.dependencies = {"res://open.obj":FileAccess.get_sha256("res://open.obj")}
	var output := await compile_design(open)
	observed_open_surface_error = output.get("error", "")
	check(not output.get("success",true) and observed_open_surface_error == "SDF tetra has no closed triangle surface", "open SDF triangles reach the intended geometry-quality rejection: " + observed_open_surface_error)
