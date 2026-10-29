extends SceneTree
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Instance = preload("res://addons/godot_mujoco/model/model_instance.gd")
var checks := []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: printerr("FAIL ",label)
func write(path: String, value: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(value);file.close()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://edge_source")
	var vertices := "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n"
	write("res://edge_source/tetra.obj",vertices)
	write("res://edge_source/model.xml","<mujoco><asset><mesh name='tetra' file='tetra.obj'/></asset><worldbody><body name='b'><geom type='mesh' mesh='tetra'/></body></worldbody></mujoco>")
	var imported := await Builder.import_file("res://edge_source/model.xml","res://integrity","mesh")
	check(imported.error.is_empty(),"import portable author design")
	var design: Resource=load(imported.path)
	var world:=World.new();world.world_design=design.fork();world.start_paused=true
	var model:=Instance.new();model.design=design;world.add_child(model);root.add_child(world)
	var until:=Time.get_ticks_msec()+30000
	while not world.author_started and Time.get_ticks_msec()<until:await process_frame
	check(world.author_started,"initial mesh design compiles")
	var before:Dictionary=model.state();var revision:int=world.info().revision
	var asset:String=design.dependencies.keys()[0]
	for label in ["deleted_entry","unlisted_reference","extra_entry","absolute_path","traversal","compiler_redirect","include","format"]:
		var damaged:Resource=design.fork()
		match label:
			"deleted_entry":damaged.dependencies.erase(asset)
			"unlisted_reference":Xml.walk(Xml.section(damaged.tree,"asset")).filter(func(e):return e.tag=="mesh")[0].attrs.file="res://unlisted.obj"
			"extra_entry":damaged.dependencies["res://unreferenced.obj"]="hash"
			"absolute_path":Xml.walk(Xml.section(damaged.tree,"asset")).filter(func(e):return e.tag=="mesh")[0].attrs.file="/tmp/unlisted.obj"
			"traversal":Xml.walk(Xml.section(damaged.tree,"asset")).filter(func(e):return e.tag=="mesh")[0].attrs.file="res://../unlisted.obj"
			"compiler_redirect":Xml.section(damaged.tree,"compiler",true).attrs.meshdir="../"
			"include":damaged.tree.children.append({"id":Xml.uuid(),"tag":"include","attrs":{"file":"/tmp/unlisted.xml"},"children":[]})
			"format":damaged.format_version=99
		var path: String="res://integrity/bad_"+str(label)+".tres"
		check(ResourceSaver.save(damaged,path)==OK,"save invalid draft "+label)
		damaged=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(not damaged.validate_dependencies().is_empty(),"diagnose dependency contract "+label)
		var rejected:=Instance.new();rejected.design=damaged;world.add_child(rejected)
		check(not rejected.model_rid.is_valid() and not rejected.last_error.is_empty(),"runtime refuses invalid source "+label)
		check(model.state()==before and world.info().revision==revision,"invalid registration preserves active world "+label)
		rejected.free()
	write(asset,vertices.replace("v 1 0 0","v 2 0 0"))
	check(design.validate_dependencies().contains("hash mismatch"),"modified valid mesh fails hash verification")
	check(model.state()==before,"corrupt external bytes cannot mutate a loaded model")
	world.queue_free();await process_frame;await process_frame
	var failed:=checks.filter(func(item):return not item.passed).size()
	print("RECOVERY_INTEGRITY_RESULT ",JSON.stringify({"checks":checks,"passed":checks.size()-failed,"failed":failed}));quit(0 if failed==0 else 1)
