extends SceneTree
const Package=preload("res://addons/godot_mujoco/model/package_builder.gd")
const Builder=preload("res://addons/godot_mujoco/model/scene_builder.gd")
const Instance=preload("res://addons/godot_mujoco/model/model_instance.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	var source:="res://assets/robots/unitree_g1/g1_29dof_mode_18/g1_29dof_mode_18.urdf"
	if not doc.import_g1(source,true,true): printerr(doc.get_error()); quit(1); return
	var snapshot: Dictionary=doc.snapshot(); snapshot.source=source
	# Preserve the first gallery's authored world gravity; no controller added.
	var regex:=RegEx.new(); regex.compile('gravity="[^"]*"')
	snapshot.xml=regex.sub(snapshot.xml,'gravity="0 0 -9.81"',true)
	if not doc.restore(snapshot): printerr(doc.get_error()); quit(1); return
	var collision_names: Dictionary={}
	for entity in doc.inspect().entities:
		if entity.kind=="geom" and (entity.properties.contype!=0 or entity.properties.conaffinity!=0): collision_names[entity.name]=true
	var definitions:=Resource.new()
	var geometries: Array=[]
	for geom in doc.collision_preview(.33,65):
		if not collision_names.has(geom.name): continue
		var preview=preload("res://addons/godot_mujoco/map/collision_preview.gd").create([geom],Transform3D.IDENTITY)
		if preview.get_child_count()!=1: printerr("Missing native collision boundary ",geom.name); preview.free(); quit(1); return
		var wire: MeshInstance3D=preview.get_child(0)
		geometries.append({"name":geom.name,"kind":geom.preview_kind,"mesh":wire.mesh,"material":wire.material_override})
		preview.free()
	definitions.set_meta("geometries",geometries)
	if ResourceSaver.save(definitions,"res://g1_collision_previews.res",ResourceSaver.FLAG_COMPRESS)!=OK: quit(1); return
	definitions=load("res://g1_collision_previews.res")
	var packed: Dictionary=Package.pack(doc,"res://models","passive_g1")
	if not packed.error.is_empty(): printerr(packed.error); quit(1); return
	var robot_model: Resource=load(packed.path)
	# Keep saved provenance portable; mesh bytes remain the upstream originals.
	var project_prefix:=ProjectSettings.globalize_path("res://")
	for field in ["assets","sources"]:
		var portable: Dictionary={}
		for path in robot_model.provenance.get(field,{}): portable[str(path).replace(project_prefix,"res://")]=robot_model.provenance[field][path]
		robot_model.provenance[field]=portable
	if ResourceSaver.save(robot_model,packed.path)!=OK: quit(1); return
	var floor_doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	var xml:="<mujoco><compiler angle='radian'/><option timestep='0.002' gravity='0 0 -9.81' integrator='implicitfast' solver='Newton'><flag nativeccd='enable'/></option><worldbody><geom name='floor_geom' type='box' size='6 4 .1' pos='0 0 -.1' rgba='.25 .28 .32 1' friction='.9 .005 .0001'/></worldbody></mujoco>"
	if not floor_doc.restore({"format":1,"source":"","xml":xml,"state":{}}): printerr(floor_doc.get_error()); quit(1); return
	var floor_package: Dictionary=Package.pack(floor_doc,"res://models","gallery_floor")
	if not floor_package.error.is_empty(): printerr(floor_package.error); quit(1); return
	var world:=Builder.create(load(floor_package.path)); world.name="PassiveG1Gallery"
	var robot:=Instance.new(); robot.name="G1_1"; robot.model=robot_model; robot.position=Vector3(-1.8,.82,0); robot.rotation_degrees.z=5; world.add_child(robot); robot.owner=world
	# Preserve sky/light; this second example uses a closer camera only.
	var original: Node=load("res://Main.tscn").instantiate()
	for name in ["PolyHavenSky","Sun"]:
		var node: Node=original.get_node(name).duplicate(); world.add_child(node); node.owner=world
	original.free()
	var camera=preload("res://g1_camera.gd").new(); camera.name="Camera"; camera.fov=50; camera.near=.05; camera.frame_for_count(1); world.add_child(camera); camera.owner=world
	var controls:=Node.new(); controls.name="DisplayControls"; controls.set_script(preload("res://g1_controls.gd")); controls.robot_model=robot_model; controls.collision_definitions=definitions; world.add_child(controls); controls.owner=world
	var scene:=PackedScene.new(); var error:=scene.pack(world)
	if error==OK: error=ResourceSaver.save(scene,"res://G1.tscn")
	world.free(); print("PASSIVE_G1_BUILD ",JSON.stringify({"error":error,"robot_model":packed.path}))
	quit(0 if error==OK else 1)
