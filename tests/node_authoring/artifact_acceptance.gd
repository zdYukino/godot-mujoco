extends SceneTree
const Author = preload("res://addons/godot_mujoco/model/author_resource.gd")
const Artifact = preload("res://addons/godot_mujoco/model/editor_artifact.gd")
const Builder = preload("res://addons/godot_mujoco/model/author_builder.gd")
const Collision = preload("res://addons/godot_mujoco/model/collision_settings.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Scene = preload("res://addons/godot_mujoco/model/author_scene.gd")
const Service = preload("res://addons/godot_mujoco/model/compile_service.gd")
const Visual = preload("res://addons/godot_mujoco/model/model_visual.gd")
const Xml = preload("res://addons/godot_mujoco/model/author_xml.gd")
const SAVED := "res://artifact-qualified.tres"
const MESH := "res://artifact-source.obj"
const IMAGE := "res://artifact-source.png"
const RAW := "res://artifact-source.stl"
const OBJ := "v 0 0 0\nv 1 0 0\nv 0 1 0\nv 0 0 1\nf 1 3 2\nf 1 2 4\nf 1 4 3\nf 2 3 4\n"
var checks := 0
var failures: Array[String] = []
var evidence := {}
var builder_started := false
var builder_done := false
var builder_error := ""

func compile_async(design: Resource, context: Dictionary) -> void:
	builder_started = true
	builder_error = await Builder.compile_design(design, context)
	builder_done = true

func builder_stale_publication() -> void:
	for kind in ["source", "context"]:
		var design: Resource = Author.from_xml('<mujoco><worldbody><geom name="shape" size=".1"/></worldbody></mujoco>').design
		var context := Collision.context(null, design)
		builder_started = false; builder_done = false; builder_error = ""
		call_deferred("compile_async", design, context)
		while not builder_started: await process_frame
		if kind == "source": Xml.find(design.tree, design.entity_snapshot().geom_by_name.shape.id).attrs.rgba = ".2 .4 .8 1"
		else: context.limits.cells_per_world += 1
		design.cached_entities = [{"newer_cache":true}]
		var current: Dictionary = design.author_snapshot()
		for sample in 2000:
			if builder_done: break
			await create_timer(.01).timeout
		check(builder_done and builder_error.contains("changed"), "async builder rejects stale " + kind + " publication")
		check(design.author_snapshot() == current and design.cached_entities == [{"newer_cache":true}] and design.editor_artifact_stamp.is_empty(), "stale builder cannot overwrite newer source/cache or certify it")

func freed_map_recovery() -> void:
	var design: Resource = Author.from_xml('<mujoco><worldbody><body name="removed"><joint name="hinge"/><geom name="shape" size=".1"/></body><body name="kept"><geom name="anchor" size=".1"/></body></worldbody></mujoco>').design
	var model := model_fixture(design)
	var source: Dictionary = design.author_snapshot()
	var by_name := {}
	for entity in design.entities(): by_name[entity.name] = entity.id
	var kept: int = model.author_scene.nodes[by_name.kept].get_instance_id()
	model.author_scene.nodes[by_name.removed].free()
	var retired := Node3D.new(); model.author_scene.nodes["retired"] = retired; retired.free()
	model.author_scene.refresh_nodes()
	var recovered: bool = not model.author_scene.applying and not model.author_scene.nodes.has("retired")
	for entity in design.entities():
		var node: Variant = model.author_scene.nodes.get(entity.id)
		recovered = recovered and is_instance_valid(node) and not node.is_queued_for_deletion() and str(node.name) == entity.name and node.owner == model
	check(recovered and model.author_scene.nodes[by_name.kept].get_instance_id() == kept, "refresh recovers freed subtree/removal-map entries while retaining unaffected authored nodes")
	var queued: Node = model.author_scene.nodes[by_name.hinge]
	queued.queue_free()
	model.author_scene.refresh_nodes()
	var restored: Variant = model.author_scene.nodes.get(by_name.hinge)
	check(is_instance_valid(restored) and not restored.is_queued_for_deletion() and restored != queued and restored.get_parent() == model.author_scene.nodes[by_name.removed], "cancel refresh replaces a queued native node before its deferred deletion")
	check(design.author_snapshot() == source, "freed/queued native recovery preserves exact authored source")
	model.author_scene.shutdown(); model.free()
	await process_frame

func portable_number_storage() -> void:
	# IEEE64 values copied from the real G1 cold producer and saved warm request;
	# decimal GDScript literals would themselves pass through the faulty parser.
	for pair in [["69dd454a38654cbf", "45dd454a38654cbf"], ["b45035e92c189e3f", "b25035e92c189e3f"]]:
		var native: float = pair[0].hex_decode().decode_double(0)
		var saved: float = pair[1].hex_decode().decode_double(0)
		var parsed: Variant = str_to_var(var_to_str(native))
		check(var_to_bytes(parsed) == var_to_bytes(saved), "G1 raw decoded scalar reproduces the actual engine storage change")
		var identity := Artifact.payload_digest({"number":native})
		check(identity == Artifact.payload_digest({"number":saved}), "G1 scalar storage identity survives the native/saved rounding tie")
		for cycle in 6:
			parsed = str_to_var(var_to_str(parsed))
			check(identity == Artifact.payload_digest({"number":parsed}), "G1 scalar identity is stable across repeated engine save/parse cycles")
		check(Artifact.digest({"number":native}) != Artifact.digest({"number":saved}), "portable derived identity does not weaken exact authored-value identity")
	for bits in ["ffffffffffffef7f", "ffffffffffffefff", "0000000000000000", "0000000000000080", "000000000000f07f", "000000000000f0ff", "000000000000f87f"]:
		var value: float = bits.hex_decode().decode_double(0)
		check(Artifact.payload_digest({"number":value}) == Artifact.payload_digest({"number":str_to_var(var_to_str(value))}), "engine-storable finite extremes/zero/nonfinite values retain typed storage identity")
	var underflow := "0100000000000000".hex_decode().decode_double(0)
	check(str_to_var(var_to_str(underflow)) == 0.0 and Artifact.payload_digest({"number":underflow}) != Artifact.payload_digest({"number":0.0}), "engine storage underflow retains exact identity and safely misses instead of blessing zero")
	check(Artifact.payload_digest({"number":1.0}) != Artifact.payload_digest({"number":1}) and Artifact.payload_digest({"number":1.0}) != Artifact.payload_digest({"number":"1.0"}), "engine storage normalization preserves float/int/String distinction")
	# Exact float32-derived gizmo positions in an ordinary Array use the writer's
	# short scalar branch; scientific text preserves different, unsaved low bits.
	for bits in ["74d70c3f", "69ff833d", "00741abe"]:
		var native: float = bits.hex_decode().decode_float(0)
		var stored: Variant = str_to_var(var_to_str(native))
		check(Artifact.payload_digest({"number":native}) == Artifact.payload_digest({"number":stored}), "edited G1 float32-derived scalar matches its actual writer/parser storage")
		check(Artifact.digest({"number":native}) != Artifact.digest({"number":stored}), "edited G1 derived storage equivalence does not weaken exact source identity")
		var packed := PackedFloat64Array([native])
		var packed_stored: Variant = str_to_var(var_to_str(packed))
		check(Artifact.payload_digest({"number":packed}) == Artifact.payload_digest({"number":packed_stored}), "packed double elements qualify through their actual constructor storage context")
		check(Artifact.payload_digest({"number":packed}) != Artifact.payload_digest({"number":[native]}) and Artifact.payload_digest({"number":packed}) != Artifact.payload_digest({"number":PackedFloat32Array([native])}), "packed float64/plain Array/packed float32 retain separate typed identity")
	var storage := Author.new()
	var exact32: float = "74d70c3f".hex_decode().decode_float(0)
	storage.cached_entities = [{"scalar":exact32, "packed64":PackedFloat64Array([exact32]), "packed32":PackedFloat32Array([exact32]), "vector3":Vector3(exact32, exact32, exact32)}]
	check(ResourceSaver.save(storage, "res://number-storage.tres") == OK, "save actual resource storage containing scalar and packed/compound numeric contexts")
	var stored_resource: Resource = ResourceLoader.load("res://number-storage.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(Artifact.payload_digest({"entities":storage.cached_entities}) == Artifact.payload_digest({"entities":stored_resource.cached_entities}), "actual ResourceSaver/ResourceLoader preserves qualified scalar, packed64, packed32 and Vector3 identity")

func raw_mesh() -> PackedByteArray:
	var data := PackedByteArray(); data.resize(84); data.encode_u32(80, 4)
	var points := [Vector3.ZERO, Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for face in [[0,2,1], [0,1,3], [0,3,2], [1,2,3]]:
		var record := PackedByteArray(); record.resize(50)
		for corner in 3:
			var point: Vector3 = points[face[corner]]
			for axis in 3: record.encode_float(12 + corner * 12 + axis * 4, point[axis])
		data.append_array(record)
	return data

func write_raw(data: PackedByteArray, modified_time: int) -> void:
	var file := FileAccess.open(RAW, FileAccess.WRITE); file.store_buffer(data); file.close()
	var output := []
	var code := OS.execute(OS.get_environment("GMJ_TEST_PYTHON") if OS.has_environment("GMJ_TEST_PYTHON") else "python3", ["-c", "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))", ProjectSettings.globalize_path(RAW), str(modified_time)], output, true)
	check(code == 0, "pin raw dependency's timestamp to exercise a same-second mutation")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL ", label)

func _initialize() -> void:
	call_deferred("run")

func write(path: String, data: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(data); file.close()

func remove_worker_directory(path: String) -> void:
	for child in DirAccess.get_directories_at(path): remove_worker_directory(path.path_join(child))
	for child in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func worker(request: Dictionary, script := Service.WorkerPath) -> Dictionary:
	var service := Service.new(); service.worker_script = script
	root.add_child(service)
	service.submit(request)
	var result: Dictionary = await service.completed
	service.queue_free()
	return result

func request(design: Resource, context: Dictionary = {}) -> Dictionary:
	return {"op":"verify_or_compile", "author":design.author_snapshot(), "context":Collision.context(null, design) if context.is_empty() else context, "editor_artifact_stamp":design.editor_artifact_stamp, "payload":Artifact.payload(design)}

func design_fixture() -> Resource:
	write(MESH, OBJ)
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8); image.fill(Color(.2, .7, .3))
	check(image.save_png(IMAGE) == OK, "write source texture")
	var design: Resource = Author.from_xml('<mujoco><asset><mesh name="tetra" file="res://artifact-source.obj"/><texture name="tex" type="2d" file="res://artifact-source.png"/><material name="mat" texture="tex" texrepeat="2 3"/></asset><worldbody><body name="body" pos=".1 .2 .6"><joint name="hinge"/><geom name="shape" type="mesh" mesh="tetra" material="mat"/></body></worldbody></mujoco>').design
	design.dependencies = {MESH:FileAccess.get_sha256(MESH), IMAGE:FileAccess.get_sha256(IMAGE)}
	return design

func model_fixture(design: Resource) -> Node:
	var model := Model.new(); model.name = "ArtifactModel"; model.design = design
	model.author_scene = Scene.new(); model.author_scene.initialize(model)
	return model

func drain(model: Node) -> void:
	var error: String = model.author_scene.drain_geometry()
	check(error.is_empty(), "accepted actual presentation drains: " + error)

func identities(model: Node) -> Array:
	var geom: Dictionary = model.design.entity_snapshot().geom_by_name.shape
	var view: MeshInstance3D = model.author_scene.nodes[geom.id].get_node("_Visual")
	return [model.author_scene.nodes[geom.id].get_instance_id(), view.get_instance_id(), view.mesh.get_instance_id(), view.material_override.get_instance_id()]

func validate_model(model: Node) -> Dictionary:
	model.author_scene.queue_compile(); model.author_scene.due_ms = 0
	var packet: Dictionary = model.author_scene._validation_request()
	var result := await worker(packet)
	model.author_scene.compilation_finished(result)
	drain(model)
	return result

func reopen() -> void:
	var design: Resource = ResourceLoader.load(SAVED, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(design != null and not design.editor_artifact_stamp.is_empty(), "saved qualification survives independent resource load")
	if design:
		var before: Dictionary = design.author_snapshot()
		var result := await worker(request(design))
		check(result.get("success", false) and result.get("artifact_kind") == "hit", "new process verifies portable saved artifact without producing: kind=%s reason=%s error=%s" % [result.get("artifact_kind", ""), result.get("cache_miss_reason", ""), result.get("error", "")])
		check(not result.has("compiled_path") and not result.has("geometry") and not result.has("snapshot") and not result.has("author"), "hit is a small approval with no runtime MJB or rewritten payload")
		check(design.author_snapshot() == before and design.validate_dependencies().is_empty(), "reopen preserves source and current project-relative dependencies")
		check(not design.compiled_snapshot.xml.contains("/tmp/") and design.compiled_snapshot.xml.contains(MESH), "saved snapshot paths come from current source names")
		var model := model_fixture(design)
		result = await validate_model(model)
		check(result.get("artifact_kind") == "hit" and model.author_scene.editor_ready(), "reopened actual preview reaches current editor readiness: kind=%s state=%s error=%s" % [result.get("artifact_kind", ""), model.author_scene.verification_state, model.last_error])
		var before_ids := identities(model)
		result = await validate_model(model)
		check(result.get("artifact_kind") == "hit" and identities(model) == before_ids, "qualified replay preserves equivalent authored/visual/Mesh/material identities")
		model.author_scene.shutdown(); model.free()
	print("NODE_ARTIFACT_REOPEN_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func run() -> void:
	if "--artifact-reopen" in OS.get_cmdline_user_args():
		await reopen(); return
	await freed_map_recovery()
	portable_number_storage()
	var design := design_fixture()
	var source: Dictionary = design.author_snapshot()
	var result := await worker(request(design))
	check(result.get("success", false) and result.get("artifact_kind") == "compiled", "metadata-free design safely compiles once: " + str(result.get("error", "")))
	if not result.get("success", false): finish(); return
	check(result.cache_miss_reason.contains("schema"), "legacy miss has a reason")
	check(Builder.apply_result(design, result).is_empty() and design.cache_path.is_empty(), "producer stores portable stamp without scratch ownership")
	check(design.author_snapshot() == source and not design.editor_artifact_stamp.is_empty(), "derived qualification never changes authored content")
	check(not design.author_snapshot().has("editor_artifact_stamp"), "cache metadata is excluded from source identity")
	check(design.compiled_snapshot.xml.contains(MESH) and not design.compiled_snapshot.xml.contains(ProjectSettings.globalize_path("res://")), "new snapshot source-named assets are portable")
	check(Artifact.candidate_reason(source, Collision.context(null,design), Artifact.payload(design), design.editor_artifact_stamp).is_empty(), "complete producer qualification matches its payload")
	check(ResourceSaver.save(design, SAVED) == OK, "save qualified resource through normal persistence")
	# Original worker/MJB directory is deliberately absent before all warm tests.
	remove_worker_directory(result.directory)
	check(not FileAccess.file_exists(result.compiled_path) and not DirAccess.dir_exists_absolute(result.directory), "warm artifact has no original producer directory, dependency copies or scratch MJB")
	result = await worker(request(design))
	check(result.get("success", false) and result.get("artifact_kind") == "hit" and not result.has("compiled_path"), "verified hit needs no scratch/native model result")
	check(not result.has("geometry") and not result.has("entities") and not result.has("snapshot"), "hit leaves existing payload arrays in place")
	var output: Array = []
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://artifact_acceptance.gd", "--", "--artifact-reopen"], output, true)
	var child_log := "".join(output)
	check(exit_code == 0 and child_log.contains('"failed":0') and not child_log.contains("SCRIPT ERROR:") and not child_log.contains("ERROR:"), "save/reopen in a new process with original worker scratch absent: " + child_log.right(5000))
	evidence.reopen_output = output
	for kind in ["schema", "producer", "payload", "source", "context"]:
		var packet := request(design).duplicate(true)
		match kind:
			"schema": packet.editor_artifact_stamp.schema = 0
			"producer": packet.editor_artifact_stamp.producer.contract = -1
			"payload": packet.payload.geometry[0].color = Color.MAGENTA
			"source": Xml.find(packet.author.tree, design.entity_snapshot().geom_by_name.shape.id).attrs.pos = ".3 0 0"
			"context": packet.context.limits.cells_per_world += 1
		var changed := await worker(packet)
		check(changed.get("success", false) and changed.get("artifact_kind") == "compiled" and not changed.get("cache_miss_reason", "").is_empty(), kind + " mismatch safely validates in one producing worker")
		if kind == "producer": check(not changed.get("repaired_preview_paths", []).is_empty(), "incompatible producer never blesses old generated files by existence")
		if kind == "source": check(changed.author.revision == design.revision and changed.editor_artifact_stamp.author_digest != design.editor_artifact_stamp.author_digest, "same revision does not qualify different source")
	var missing_mesh: String = design.cached_geometry[0].mesh_path
	DirAccess.remove_absolute(missing_mesh)
	var restored := await worker(request(design))
	check(restored.get("success", false) and restored.get("artifact_kind") == "compiled" and restored.repaired_preview_paths.has(missing_mesh) and FileAccess.file_exists(missing_mesh), "missing required preview is a repairable miss rather than a source dependency error")
	Builder.apply_result(design, restored)
	check(Artifact.payload_digest({"item":1.0}) != Artifact.payload_digest({"item":{"float":"1.000000000000e+00"}}), "portable payload precision preserves float/Dictionary type identity")
	check(Artifact.payload_digest({"item":1.0}) != Artifact.payload_digest({"item":["float",0,"1"]}), "portable payload precision preserves float/Array type identity")
	check(Artifact.payload_digest({"pose":Transform3D(Basis.IDENTITY, Vector3(0,0,-0.0))}) == Artifact.payload_digest({"pose":Transform3D.IDENTITY}), "portable payload canonicalizes text-serialized signed zero")
	var near_ten := "ffffffffffff2340".hex_decode().decode_double(0)
	check(Artifact.payload_digest({"value":near_ten}) == Artifact.payload_digest({"value":str_to_var(var_to_str(near_ten))}), "numeric storage identity handles a decimal exponent boundary without hand rounding bins")
	for malformed in ["geometry", "collision_geometry", "manifest"]:
		var packet := request(design).duplicate(true)
		if malformed == "manifest": packet.editor_artifact_stamp.preview_files = {17:"invalid"}
		else: packet.payload[malformed] = [17]
		var repaired := await worker(packet)
		check(repaired.get("success", false) and repaired.get("artifact_kind") == "compiled", "malformed derived " + malformed + " safely misses without a foreground/worker script error")
	var malformed: Resource = design.fork()
	malformed.cached_entities = [{}]; malformed.cached_geometry = [{}]; malformed.collision_geometry = [{}]; malformed.collision_stats = [{}]
	var malformed_model := model_fixture(malformed)
	check(malformed.cached_entities.is_empty() and malformed.cached_geometry.is_empty() and malformed.collision_geometry.is_empty() and malformed.collision_stats.is_empty(), "malformed saved payload initializes safely before Inspector/visual consumers")
	var repaired := await validate_model(malformed_model)
	check(repaired.get("artifact_kind") == "compiled" and malformed_model.author_scene.editor_ready(), "malformed initialized payload reaches worker miss and current repaired preview")
	malformed_model.author_scene.shutdown(); malformed_model.free()
	# Exercise a well-formed wrong Mesh and Texture already retained in the main
	# process loader/B state before the worker repairs their original paths.
	var geom: Dictionary = design.cached_geometry[0]
	var wrong_shape := BoxMesh.new(); wrong_shape.size = Vector3.ONE * 9
	var wrong := ArrayMesh.new(); wrong.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wrong_shape.surface_get_arrays(0))
	check(ResourceSaver.save(wrong, geom.mesh_path, ResourceSaver.FLAG_COMPRESS) == OK, "replace derived mesh with a valid wrong resource")
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8); image.fill(Color.MAGENTA)
	var wrong_texture := ImageTexture.create_from_image(image)
	check(ResourceSaver.save(wrong_texture, geom.texture_path, ResourceSaver.FLAG_COMPRESS) == OK, "replace derived texture with valid wrong pixels")
	var model := model_fixture(design)
	drain(model)
	var entity: Dictionary = design.entity_snapshot().geom_by_name.shape
	var view: MeshInstance3D = model.author_scene.nodes[entity.id].get_node("_Visual")
	check(view.mesh.get_aabb().size.is_equal_approx(Vector3.ONE * 9) and view.material_override.albedo_texture.get_image().get_pixel(0,0).is_equal_approx(Color.MAGENTA), "wrong resources are genuinely loaded and remembered before repair")
	var second := Visual.create(geom)
	check(second.mesh is ArrayMesh and second.mesh == view.mesh and second.material_override.albedo_texture == view.material_override.albedo_texture, "two existing tracked views genuinely share the wrong cached ArrayMesh and Texture")
	var script: Script = design.get_script()
	result = await validate_model(model)
	check(result.get("artifact_kind") == "compiled" and result.get("repaired_preview_paths", []).has(geom.mesh_path) and result.get("repaired_preview_paths", []).has(geom.texture_path), "derived byte mismatch compiles and publishes explicit targeted repairs")
	check(view == model.author_scene.nodes[entity.id].get_node("_Visual") and view.mesh.get_aabb().size.length() < 3, "repair replaces wrong actual mesh data and preserves the view")
	check(view.material_override.albedo_texture.get_image().get_pixel(0,0).g > .6 and view.material_override.albedo_texture.get_image().get_pixel(0,0).r < .3, "repair overrides wrong already-cached texture pixels")
	check(second.mesh.get_aabb().size.is_equal_approx(Vector3.ONE * 9) and second.material_override.albedo_texture.get_image().get_pixel(0,0).is_equal_approx(Color.MAGENTA), "repairing A does not silently mutate B's shared old resources")
	var second_update := Visual.prepare_update(second, model.design.cached_geometry[0])
	check(second_update.error.is_empty(), "existing B prepares a normal nonfresh update after A's repair")
	if second_update.error.is_empty(): Visual.apply_update(second, second_update, second.transform)
	check(second.mesh.get_aabb().size.length() < 3 and second.material_override.albedo_texture.get_image().get_pixel(0,0).g > .6, "normal nonfresh B update rejects remembered wrong Mesh/Texture and repairs actual bounds/pixels")
	var valid_second := [second.get_instance_id(), second.mesh.get_instance_id(), second.material_override.get_instance_id(), second.material_override.albedo_texture.get_instance_id()]
	second_update = Visual.prepare_update(second, model.design.cached_geometry[0])
	var second_writes: bool = Visual.apply_update(second, second_update, second.transform) if second_update.error.is_empty() else true
	check(not second_writes and valid_second == [second.get_instance_id(), second.mesh.get_instance_id(), second.material_override.get_instance_id(), second.material_override.albedo_texture.get_instance_id()], "matching valid B replay preserves view/Mesh/material/Texture identities without writes")
	second.free()
	var later := Visual.create(model.design.cached_geometry[0])
	check(later.mesh.get_aabb().size.length() < 3 and later.material_override.albedo_texture.get_image().get_pixel(0,0).g > .6, "a later new view cannot re-adopt the repaired path's old wrong loader-cache objects")
	later.free()
	check(design.get_script() == script and model.author_scene.editor_ready(), "repair leaves executing Script identity and current readiness intact")
	var before_ids := identities(model)
	result = await validate_model(model)
	check(result.get("artifact_kind") == "hit" and identities(model) == before_ids, "repaired artifact next warm hit preserves all compatible identities")
	# Fresh file verification distinguishes author dependencies from previews.
	write(MESH, OBJ.replace("v 1 0 0", "v 2 0 0"))
	check(FileAccess.get_file_as_bytes(MESH).size() == OBJ.to_utf8_buffer().size(), "dependency mutation has unchanged byte count")
	var original_manifest: Dictionary = design.dependencies.duplicate(true)
	result = await worker(request(design))
	check(not result.get("success", true) and result.get("error", "").contains("hash mismatch") and not result.has("editor_artifact_stamp"), "modified declared dependency is an error, never a blessed compile miss")
	check(design.dependencies == original_manifest, "failure cannot rewrite the expected source dependency manifest")
	model.author_scene._resources_reimported(PackedStringArray([MESH]))
	check(not model.author_scene.editor_ready() and model.author_scene.verification_state == "pending", "same-size relevant notification immediately retires approval")
	write(MESH, OBJ)
	DirAccess.rename_absolute(MESH, MESH + ".absent")
	result = await worker(request(design))
	check(not result.get("success", true) and result.get("error", "").contains("Missing author dependency"), "missing declared dependency is a clear validation error")
	DirAccess.rename_absolute(MESH + ".absent", MESH)
	var race_packet := request(design); race_packet.op = "compile"
	result = await worker(race_packet, "res://artifact_race_worker.gd")
	check(not result.get("success", true) and result.get("error", "").contains("dependency"), "source race across native production cannot publish a qualification")
	write(MESH, OBJ)
	result = await validate_model(model)
	check(model.author_scene.editor_ready(), "current repaired source can verify again")
	# Readiness never relies on serialized revision or an old result token.
	model.author_scene.queue_compile(); model.author_scene.due_ms = 0
	var packet: Dictionary = model.author_scene._validation_request()
	var late := await worker(packet)
	model.design.initial_controls["alias-only"] = .5
	model.author_scene.compilation_finished(late)
	check(not model.author_scene.editor_ready(), "same-revision initial-state alias rejects an in-flight verification reply")
	model.design.initial_controls.erase("alias-only")
	model.author_scene.queue_compile(); model.author_scene.due_ms = 0
	packet = model.author_scene._validation_request()
	late = await worker(packet)
	model.author_scene.cancel_compile()
	model.author_scene.compilation_finished(late)
	check(model.author_scene.verification_state == "cancelled" and not model.author_scene.editor_ready(), "cancelled generation cannot release the gate via a late hit")
	check(identities(model) == before_ids, "pending/error/cancel states preserve the last visible valid preview")
	result = await validate_model(model)
	check(model.author_scene.editor_ready(), "later current verification recovers from cancellation")
	var invalid := request(design).duplicate(true); invalid.author.dependencies[17] = "invalid"
	result = await worker(invalid)
	check(not result.get("success", true) and result.get("error", "").contains("belong to this project"), "non-String declared dependency reaches the explicit worker error boundary")
	var manifest: Dictionary = design.dependencies.duplicate(true)
	design.dependencies[17] = "invalid"; model.author_scene.queue_compile()
	check(not model.author_scene.editor_ready(), "invalid observation paths cannot raise a foreground FileAccess type error or retain readiness")
	design.dependencies = manifest
	result = await validate_model(model)
	var jobs: int = model.author_scene.compiler.serial if model.author_scene.compiler else 0
	for tick in 30: model.author_scene.poll()
	check(model.author_scene.editor_ready() and (not model.author_scene.compiler or model.author_scene.compiler.serial == jobs), "settled idle polling schedules no verification or compile jobs")
	var old_budget: Variant = ProjectSettings.get_setting("mujoco/authoring/sdf_max_cells_per_world", 2000000)
	ProjectSettings.set_setting("mujoco/authoring/sdf_max_cells_per_world", int(old_budget) + 1)
	check(not model.author_scene.editor_ready(), "validation budget change immediately closes current readiness")
	ProjectSettings.set_setting("mujoco/authoring/sdf_max_cells_per_world", old_budget)
	await raw_notifications()
	await builder_stale_publication()
	var savable: Resource = Author.from_xml('<mujoco><worldbody><geom name="box" type="box" size=".1 .2 .3"/></worldbody></mujoco>').design
	check(await preload("res://addons/godot_mujoco/model/scene_builder.gd").save(savable, "res://artifact-builder.tscn") == OK, "SceneBuilder prepare_tree actually compiles a stale design and saves")
	check(not savable.editor_artifact_stamp.is_empty() and Artifact.candidate_reason(savable.author_snapshot(), Collision.context(null,savable), Artifact.payload(savable), savable.editor_artifact_stamp).is_empty(), "compiled builder replay preserves the producer's portable stamp")
	# Earlier cases deliberately replace/remove and regenerate shared generated
	# files. Their byte hashes may change even when the repaired data is equal.
	# Publish the separate portable/reopen fixture only after those mutations.
	result = await validate_model(model)
	check(result.get("success", false) and model.author_scene.editor_ready() and model.design.author_snapshot() == source, "portable fixture is freshly qualified with unchanged source after destructive cache cases")
	var portable_producer_directory: String = model.author_scene.artifact.get("directory", "")
	if not portable_producer_directory.is_empty() and DirAccess.dir_exists_absolute(portable_producer_directory): remove_worker_directory(portable_producer_directory)
	check(not portable_producer_directory.is_empty() and not DirAccess.dir_exists_absolute(portable_producer_directory), "final portable fixture's accepted producer scratch is absent before save/relocation")
	check(ResourceSaver.save(model.design, SAVED) == OK, "save the current qualified portable fixture for the subsequent relocation stage")
	var current_preview_files := true
	for path in model.design.editor_artifact_stamp.preview_files:
		if FileAccess.get_sha256(path) != model.design.editor_artifact_stamp.preview_files[path]: current_preview_files = false
	check(current_preview_files, "portable fixture's declared preview bytes are current immediately before relocation")
	# Saving metadata cannot inject a cache into native authoritative composition.
	# Enter only after preparing the current off-tree preview; registration is
	# deferred so this test does not start an unrelated authoritative world.
	model.author_registration_deferred = true
	model.author_scene.shutdown()
	root.add_child(model)
	var definition: Dictionary = model.author_definition()
	check(not definition.has("compiled_path") and not definition.has("editor_artifact_stamp") and definition.xml.contains(ProjectSettings.globalize_path(MESH)), "runtime definition still composes current source-named XML, never a scratch MJB")
	model.author_scene.shutdown(); model.free()
	finish()

func raw_notifications() -> void:
	var bytes := raw_mesh(); write_raw(bytes, int(Time.get_unix_time_from_system()))
	var raw: Resource = Author.from_xml('<mujoco><asset><mesh name="raw" file="res://artifact-source.stl"/></asset><worldbody><geom name="shape" type="mesh" mesh="raw"/></worldbody></mujoco>').design
	raw.dependencies = {RAW:FileAccess.get_sha256(RAW)}
	var produced := await worker(request(raw))
	check(produced.get("success", false), "raw non-imported dependency compiles for notification fixture: " + str(produced.get("error", "")))
	if not produced.get("success", false): return
	Builder.apply_result(raw, produced)
	var model := model_fixture(raw)
	await validate_model(model)
	check(model.author_scene.editor_ready(), "raw source starts currently verified")
	model.author_scene._publish_geometry(raw.cached_geometry, raw.author_snapshot(), raw.entity_snapshot())
	var generation: int = model.author_scene._queue_generation
	model.author_scene._filesystem_changed()
	check(model.author_scene._queue_generation > generation and model.author_scene.geometry_queue[0].get("_waiting", false), "file invalidation retires an accepted unfinished visual audit")
	var before_nodes := identities(model)
	model.author_scene.build_geometry_step()
	check(identities(model) == before_nodes and not model.author_scene.editor_ready(), "old dependency-generation visual work cannot write or release readiness")
	await validate_model(model)
	var observed := Artifact.observe_files([RAW])
	var changed := bytes.duplicate(); changed[0] = 73
	write_raw(changed, int(observed[RAW][0]))
	check(Artifact.observe_files([RAW]) == observed and FileAccess.get_sha256(RAW) != raw.dependencies[RAW], "raw changed bytes retain both observed timestamp and byte count")
	model.author_scene._filesystem_changed()
	check(not model.author_scene.editor_ready() and model.author_scene.verification_state == "pending", "ambiguous same-second raw-source event immediately closes readiness")
	model.author_scene.due_ms = 0
	var packet: Dictionary = model.author_scene._validation_request()
	var failed := await worker(packet); model.author_scene.compilation_finished(failed)
	check(model.author_scene.verification_state == "error" and not model.author_scene.editor_ready(), "raw byte mismatch remains a validation error until manifest/source is repaired")
	write_raw(bytes, int(observed[RAW][0])); await validate_model(model)
	write_raw(changed, int(observed[RAW][0]))
	model.author_scene.queue_compile(); model.author_scene.due_ms = 0
	packet = model.author_scene._validation_request()
	failed = await worker(packet)
	write_raw(bytes, int(observed[RAW][0])); model.author_scene._filesystem_changed()
	model.author_scene.compilation_finished(failed)
	check(model.author_scene.verification_state == "pending" and model.author_scene.due_ms > 0, "late source failure cannot discard a coalesced same-second repair notification")
	model.author_scene.due_ms = 0; packet = model.author_scene._validation_request()
	var recovered := await worker(packet); model.author_scene.compilation_finished(recovered); drain(model)
	check(recovered.get("artifact_kind") == "hit" and model.author_scene.editor_ready(), "latest repaired raw bytes reverify without manual edits or another native model result")
	# Coalesce an ambiguous event during production. Its successful candidate is
	# private until one follow-up verifier checks the actual current bytes.
	raw.editor_artifact_stamp = {}
	model.author_scene.queue_compile(); model.author_scene.due_ms = 0
	packet = model.author_scene._validation_request()
	produced = await worker(packet)
	check(produced.get("artifact_kind") == "compiled", "pending-notification fixture really produces a legacy miss")
	model.author_scene._filesystem_changed()
	model.author_scene.compilation_finished(produced)
	check(not model.author_scene.editor_ready() and model.author_scene.verification_state == "pending" and not model.author_scene._staged_compiled.is_empty(), "ambiguous pending event cannot approve the producer's reply")
	model.author_scene.due_ms = 0; packet = model.author_scene._validation_request()
	var follow_up := await worker(packet)
	check(follow_up.get("artifact_kind") == "hit" and not follow_up.has("compiled_path"), "follow-up checks staged production without a second native model result")
	model.author_scene.compilation_finished(follow_up); drain(model)
	check(model.author_scene.editor_ready(), "current staged result publishes only after the follow-up verifies")
	model.author_scene._resources_reimported(PackedStringArray(["res://unrelated.png"]))
	check(model.author_scene.editor_ready() and model.author_scene.due_ms == 0, "specific unrelated file notifications do not schedule jobs")
	for tick in 30: model.author_scene.poll()
	check(model.author_scene.editor_ready() and model.author_scene.due_ms == 0, "own publication and coalesced follow-up settle without repeated idle jobs")
	model.author_scene.shutdown(); model.free()

func finish() -> void:
	var report := {"checks":checks,"failed":failures.size(),"failures":failures,"evidence":evidence}
	FileAccess.open("res://artifact-result.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("NODE_ARTIFACT_RESULT ", JSON.stringify({"checks":checks,"failed":failures.size(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
