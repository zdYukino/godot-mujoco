extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Commands = preload("res://addons/godot_mujoco/model/author_commands.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Scene = preload("res://addons/godot_mujoco/model/author_scene.gd")
const Visual = preload("res://addons/godot_mujoco/model/model_visual.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Builder = preload("res://addons/godot_mujoco/model/scene_builder.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func fixture(xml := '<mujoco><compiler angle="radian"/><worldbody><frame pos=".4 .2 .3" euler=".1 .2 -.3"><body name="parent" pos=".1 -.1 .6"><freejoint name="base"/><geom name="box" type="box" size=".1 .2 .3" rgba=".2 .4 .6 1" pos=".2 .1 .05"/><geom name="ellipsoid" type="ellipsoid" size=".2 .3 .4" pos="-.2 0 .1"/><body name="child" pos=".3 -.2 .4" euler=".2 .3 .1"><joint name="hinge"/><geom name="ball" size=".08"/></body></body></frame><body name="target" pos="1 0 0"><geom name="anchor" size=".05"/></body></worldbody></mujoco>') -> Node:
	var model := Model.new(); model.name = "VisualModel"
	model.design = Author.from_xml(xml).design
	model.author_scene = Scene.new(); model.author_scene.initialize(model)
	return model

func named(model: Node, name: String) -> Dictionary:
	for item in model.design.entities():
		if item.name == name: return item
	return {}

func native_result(model: Node) -> Dictionary:
	var document: RefCounted = ClassDB.instantiate("MjEditorDocument")
	var ok: bool = document.compile_author(model.design.worker_xml(model.compilation_context().collision_options), model.design.native_initial_pose(), model.design.native_mesh_options(), model.design.native_initial_controls())
	check(ok, "fixture native validation: " + document.get_error())
	if not ok: return {}
	return {"success":true, "author":model.design.author_snapshot(), "context":model.compilation_signature(), "entities":document.inspect().entities, "geometry":document.geometry(), "snapshot":document.snapshot(), "collision_geometry":[], "collision_stats":[]}

func drain(model: Node) -> bool:
	for step in 1000:
		if model.author_scene.geometry_queue.is_empty(): return true
		if model.author_scene.geometry_queue[0].get("_waiting", false) or not model.design.validation_error.is_empty(): return false
		model.author_scene.build_geometry_step()
	return false

func accept(model: Node, result: Dictionary) -> void:
	model.author_scene.due_ms = 0
	model.author_scene.apply_compiled(result)
	check(drain(model), "current accepted presentation drains: " + model.last_error)

func command(model: Node, value: Dictionary) -> void:
	var result := Commands.execute(model.design, value)
	check(result.get("error", "").is_empty() and not result.get("confirmation_required", false), "author command accepted: " + str(value.op))
	if result.has("after"): model.restore_author_snapshot(result.after)

func view(model: Node, identity: String) -> MeshInstance3D:
	return model.author_scene.nodes[identity].get_node("_Visual") as MeshInstance3D

func ids(model: Node) -> Dictionary:
	var result := {}
	for item in model.design.entities():
		if item.kind != "geom": continue
		var visual := view(model, item.id)
		result[item.id] = [model.author_scene.nodes[item.id].get_instance_id(), visual.get_instance_id(), visual.mesh.get_instance_id(), visual.material_override.get_instance_id()]
	return result

func world_pose(node: Node3D) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var current: Node = node
	while current is Node3D:
		pose = current.transform * pose; current = current.get_parent()
	return pose

func assert_geometry(model: Node, result: Dictionary, label: String) -> void:
	var snapshot: Dictionary = model.design.entity_snapshot()
	for geometry in result.geometry:
		var visual := view(model, snapshot.geom_by_name[geometry.name].id)
		var expected: Transform3D = model.transform * geometry.transform
		expected.basis *= Basis.from_scale(Visual.shape_scale(geometry))
		check(world_pose(visual).is_equal_approx(expected), label + ": " + geometry.name)

func dispose(model: Node) -> void:
	model.author_scene.shutdown(); model.free()

func identity_pose() -> void:
	var model := fixture()
	model.transform = Transform3D(Basis.from_euler(Vector3(.2,-.3,.1)), Vector3(2,3,-1))
	var base := named(model, "base")
	model.design.initial_pose[base.id] = [.6,.2,1.1,cos(.2),0.,0.,sin(.2)]
	var result := native_result(model); accept(model, result)
	var before := ids(model)
	var box := view(model, named(model,"box").id)
	box.visible = false; box.layers = 5; box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	for repeat in 4: accept(model, result)
	check(ids(model) == before, "no-op results preserve authored, visual, Mesh and owned material identities")
	check(not box.visible and box.layers == 5 and box.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED and box.owner == model, "reuse preserves visibility, user instance settings and scene ownership")
	assert_geometry(model, result, "nested initial-pose/frame/ellipsoid visual matches native geometry without scale accumulation")
	command(model, {"op":"set", "id":named(model,"hinge").id, "values":{"damping":.7}})
	result = native_result(model); accept(model,result)
	check(ids(model) == before, "damping-only validated result does not replace visual resources")
	var parent := named(model,"parent")
	var pose: Transform3D = parent.transform; pose.origin += Vector3(.3,.2,-.1)
	command(model,{"op":"pose","id":parent.id,"transform":pose})
	result = native_result(model); accept(model,result)
	check(ids(model) == before, "body pose update retains visual, Mesh and material identities")
	assert_geometry(model,result,"moved free-body visible geometry matches native result")
	check(model.author_scene.compiled_status == "有效", "completed presentation has ready status")
	dispose(model)

func appearance() -> void:
	var model := fixture(); accept(model,native_result(model))
	var identity: String = named(model,"box").id
	var box := view(model,identity)
	var visual_id := box.get_instance_id(); var mesh_id := box.mesh.get_instance_id(); var material_id := box.material_override.get_instance_id()
	command(model,{"op":"appearance","id":identity,"field":"color","value":Color(.7,.2,.3)})
	accept(model,native_result(model))
	check(box.get_instance_id()==visual_id and box.mesh.get_instance_id()==mesh_id and box.material_override.get_instance_id()==material_id and box.material_override.albedo_color.is_equal_approx(Color(.7,.2,.3)), "RGB updates the compatible owned material on the existing visual")
	for alpha in [.35,1.0]:
		command(model,{"op":"appearance","id":identity,"field":"opacity","value":alpha}); accept(model,native_result(model))
		check(is_equal_approx(box.material_override.albedo_color.a,alpha) and box.material_override.transparency==(BaseMaterial3D.TRANSPARENCY_ALPHA if alpha<1 else BaseMaterial3D.TRANSPARENCY_DISABLED), "opacity transition resets transparency in both directions: " + str(alpha))
	var image := Image.create(4,4,false,Image.FORMAT_RGBA8); image.fill(Color(.4,.6,.8,.5)); image.save_png("res://visual-texture.png")
	command(model,{"op":"appearance","id":identity,"field":"texture_file","value":"res://visual-texture.png"}); accept(model,native_result(model))
	check(box.material_override.albedo_texture != null and box.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA, "RGBA texture enables alpha even with opaque color")
	var texture_id: int = box.material_override.albedo_texture.get_instance_id()
	var textured_mesh: int = box.mesh.get_instance_id()
	var source := Xml.find(model.design.tree,identity)
	var material: Dictionary = preload("res://addons/godot_mujoco/model/geom_appearance.gd").material(model.design,source)
	material.attrs.texrepeat = "3 2"; accept(model,native_result(model))
	check(box.material_override.uv1_scale==Vector3(3,2,1) and box.material_override.albedo_texture.get_instance_id()==texture_id and box.mesh.get_instance_id()==textured_mesh, "repeat-only update retains Mesh/Texture resources")
	material.attrs.erase("texrepeat"); accept(model,native_result(model))
	check(box.material_override.uv1_scale==Vector3.ONE, "texture repeat returns to its default")
	command(model,{"op":"appearance","id":identity,"field":"texture_file","value":""}); accept(model,native_result(model))
	check(box.get_instance_id()==visual_id and box.material_override.albedo_texture==null and box.material_override.uv1_scale==Vector3.ONE and box.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED, "texture clear resets texture/repeat/alpha on the existing visual")
	command(model,{"op":"appearance","id":named(model,"ellipsoid").id,"field":"color","value":Color(.7,.2,.3)}); accept(model,native_result(model))
	var shared := StandardMaterial3D.new(); shared.albedo_color = box.material_override.albedo_color; shared.roughness = .85; shared.vertex_color_use_as_albedo = true
	var sibling := view(model,named(model,"ellipsoid").id)
	box.material_override = shared; sibling.material_override = shared
	accept(model,native_result(model))
	check(box.material_override==shared and sibling.material_override==shared, "unchanged result does not clone an external shared material to claim ownership")
	var shared_color := shared.albedo_color
	command(model,{"op":"appearance","id":identity,"field":"color","value":Color(.1,.8,.2)}); accept(model,native_result(model))
	check(box.material_override!=shared and shared.albedo_color==shared_color and sibling.material_override==shared and box.material_override.vertex_color_use_as_albedo, "necessary edit privately clones shared external material and preserves unrelated fields")
	var alias := MeshInstance3D.new(); alias.mesh=box.mesh; alias.material_override=box.material_override
	var previous_color: Color = alias.material_override.albedo_color
	command(model,{"op":"appearance","id":identity,"field":"color","value":Color(.8,.3,.9)}); accept(model,native_result(model))
	check(box.material_override!=alias.material_override and alias.material_override.albedo_color==previous_color, "late alias of an already-owned material cannot mutate another visual")
	box.material_override.albedo_color = Color.BLACK
	alias.material_override = box.material_override
	accept(model,native_result(model))
	check(box.material_override.albedo_color.is_equal_approx(Color(.8,.3,.9)) and alias.material_override.albedo_color==Color.BLACK and box.material_override!=alias.material_override, "unchanged descriptor corrects externally mutated source-owned material fields privately")
	alias.mesh = box.mesh
	var mutated_size: Vector3 = box.mesh.size * 2
	box.mesh.size = mutated_size
	accept(model,native_result(model))
	check(box.mesh != alias.mesh and box.mesh.size.is_equal_approx(Vector3(.2,.6,.4)) and alias.mesh.size==mutated_size, "unchanged descriptor privately corrects a mutated shared primitive Mesh")
	var matching := BoxMesh.new(); matching.size = box.mesh.size; box.mesh = matching
	accept(model,native_result(model))
	check(box.mesh==matching, "matching external Mesh replacement remains unchanged")
	box.mesh = SphereMesh.new()
	accept(model,native_result(model))
	check(box.mesh is BoxMesh and box.mesh.size.is_equal_approx(Vector3(.2,.6,.4)), "mismatching external Mesh replacement is corrected on the existing visual")
	alias.free(); dispose(model)

func raw_shapes() -> void:
	var ellipsoid := {"name":"independent_ellipsoid", "type":4, "size":Vector3(9,8,7), "source_size":Vector3(.2,.3,.4), "transform":Transform3D(Basis.from_euler(Vector3(.1,.3,.2)), Vector3(1,2,3))}
	var ellipsoid_view := Visual.create(ellipsoid)
	check(ellipsoid_view.scale.is_equal_approx(Vector3(.2,.4,.3)), "ellipsoid factory independently uses source_size with MJCF coordinate order")
	var ellipsoid_pose: Transform3D = ellipsoid.transform
	ellipsoid_pose.basis *= Basis.from_scale(Vector3(.2,.4,.3))
	for repeat in 3: Visual.apply_update(ellipsoid_view,Visual.prepare_update(ellipsoid_view,ellipsoid),ellipsoid_pose)
	check(ellipsoid_view.scale.is_equal_approx(Vector3(.2,.4,.3)), "reused ellipsoid scale does not accumulate or fall back to compiled size")
	ellipsoid_view.free()
	var geom := {"name":"raw", "type":7, "size":Vector3(2,3,4), "transform":Transform3D.IDENTITY, "color":Color(.2,.4,.6,1), "vertices":PackedVector3Array([Vector3.ZERO,Vector3(.4,0,0),Vector3(0,0,.8)]), "normals":PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])}
	var visual := Visual.create(geom)
	check(visual != null, "standalone raw factory remains compatible")
	var visual_id := visual.get_instance_id(); var material_id := visual.material_override.get_instance_id()
	var old_mesh := visual.mesh
	geom.vertices[1] = Vector3(1.2,0,0)
	var prepared := Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.get_instance_id()==visual_id and visual.mesh!=old_mesh and old_mesh.get_aabb().size.x < visual.mesh.get_aabb().size.x and visual.material_override.get_instance_id()==material_id, "raw shape edits replace only Mesh and do not mutate shared old data")
	geom.uvs = PackedVector2Array([Vector2.ZERO,Vector2(1,0),Vector2(0,1)])
	var before_uv := visual.mesh.get_instance_id()
	prepared = Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh.get_instance_id()!=before_uv and visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]==geom.uvs, "explicit UV change updates Mesh data on the same visual")
	geom.texture_image = {"width":2,"height":2,"channels":3,"pixels":PackedByteArray([255,0,0,0,255,0,0,0,255,255,255,255])}
	before_uv = visual.mesh.get_instance_id()
	prepared = Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh.get_instance_id()==before_uv and visual.material_override.albedo_texture!=null, "adding texture retains explicit-UV Mesh")
	geom.erase("uvs")
	prepared = Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	var projected: PackedVector2Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	geom.texture_uniform = true
	prepared = Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != projected and visual.get_instance_id()==visual_id, "projection changes update actual UVs while retaining visual identity")
	geom.texture_path = "res://missing-visual-texture.res"
	var mesh_id := visual.mesh.get_instance_id(); material_id = visual.material_override.get_instance_id()
	prepared = Visual.prepare_update(visual,geom)
	check(not prepared.error.is_empty() and visual.mesh.get_instance_id()==mesh_id and visual.material_override.get_instance_id()==material_id, "texture preparation failure cannot partially replace old Mesh/material")
	ResourceSaver.save(BoxMesh.new(),"res://wrong-visual-texture.res")
	geom.texture_path = "res://wrong-visual-texture.res"
	prepared = Visual.prepare_update(visual,geom)
	check(not prepared.error.is_empty() and visual.mesh.get_instance_id()==mesh_id, "well-formed wrong resource type is rejected before changing the visual")
	visual.free()

