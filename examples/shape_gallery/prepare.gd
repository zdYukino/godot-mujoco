extends SceneTree
const Package = preload("res://addons/godot_mujoco/model/package_builder.gd")
const Builder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
	if not doc.import_file("res://assets/gallery.xml"): printerr(doc.get_error()); quit(1); return
	var snapshot: Dictionary=doc.snapshot(); snapshot.source="res://assets/gallery.xml"
	if not doc.restore(snapshot): printerr(doc.get_error()); quit(1); return
	var packed: Dictionary=Package.pack(doc,"res://models","dynamic_shapes")
	if not packed.error.is_empty(): printerr(packed.error); quit(1); return
	var model: Resource=load(packed.path)
	var world:=Builder.create(model); world.name="ShapeGallery"
	world.set_meta("example","One shared MuJoCo space; 7 freejoint rigid bodies. Cone = compiled convex mesh, not native cone or SDF.")
	var camera:=Camera3D.new(); camera.name="Camera"; camera.position=Vector3(8,6,10); camera.look_at_from_position(camera.position,Vector3(.5,1,0)); world.add_child(camera); camera.owner=world
	var environment:=WorldEnvironment.new(); environment.name="PolyHavenSky"; environment.environment=Environment.new()
	var sky:=Sky.new(); var material:=PanoramaSkyMaterial.new(); material.panorama=load("res://assets/kloofendal_43d_clear_puresky_4k.hdr")
	sky.sky_material=material; environment.environment.sky=sky; environment.environment.background_mode=Environment.BG_SKY
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_SKY; environment.environment.ambient_light_energy=.65
	world.add_child(environment); environment.owner=world
	var sun:=DirectionalLight3D.new(); sun.name="Sun"; sun.rotation_degrees=Vector3(-50,-35,0); sun.light_energy=1.3; sun.shadow_enabled=true; world.add_child(sun); sun.owner=world
	var controls:=Node.new(); controls.name="DisplayControls"; controls.set_script(preload("gallery.gd")); world.add_child(controls); controls.owner=world
	var scene:=PackedScene.new()
	var error:=scene.pack(world)
	if error==OK: error=ResourceSaver.save(scene,"res://Main.tscn")
	world.free()
	print("SHAPE_GALLERY_BUILD ",JSON.stringify({"error":error,"model":packed.path,"floor":"original world-space grid on existing floor; 1 m spacing"}))
	quit(0 if error==OK else 1)
