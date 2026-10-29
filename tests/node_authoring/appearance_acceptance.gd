extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Appearance = preload("res://addons/godot_mujoco/model/geom_appearance.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Visual = preload("res://addons/godot_mujoco/model/model_visual.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message); print("FAIL ", message)

func _initialize() -> void:
	call_deferred("run")

func edit(design: Resource, identity: String, field: String, value: Variant) -> void:
	var result := Commands.execute(design, {"op":"appearance", "id":identity, "field":field, "value":value})
	check(result.error.is_empty(), "appearance command: " + field + ": " + result.error)
	if result.error.is_empty(): check(design.restore_author(result.after).is_empty(), "appearance snapshot restores with unique IDs")

func run() -> void:
	var design: Resource = Author.from_xml('<mujoco><compiler angle="radian"/><default><default class="colored"><geom material="shared"/></default></default><asset><material name="shared" rgba=".8 .2 .1 .6" specular=".7"/><mesh name="tetra" vertex="0 0 0 1 0 0 0 1 0 0 0 1" texcoord=".1 .2 .9 .2 .1 .8 .9 .8" face="0 2 1 0 1 3 0 3 2 1 2 3"/></asset><worldbody><body name="body" childclass="colored"><geom name="painted" type="mesh" mesh="tetra"/><geom name="sibling" type="box" size=".2 .2 .2" pos="2 0 0"/></body></worldbody></mujoco>').design
	var geom: Dictionary = Xml.find(design.tree, design.entities()[1].id)
	var sibling_id: String = design.entities()[2].id
	var identity: String = geom.id
	check(Appearance.color(design, geom).is_equal_approx(Color(.8,.2,.1,.6)), "Inspector resolves inherited material color and alpha")
	edit(design, identity, "color", Color(.1,.4,.9))
	geom = Xml.find(design.tree, identity)
	check(Appearance.color(design, geom).is_equal_approx(Color(.1,.4,.9,.6)), "color edit preserves inherited alpha")
	check(Appearance.color(design, Xml.find(design.tree, sibling_id)).is_equal_approx(Color(.8,.2,.1,.6)), "shared-material sibling stays unchanged")
	check(Appearance.material(design, geom).attrs.specular == ".7", "material clone retains other MJCF properties")
	edit(design, identity, "opacity", 1.0)
	edit(design, identity, "color", Color(.5,.5,.5))
	var native: RefCounted = ClassDB.instantiate("MjEditorDocument")
	check(native.compile_author(design.worker_xml(), {}), "edited MJCF compiles")
	check(native.geometry()[0].color.is_equal_approx(Color(.5,.5,.5,1)), "exact default gray overrides previous material color")
	edit(design, identity, "opacity", .35)
	var before: Dictionary = design.author_snapshot()
	var rejected := Commands.execute(design, {"op":"appearance", "id":identity, "field":"opacity", "value":1.5})
	check(not rejected.error.is_empty() and design.author_snapshot() == before, "invalid alpha does not mutate author data")
	var image := Image.create(8,8,false,Image.FORMAT_RGBA8)
	image.fill(Color(.9,.1,.2,1))
	image.fill_rect(Rect2i(0,0,4,4), Color(.1,.8,.9,.5))
	var original := "user://appearance-source.png"
	check(image.save_png(original) == OK, "create external RGBA texture fixture")
	var digest := FileAccess.get_sha256(original)
	edit(design, identity, "texture_file", original)
	geom = Xml.find(design.tree, identity)
	var copied: String = Appearance.get_value(design, geom, "mjcf/texture_file")
	check(copied.begins_with("res://mujoco_models/") and FileAccess.get_sha256(copied) == digest, "texture copied into portable project assets")
	check(FileAccess.get_sha256(original) == digest and design.dependencies.get(copied) == digest, "original texture stays unchanged and dependency is tracked")
	DirAccess.remove_absolute(original)
	check(ResourceSaver.save(design, "res://appearance-roundtrip.tres") == OK, "save MJCF appearance resource")
	design = ResourceLoader.load("res://appearance-roundtrip.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	geom = Xml.find(design.tree, identity)
	check(Appearance.get_value(design, geom, "mjcf/texture_file") == copied and is_equal_approx(Appearance.color(design,geom).a,.35), "reopen retains texture and opacity")
	check(native.compile_author(design.worker_xml(), {}), "MJCF compiles after original texture is removed")
	var geometry: Array = native.geometry()
	check(geometry[0].has("texture_image") and geometry[0].texture_image.channels == 4, "native model exports decoded RGBA texture pixels")
	check(geometry[0].uvs.size() == geometry[0].vertices.size(), "native mesh preserves per-face texture coordinates")
	check(geometry[0].uvs[0].is_equal_approx(Vector2(.1,.8)), "mesh UV orientation converts from MuJoCo to Godot")
	check(geometry[1].color.is_equal_approx(Color(.8,.2,.1,.6)) and not geometry[1].has("texture_image"), "compiled sibling still uses original appearance")
	var service := Service.new(); root.add_child(service)
	var output := {}
	service.completed.connect(func(result): output.merge(result))
	service.submit({"author":design.author_snapshot(), "generation":design.document_id})
	var deadline := Time.get_ticks_msec() + 30000
	while output.is_empty() and Time.get_ticks_msec() < deadline: await process_frame
	check(output.get("success",false), "background worker caches textured mesh: " + str(output.get("error", "timeout")))
	if output.get("success", false):
		var cached: Dictionary = output.geometry[0]
		check(cached.has("texture_path") and not cached.has("texture_image"), "worker publishes portable texture resource without duplicating pixels in scene")
		var visual: MeshInstance3D = Visual.create(cached)
		var material := visual.material_override as StandardMaterial3D
		check(material.albedo_color.is_equal_approx(Color(.5,.5,.5,.35)) and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "Godot material displays authored color and transparency")
		check(material.albedo_texture != null and material.albedo_texture.get_width() == 8, "cached texture loads without editor image import")
		check(visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV].size() > 0, "cached mesh retains UVs")
		visual.free()
		# Exercise the saved author-data path used by standalone game startup.
		design.cached_entities = output.entities; design.cached_geometry = output.geometry
		design.compiled_snapshot = output.snapshot; design.validated_revision = design.revision; design.validated_context = output.context
		var world := World.new(); world.name = "AppearanceWorld"; world.world_design = design.fork(); world.start_paused = true
		var model := Model.new(); model.name = "AppearanceModel"; model.design = design
		world.add_child(model); root.add_child(world)
		deadline = Time.get_ticks_msec() + 30000
		while Time.get_ticks_msec() < deadline and world.info().get("compile_status") not in ["ready", "failed"]: await process_frame
		check(world.info().get("compile_status") == "ready", "textured author document assembles at runtime")
		for frame in 8: await process_frame
		var runtime_visual: MeshInstance3D = model.get_node("body/painted/_Visual")
		var runtime_material := runtime_visual.material_override as StandardMaterial3D
		check(runtime_material.albedo_texture != null and is_equal_approx(runtime_material.albedo_color.a,.35), "runtime hierarchy retains texture and alpha")
		world.queue_free(); await process_frame; await process_frame
	# Clearing only removes this geom's albedo texture and keeps color/alpha.
	edit(design, identity, "texture_file", "")
	geom = Xml.find(design.tree, identity)
	check(Appearance.get_value(design,geom,"mjcf/texture_file") == "" and is_equal_approx(Appearance.color(design,geom).a,.35), "clear texture preserves opacity")
	check(native.compile_author(design.worker_xml(), {}) and not native.geometry()[0].has("texture_image"), "cleared texture is removed from compiled MJCF material")
	service.queue_free(); await process_frame
	print("NODE_APPEARANCE_RESULT ", JSON.stringify({"checks":checks, "failed":failures.size(), "failures":failures}))
	quit(0 if failures.is_empty() else 1)