func scaled_mesh_options() -> void:
	FileAccess.open("res://visual-tetra.obj",FileAccess.WRITE).store_string("v 0 0 0\nv .2 0 0\nv 0 .3 0\nv 0 0 .4\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n")
	var model := fixture('<mujoco><compiler angle="radian"/><asset><mesh name="tetra" file="res://visual-tetra.obj" scale="2 3 4"/></asset><worldbody><body name="body" pos=".3 -.2 .8" euler=".2 .4 -.1"><geom name="mesh" type="mesh" mesh="tetra" pos=".1 .2 .3" euler=".3 -.2 .1"/><geom name="other" type="mesh" mesh="tetra" pos="-.2 .1 .2"/></body></worldbody></mujoco>')
	model.design.dependencies["res://visual-tetra.obj"] = FileAccess.get_sha256("res://visual-tetra.obj")
	var result := native_result(model); accept(model,result)
	assert_geometry(model,result,"scaled mesh visible transform")
	var identity: String = named(model,"mesh").id
	var other_id: String = named(model,"other").id
	var before := ids(model)
	command(model,{"op":"mesh_scale","id":identity,"value":Vector3(1,2,3)})
	result=native_result(model); accept(model,result)
	var geometry: Dictionary = result.geometry.filter(func(g):return g.name=="mesh")[0]
	check(view(model,identity).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==geometry.vertices and ids(model)[identity][1]==before[identity][1] and ids(model)[other_id]==before[other_id], "mesh scale replaces only changed Mesh data and preserves sibling resources")
	assert_geometry(model,result,"updated mesh scale final native geometry")
	var epoch: int = model.design.entity_snapshot().epoch
	var mesh: Dictionary = preload("res://addons/godot_mujoco/model/collision_settings.gd").mesh_asset(model.design,Xml.find(model.design.tree,identity))
	model.author_scene.apply_compiled(result); before=ids(model)
	model.design.mesh_options[mesh.id]={"octree_maxdepth":3}
	model.author_scene.build_geometry_step()
	check(model.design.entity_snapshot().epoch==epoch and ids(model)==before and model.author_scene.geometry_queue[0].get("_waiting",false), "mesh options invalidate queued source association independently of the tree epoch")
	accept(model,native_result(model)); dispose(model)

