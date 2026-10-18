extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/package_builder.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func write(path: String, value: String) -> void:
	var f := FileAccess.open(path,FileAccess.WRITE);f.store_string(value);f.close()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var doc: RefCounted = ClassDB.instantiate("MjEditorDocument")
	DirAccess.make_dir_recursive_absolute("res://edge_source")
	var vertices := "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n"
	write("res://edge_source/tetra.obj",vertices)
	write("res://edge_source/model.xml","<mujoco><asset><mesh name='tetra' file='tetra.obj'/></asset><worldbody><body name='b'><geom type='mesh' mesh='tetra'/></body></worldbody></mujoco>")
	if not doc.import_file("res://edge_source/model.xml"):printerr(doc.get_error());quit(1);return
	var packed: Dictionary=Builder.pack(doc,"res://edge_regression_packages","mesh")
	if not packed.error.is_empty():printerr(packed.error);quit(1);return
	var resource=ResourceLoader.load(packed.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var world=World.new();world.world_model=resource;world.start_paused=true
	var model=Instance.new();model.model=resource;world.add_child(model);root.add_child(world)
	check(model.model_rid.is_valid(),"valid mesh loads into live world")
	var before:Dictionary=model.state()
	var revision:int=world.info().revision
	var relative:String=resource.dependencies.keys()[0]
	var asset:String=packed.path.get_base_dir().path_join(relative)
	var cases := ["deleted_entry","unlisted_reference","extra_entry","absolute_path","traversal","backslash","empty_component","compiler_redirect","include"]
	for index in cases.size():
		var damaged=resource.duplicate(true)
		var label:String=cases[index]
		match label:
			"deleted_entry":damaged.dependencies.erase(relative)
			"unlisted_reference":damaged.snapshot.xml=damaged.snapshot.xml.replace(relative,"assets/unlisted.obj")
			"extra_entry":damaged.dependencies["assets/unreferenced.obj"]=resource.dependencies[relative]
			"absolute_path":damaged.snapshot.xml=damaged.snapshot.xml.replace(relative,"/tmp/unlisted.obj")
			"traversal":damaged.snapshot.xml=damaged.snapshot.xml.replace(relative,"assets/../unlisted.obj")
			"backslash":damaged.snapshot.xml=damaged.snapshot.xml.replace(relative,"assets/..\\unlisted.obj")
			"empty_component":damaged.snapshot.xml=damaged.snapshot.xml.replace(relative,"assets//unlisted.obj")
			"compiler_redirect":damaged.snapshot.xml=damaged.snapshot.xml.replace("<asset>","<compiler meshdir='../'/><asset>")
			"include":damaged.snapshot.xml=damaged.snapshot.xml.replace("<asset>","<include file='/tmp/model.xml'/><asset>")
		var path:String=packed.path.get_base_dir().path_join("bad_"+str(index)+".tres")
		check(ResourceSaver.save(damaged,path)==OK,"persist malformed package "+label)
		damaged=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(not damaged.open_document().error.is_empty(),"reject malformed package "+label)
		var rejected=Instance.new();rejected.model=damaged;world.add_child(rejected)
		check(not rejected.model_rid.is_valid() and not rejected.last_error.is_empty(),"runtime rejects "+label)
		check(model.state()==before and world.info().revision==revision,"live world unchanged "+label)
		rejected.free()
	write(asset,vertices.replace("v 1 0 0","v 2 0 0"))
	check(not resource.open_document().error.is_empty(),"changed valid mesh rejected by hash")
	resource.dependencies.erase(relative)
	check(ResourceSaver.save(resource,packed.path)==OK,"persist changed mesh and missing entry")
	var reread=ResourceLoader.load(packed.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(not reread.open_document().error.is_empty(),"deleted entry cannot bypass changed-mesh checksum")
	check(model.state()==before and world.info().revision==revision,"corrupt package does not mutate loaded model")
	world.free()
	var failed:=0
	for c in checks:if not c.passed:failed+=1
	print("RECOVERY_INTEGRITY_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}))
	quit(0 if failed==0 else 1)
