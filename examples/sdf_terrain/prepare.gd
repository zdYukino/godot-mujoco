extends SceneTree
const Session=preload("res://addons/godot_mujoco/map/session.gd")
const Package=preload("res://addons/godot_mujoco/map/package.gd")
const Native=preload("res://addons/godot_mujoco/map/native_collision.gd")
const Preview=preload("res://addons/godot_mujoco/map/collision_preview.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var session:=Session.new()
	if not session.import_file("res://assets/terrain.obj","m","Y_UP"): push_error(session.error); quit(1); return
	session.view.camera={"center":Vector3(0,.1,0),"distance":10.0,"yaw":.45,"pitch":.55}
	var manifest: Array=[]
	for mesh in session.meshes():
		var path:=str(session.visual.get_path_to(mesh))
		if not session.configure(path,{"kind":"sdf","octree_maxdepth":6,"friction":.8}): push_error(session.error); session.close(); quit(1); return
		var built:=Native.build(mesh,session.visual,session.specs[path],session.world_settings)
		if not built.error.is_empty(): push_error(built.error); session.close(); quit(1); return
		manifest.append({"node":path,"actual_mode":built.contract.actual_mode,"inspect":built.document.inspect(),"geometry_types":built.geometry.map(func(g): return g.type)})
	var packaged:=Package.pack(session,"res://models")
	if not packaged.error.is_empty(): push_error(packaged.error); session.close(); quit(1); return
	var f:=FileAccess.open("res://map_package_path.txt",FileAccess.WRITE); f.store_string(packaged.path); f.close()
	var built:=session.build_scene()
	if not built.error.is_empty(): push_error(built.error); session.close(); quit(1); return
	var scene: Node3D=built.scene
	scene.name="SdfTerrain"
	var overlays:=Node3D.new(); overlays.name="CollisionPreview"; overlays.visible=false; scene.add_child(overlays)
	for mesh in session.meshes():
		var path:=str(session.visual.get_path_to(mesh))
		var collision:=Native.build(mesh,session.visual,session.specs[path],session.world_settings)
		overlays.add_child(Preview.create(collision.document.collision_preview(.43,33),collision.pose))
	var shader:=load("res://floor_grid.gdshader")
	for mesh in scene.find_children("*","MeshInstance3D",true,false):
		if not scene.get_node("Visual").is_ancestor_of(mesh): continue
		var material:=ShaderMaterial.new(); material.shader=shader
		material.set_shader_parameter("base_color",Color(.22,.26,.29,1))
		material.set_shader_parameter("grid_spacing",.25)
		material.set_shader_parameter("line_width",.012)
		mesh.material_override=material
	var environment:=WorldEnvironment.new(); environment.name="PolyHavenSky"
	var panorama:=PanoramaSkyMaterial.new(); panorama.panorama=load("res://assets/kloofendal_43d_clear_puresky_4k.hdr")
	var sky:=Sky.new(); sky.sky_material=panorama
	var env:=Environment.new(); env.background_mode=Environment.BG_SKY; env.sky=sky; env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY; env.ambient_light_energy=.65
	environment.environment=env; scene.add_child(environment)
	var controls:=CanvasLayer.new(); controls.name="DisplayControls"; controls.set_script(load("res://terrain_controls.gd")); scene.add_child(controls)
	for item in [{"name":"StairsBall","p":Vector3(-4.25,1.5,0)},{"name":"PitBall","p":Vector3(0,1.5,0)},{"name":"RoughBall","p":Vector3(3,1.5,0)}]:
		var ball:=RigidBody3D.new(); ball.name=item.name; ball.position=item.p; ball.mass=.2
		var shape:=CollisionShape3D.new(); var sphere:=SphereShape3D.new(); sphere.radius=.12; shape.shape=sphere; ball.add_child(shape)
		var visual:=MeshInstance3D.new(); var sphere_mesh:=SphereMesh.new(); sphere_mesh.radius=.12; sphere_mesh.height=.24; visual.mesh=sphere_mesh
		var material:=StandardMaterial3D.new(); material.albedo_color=Color(.95,.65,.12); visual.material_override=material; ball.add_child(visual); scene.add_child(ball)
	for child in scene.get_children(): session.own_scene(child,scene)
	var packed:=PackedScene.new()
	if packed.pack(scene)!=OK or ResourceSaver.save(packed,"res://Main.tscn")!=OK: push_error("Failed to save terrain example"); scene.free(); session.close(); quit(1); return
	var report:=FileAccess.open("res://assets/sdf_manifest.json",FileAccess.WRITE); report.store_string(JSON.stringify({"chunks":manifest,"package":packaged.path,"default_collision":"sdf","octree_maxdepth":6},"\t")); report.close()
	print("SDF_TERRAIN_PREPARED ",JSON.stringify({"chunks":manifest.size(),"package":packaged.path}))
	scene.free(); session.close(); quit(0)