func path_and_release() -> void:
	var backing := BoxMesh.new(); backing.size=Vector3(.6,.8,1)
	ResourceSaver.save(backing,"res://visual-path-mesh.res")
	var geom := {"name":"path", "type":6, "size":Vector3(.3,.5,.4), "transform":Transform3D.IDENTITY, "mesh_path":"res://visual-path-mesh.res"}
	var visual := Visual.create(geom)
	var alias := MeshInstance3D.new(); alias.mesh=visual.mesh
	visual.mesh.size=Vector3(3,4,5)
	var prepared := Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh!=alias.mesh and visual.mesh.get_aabb().size.is_equal_approx(Vector3(.6,.8,1)) and alias.mesh.size==Vector3(3,4,5), "path-backed live Mesh mutation is privately corrected without mutating other users")
	var corrected := visual.mesh.get_instance_id()
	prepared=Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh.get_instance_id()==corrected,"recovered path-backed Mesh remains stable on the next no-op")
	var later := Visual.create(geom)
	check(later.mesh.get_aabb().size.is_equal_approx(Vector3(.6,.8,1)) and later.mesh!=alias.mesh,"new view bypasses a known mutated live cached Mesh still retained by another user")
	later.free()
	visual.mesh=SphereMesh.new()
	prepared=Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh is BoxMesh and visual.mesh.get_aabb().size.is_equal_approx(Vector3(.6,.8,1)), "path-backed mismatching live replacement is corrected on the same visual")
	prepared={}; alias.free(); visual.free()
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(.2,0,0),Vector3(0,0,.3)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	var triangle := ArrayMesh.new(); triangle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	ResourceSaver.save(triangle,"res://visual-path-array.res")
	geom.mesh_path="res://visual-path-array.res"; geom.type=7
	visual=Visual.create(geom); alias=MeshInstance3D.new(); alias.mesh=visual.mesh
	var changed: Array=alias.mesh.surface_get_arrays(0)
	changed[Mesh.ARRAY_VERTEX][1]=Vector3(1.2,0,0)
	alias.mesh.clear_surfaces(); alias.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,changed)
	prepared=Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh!=alias.mesh and visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX] and alias.mesh.get_aabb().size.x>visual.mesh.get_aabb().size.x, "path ArrayMesh changed observer privately restores canonical data and retains a mutated alias")
	corrected=visual.mesh.get_instance_id()
	prepared=Visual.prepare_update(visual,geom); Visual.apply_update(visual,prepared,geom.transform)
	check(visual.mesh.get_instance_id()==corrected,"recovered ArrayMesh fast path preserves identity")
	later=Visual.create(geom)
	check(later.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX] and later.mesh!=alias.mesh,"new ArrayMesh view cannot adopt a known mutated cached object")
	later.free()
	prepared={}; alias.free(); visual.free()
	ResourceSaver.save(triangle,"res://visual-path-shared-array.res")
	geom.mesh_path="res://visual-path-shared-array.res"
	var shared_a := Visual.create(geom); var shared_b := Visual.create(geom)
	check(shared_a.mesh==shared_b.mesh,"independent views can share one canonical path-backed Mesh")
	check(shared_a.mesh.changed.get_connections().filter(func(c):return c.callable.get_object()==Visual).size()==1,"one actual Mesh has only one weak presentation observer")
	var shared_id := shared_a.mesh.get_instance_id()
	for repeat in 3:
		Visual.apply_update(shared_a,Visual.prepare_update(shared_a,geom),geom.transform)
		Visual.apply_update(shared_b,Visual.prepare_update(shared_b,geom),geom.transform)
	check(shared_a.mesh.get_instance_id()==shared_id and shared_b.mesh.get_instance_id()==shared_id,"shared-Mesh observers remain deduplicated through repeated no-op application")
	var transient := Visual.create(geom)
	var weak_transient: WeakRef=weakref(transient)
	transient.free(); transient=null
	var marker := Visual.create({"name":"observer_prune", "type":2, "size":Vector3(.1,.1,.1), "transform":Transform3D.IDENTITY})
	check(weak_transient.get_ref()==null and shared_a.mesh.changed.get_connections().filter(func(c):return c.callable.get_object()==Visual).size()==1,"retiring one shared-Mesh subscriber leaves remaining invalidation connected")
	marker.free()
	alias=MeshInstance3D.new(); alias.mesh=shared_a.mesh
	changed=alias.mesh.surface_get_arrays(0); changed[Mesh.ARRAY_VERTEX][1]=Vector3(2.2,0,0)
	alias.mesh.clear_surfaces(); alias.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,changed)
	Visual.apply_update(shared_b,Visual.prepare_update(shared_b,geom),geom.transform)
	Visual.apply_update(shared_a,Visual.prepare_update(shared_a,geom),geom.transform)
	check(shared_a.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX] and shared_b.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==arrays[Mesh.ARRAY_VERTEX] and alias.mesh.get_aabb().size.x>shared_a.mesh.get_aabb().size.x,"a shared-Mesh change invalidates every live user before private repair")
	var held_mesh: Mesh=shared_a.mesh
	var weak_material_a: WeakRef=weakref(shared_a.material_override)
	shared_a.free(); shared_a=null
	marker=Visual.create({"name":"last_observer_prune", "type":2, "size":Vector3(.1,.1,.1), "transform":Transform3D.IDENTITY})
	check(held_mesh.changed.get_connections().filter(func(c):return c.callable.get_object()==Visual).is_empty() and weak_material_a.get_ref()==null,"last observer release disconnects without retaining its view or material")
	marker.free(); alias.free(); shared_b.free(); held_mesh=null
	var ephemeral := Visual.create({"name":"ephemeral", "type":2, "size":Vector3(.1,.1,.1), "transform":Transform3D.IDENTITY})
	var weak_mesh: WeakRef = weakref(ephemeral.mesh); var weak_material: WeakRef = weakref(ephemeral.material_override); var weak_view: WeakRef = weakref(ephemeral)
	ephemeral.free(); ephemeral=null
	check(weak_view.get_ref()==null and weak_mesh.get_ref()==null and weak_material.get_ref()==null,"live descriptor/ownership tracking does not retain freed visuals, Meshes or materials")

