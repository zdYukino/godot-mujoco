@tool
extends RefCounted
var passed:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func run(plugin) -> void:
	var panel=plugin.map_panel
	for i in 15: await panel.get_tree().process_frame
	panel.path_field.text="res://assets/terrain.obj";panel.unit.select(1);panel.axes.select(0)
	check(panel.import_source(false),"terrain import through existing right-side map panel")
	for mesh in panel.session.meshes():
		var path:=str(panel.session.visual.get_path_to(mesh));panel.items[path].select(0);panel.select_tree()
		for i in panel.strategy.item_count:
			if panel.strategy.get_item_text(i)=="sdf": panel.strategy.select(i)
		panel.sdf_depth.value=6
		check(panel.configure(),"SDF and depth6 applied to "+path)
	var selected: String=panel.selected
	var original: Dictionary=panel.session.specs.duplicate(true)
	for i in panel.strategy.item_count:
		if panel.strategy.get_item_text(i)=="mesh":panel.strategy.select(i)
	check(panel.configure() and panel.session.specs[selected].kind=="mesh","explicit editor mode change to convex control")
	panel.session.history.undo();panel.rebuild()
	check(panel.session.specs==original,"Undo restores SDF mode and depth")
	panel.session.history.redo();panel.rebuild()
	check(panel.session.specs[selected].kind=="mesh","Redo restores explicit convex mode")
	for i in panel.strategy.item_count:
		if panel.strategy.get_item_text(i)=="sdf":panel.strategy.select(i)
	panel.sdf_depth.value=6;check(panel.configure(),"restore SDF default before saving example")
	var retained: Dictionary=panel.session.specs.duplicate(true)
	panel.sdf_depth.value=2
	check(not panel.configure() and panel.session.specs==retained,"invalid SDF depth rejects atomically")
	panel.sdf_depth.value=6;check(panel.configure(),"valid SDF depth recovers after rejection")
	var mesh: MeshInstance3D=panel.session.meshes()[1]
	var resolutions: Array=[]
	for depth in [3,4,6]:
		var built: Dictionary=panel.session.Native.build(mesh,panel.session.visual,{"kind":"sdf","octree_maxdepth":depth})
		check(built.error.is_empty(),"independent bounded SDF compilation depth%d" % depth)
		if built.error.is_empty():
			var snapshot: Dictionary=built.document.snapshot()
			check(snapshot.format==2 and snapshot.mesh_options.collision_mesh.octree_maxdepth==depth,"versioned snapshot preserves native-only octree option")
			var restored:=MjEditorDocument.new()
			check(restored.restore(snapshot) and restored.inspect().octree_cells==built.document.inspect().octree_cells,"snapshot restores same actual octree asset")
			resolutions.append({"depth":depth,"cells":built.document.inspect().octree_cells,"buffer_bytes":built.document.inspect().model_buffer_bytes})
	var package: Dictionary=preload("res://addons/godot_mujoco/map/package.gd").pack(panel.session,"res://editor_packages")
	check(package.error.is_empty(),"save independent SDF terrain map package")
	if package.error.is_empty():
		check(panel.open_package(package.path),"reopen map package in right-side editor")
		check(panel.session.specs.values().all(func(s):return s.kind=="sdf" and s.octree_maxdepth==6),"all saved collision modes and depths retained")
	var host:=Node3D.new();host.name="TerrainHost";var packed:=PackedScene.new()
	packed.pack(host);ResourceSaver.save(packed,"res://TerrainHost.tscn");host.free()
	EditorInterface.open_scene_from_path("res://TerrainHost.tscn")
	for i in 15: await panel.get_tree().process_frame
	check(panel.apply_scene(),"real editor Apply authors SDF terrain in host")
	var edited:=EditorInterface.get_edited_scene_root()
	check(edited.has_node("StaticMap") and edited.get_node("StaticMap").native_collisions.size()==3,"Apply preserves all three physical chunks")
	var applied=edited.get_node("StaticMap")
	check(applied.native_collisions.all(func(e):return e.snapshot.get("mesh_options",{}).size()>0),"Apply retains octree options instead of XML fallback")
	check(panel.apply_scene() and edited.get_child_count()==1,"repeated Apply replaces target without duplicate terrain")
	var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(edited))
	history.undo();check(edited.get_child_count()==1,"scene Undo preserves one authored map")
	history.redo();check(edited.get_child_count()==1,"scene Redo preserves one authored map")
	var saved:=PackedScene.new()
	check(saved.pack(edited)==OK and ResourceSaver.save(saved,"res://TerrainHost.tscn")==OK,"save applied editable scene headless without fake thumbnail")
	print("SDF_EDITOR_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"resolutions":resolutions,"gui":"headless editor logic only"}))
	panel.session.dirty=false;plugin.state.dirty=false
	panel.get_tree().quit(0 if failed==0 else 1)