func topology_failure() -> void:
	var model := fixture(); accept(model,native_result(model))
	var identity: String = named(model,"box").id
	var before := ids(model)
	command(model,{"op":"rename","id":identity,"name":"renamed"}); accept(model,native_result(model))
	check(not model.visuals.has("box") and model.visuals.get("renamed")==view(model,identity) and ids(model)==before, "rename prunes old compatibility keys while retaining every visual identity")
	command(model,{"op":"reparent","id":identity,"parent_id":named(model,"target").id}); var result:=native_result(model); accept(model,result)
	check(ids(model)==before, "reparent retains unaffected and moved visual resources")
	assert_geometry(model,result,"reparent final visible native geometry")
	var original: Dictionary = model.design.author_snapshot()
	var duplicate := Commands.execute(model.design,{"op":"duplicate","id":identity})
	model.restore_author_snapshot(duplicate.after); accept(model,native_result(model))
	var copied := view(model,duplicate.selected)
	check(copied!=view(model,identity) and copied.material_override!=view(model,identity).material_override and ids(model)[identity]==before[identity], "duplicate creates its own mutable material while original identities survive")
	command(model,{"op":"delete","id":duplicate.selected,"confirmed":true}); accept(model,native_result(model))
	check(not model.visuals.has("renamed_copy") and ids(model)==before, "delete prunes only removed visual/maps and keeps unaffected identities")
	model.restore_author_snapshot(original); result=native_result(model); accept(model,result)
	var packed := PackedScene.new(); packed.pack(model)
	check(ResourceSaver.save(packed,"res://VisualSaved.tscn")==OK,"reused visual hierarchy saves")
	var reopened: Node = ResourceLoader.load("res://VisualSaved.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(reopened.design.author_snapshot()==model.design.author_snapshot() and reopened.get_node_or_null("target/renamed/_Visual")!=null,"save/reopen preserves stable source/hierarchy and visible resources")
	reopened.free()
	var visual := view(model,identity)
	var old_mesh := visual.mesh.get_instance_id(); var old_material := visual.material_override.get_instance_id(); var old_pose := visual.transform
	var broken := result.duplicate(true)
	for geometry in broken.geometry:
		if geometry.name=="renamed": geometry.mesh_path="res://missing-visual-mesh.res"
	model.author_scene.apply_compiled(broken); model.author_scene.build_geometry_step()
	check(not model.author_scene.geometry_queue.is_empty() and not model.last_error.is_empty() and visual.mesh.get_instance_id()==old_mesh and visual.material_override.get_instance_id()==old_material and visual.transform==old_pose, "failed mesh preparation retains the last valid visual and remains not ready")
	var world := World.new(); world.add_child(model)
	check(not world.all_author_visuals_ready(), "runtime readiness stays false for failed current presentation")
	model.author_scene.apply_compiled(result); check(drain(model),"matching result recovers after preparation failure")
	check(world.all_author_visuals_ready(), "runtime readiness becomes true only after current work drains")
	world.remove_child(model); world.free()
	var old: RefCounted = model.author_scene; old.shutdown()
	model.author_scene = Scene.new(); model.author_scene.initialize(model,false)
	check(drain(model) and ids(model)==before, "runtime initialize(false) seeds compatible live visuals across manager replacement")
	old.build_geometry_step()
	dispose(model)

func heavy_geometry(result: Dictionary) -> Dictionary:
	var changed := result.duplicate(true)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array()
	vertices.resize(180000); normals.resize(180000)
	for offset in range(0,vertices.size(),3):
		vertices[offset]=Vector3.ZERO; vertices[offset+1]=Vector3(.01,0,0); vertices[offset+2]=Vector3(0,0,.01)
		normals[offset]=Vector3.UP; normals[offset+1]=Vector3.UP; normals[offset+2]=Vector3.UP
	for geom in changed.geometry:
		geom.type=7; geom.vertices=vertices; geom.normals=normals
		geom.erase("mesh_path"); geom.erase("uvs")
	return changed

func queue_lifetime() -> void:
	var xml := '<mujoco><worldbody><body name="body"><joint name="hinge"/>'
	for index in 8: xml += '<geom name="g%d" type="box" size=".1 .1 .1" pos="%f 0 0"/>' % [index,index*.3]
	xml += '</body></worldbody><actuator><motor name="drive" joint="hinge"/></actuator></mujoco>'
	var model := fixture(xml); var current := native_result(model); accept(model,current)
	var world := World.new(); world.add_child(model)
	model.author_scene.apply_compiled(heavy_geometry(current)); model.author_scene.build_geometry_step()
	check(model.author_scene.geometry_queue.size()>0 and model.author_scene.geometry_queue.size()<8 and not world.all_author_visuals_ready(), "bounded expensive geometry preparation leaves meaningful multi-frame pending work")
	var partial := ids(model); var epoch: int = model.design.entity_snapshot().epoch
	var drive: Dictionary = Xml.section(model.design.tree,"actuator").children[0]
	model.design.initial_controls[drive.id]=.6
	model.author_scene.build_geometry_step()
	check(ids(model)==partial and model.design.entity_snapshot().epoch==epoch and model.author_scene.geometry_queue[0].get("_waiting",false) and not world.all_author_visuals_ready(), "same-tree-epoch control mutation retires stale queued work without false readiness")
	current=native_result(model); accept(model,current)
	check(world.all_author_visuals_ready(), "current source association drains after a retired queue")
	model.author_scene.apply_compiled(heavy_geometry(current)); model.author_scene.build_geometry_step(); partial=ids(model)
	model.design.initial_pose[named(model,"hinge").id]=[.3]
	model.author_scene.build_geometry_step()
	check(ids(model)==partial and not world.all_author_visuals_ready(), "same-revision initial pose mutation cannot drain an older accepted view")
	current=native_result(model); accept(model,current); assert_geometry(model,current,"initial-pose replacement visible state")
	model.author_scene.apply_compiled(heavy_geometry(current)); model.author_scene.build_geometry_step(); partial=ids(model)
	model.author_scene.cancel_compile(); model.author_scene.build_geometry_step()
	check(ids(model)==partial and not world.all_author_visuals_ready() and model.author_scene.compiled_status=="编译已取消", "cancel retires pending work and cannot certify presentation ready")
	accept(model,current)
	var node: Node3D = model.author_scene.nodes[named(model,"g0").id]
	node.transform.origin.x += .2; model.author_scene.node_transform_changed(node)
	var gesture := node.transform
	model.author_scene.apply_compiled(current); model.author_scene.build_geometry_step()
	check(node.transform==gesture and not world.all_author_visuals_ready(), "first unpublished native transform retires old queue and rejects old-source application")
	model.author_scene.pending_transforms.clear(); node.set_display_transform(node.displayed_transform); accept(model,current)
	model.author_scene.compile_token="latest"
	var stale := current.duplicate(true); stale.generation="old"; stale.revision=model.design.revision
	model.author_scene.apply_compiled(current); var pending: int=model.author_scene.geometry_queue.size()
	model.author_scene.apply_compiled(stale)
	check(model.author_scene.geometry_queue.size()==pending,"stale generation cannot supersede current accepted work")
	check(drain(model),"matching current queue still drains after stale rejection")
	model.author_scene.apply_compiled(heavy_geometry(current)); model.author_scene.build_geometry_step(); partial=ids(model)
	var old_design: Resource = model.design
	model.design = model.design.fork()
	model.author_scene.build_geometry_step()
	check(ids(model)==partial and not world.all_author_visuals_ready(),"resource replacement invalidates the old queued model/source identity")
	current=native_result(model); accept(model,current)
	old_design.touch()
	check(world.all_author_visuals_ready(),"old design signal is disconnected after new source publication")
	model.author_scene.apply_compiled(heavy_geometry(current)); model.author_scene.build_geometry_step()
	var retired: RefCounted = model.author_scene; retired.shutdown()
	model.author_scene=Scene.new(); model.author_scene.initialize(model,false)
	check(not world.all_author_visuals_ready() and drain(model),"runtime manager replacement owns and drains only current accepted work")
	partial=ids(model); retired.build_geometry_step()
	check(ids(model)==partial and world.all_author_visuals_ready(),"shutdown manager cannot publish into replacement host views")
	model.author_scene.geometry_queue=model.design.cached_geometry.duplicate(true)
	check(drain(model) and ids(model)==partial,"qualified legacy cached-geometry queue replay retains compatibility and identity")
	model.author_scene.shutdown(); model.author_scene=Scene.new(); model.author_scene.initialize(model,true)
	check(drain(model) and ids(model)==partial,"initialize(true) also reuses compatible current resources")
	model.author_scene.initialize(model,true)
	check(drain(model) and ids(model)==partial,"reinitializing the same manager republishes current work without stale artifact suppression")
	world.remove_child(model); world.free(); dispose(model)
	var empty := fixture('<mujoco><worldbody/></mujoco>')
	empty.author_scene.apply_compiled(native_result(empty))
	check(empty.author_scene.geometry_queue.is_empty() and empty.author_scene.compiled_status=="有效" and empty.visuals.is_empty(),"empty accepted geometry is immediately and meaningfully ready")
	dispose(empty)

func builder_failure() -> void:
	var model := fixture(); accept(model,native_result(model))
	model.design.cached_geometry[0].mesh_path="res://missing-builder-visual.res"
	var built: Node3D = Builder.create(model.design)
	check(built!=null and not built.last_error.is_empty() and not built.all_author_visuals_ready(), "SceneBuilder create returns a diagnostic world promptly on blocked visual preparation")
	var error: String=await Builder.prepare_tree(built)
	check(not error.is_empty(),"SceneBuilder prepare_tree propagates failed presentation instead of spinning")
	for child in built.get_children():
		if child is Model and child.author_scene: child.author_scene.shutdown()
	built.free()
	check((await Builder.save(model.design,"res://InvalidVisualSaved.tscn"))==ERR_INVALID_DATA and not FileAccess.file_exists("res://InvalidVisualSaved.tscn"),"SceneBuilder save propagates blocked visual failure")
	check((await Builder.save_playground(model.design,"res://InvalidVisualPlayground.tscn"))==ERR_INVALID_DATA and not FileAccess.file_exists("res://InvalidVisualPlayground.tscn"),"playground save has no null-world cascade or infinite drain on visual failure")
	dispose(model)

func run() -> void:
	identity_pose()
	appearance()
	raw_shapes()
	scaled_mesh_options()
	path_and_release()
	topology_failure()
	await process_frame
	queue_lifetime()
	await process_frame
	await builder_failure()
	await process_frame
	print("NODE_VISUAL_RESULT ",JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
