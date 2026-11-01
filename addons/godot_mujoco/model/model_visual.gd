@tool
extends RefCounted
# Weak live-view state survives AuthorScene replacement without owning nodes or
# resources. It is presentation history, not a source/compiled artifact cache.
static var _states := {}
static var _changed_meshes := {}
static var _changed_textures := {}
static var _mesh_watches := {}

static func describe(geom: Dictionary) -> Dictionary:
	var size: Vector3 = geom.get("source_size", geom.size)
	var shape := {}
	if geom.has("mesh_path"):
		shape.mesh_path = str(geom.mesh_path)
	else:
		shape.type = int(geom.type)
		match int(geom.type):
			0: shape.size = Vector2(maxf(2 * size.x, 10), maxf(2 * size.y, 10))
			2: shape.size = size.x
			3, 5: shape.size = Vector2(size.x, size.y)
			6: shape.size = size
			1, 7, 8:
				shape.vertices = geom.get("vertices", PackedVector3Array())
				shape.normals = geom.get("normals", PackedVector3Array())
				shape.has_uvs = geom.has("uvs")
				if geom.has("uvs"): shape.uvs = geom.uvs
		shape.projected = (geom.has("texture_image") or geom.has("texture_path")) and not geom.has("uvs")
		if shape.projected:
			shape.projection_size = size
			shape.uniform = geom.get("texture_uniform", false)
	var image: Dictionary = geom.get("texture_image", {})
	var texture_value := {}
	if geom.has("texture_path"): texture_value.path = str(geom.texture_path)
	elif geom.has("texture_image"): texture_value.image = image.duplicate(true)
	return {"shape":shape, "material":{"color":geom.get("color", Color("8094a8")), "texture":texture_value, "repeat":geom.get("texture_repeat", Vector2.ONE), "alpha":geom.get("color", Color("8094a8")).a < 1.0 or geom.get("texture_alpha", false) or image.get("channels", 3) == 4}}

static func shape_scale(geom: Dictionary) -> Vector3:
	var size: Vector3 = geom.get("source_size", geom.size)
	return Vector3(size.x, size.z, size.y) if int(geom.type) == 4 else Vector3.ONE

static func _track(instance: MeshInstance3D) -> Dictionary:
	var identity := instance.get_instance_id()
	if _states.has(identity) and _states[identity].view.get_ref() == instance: return _states[identity]
	for key in _states.keys():
		if not is_instance_valid(_states[key].view.get_ref()):
			_disconnect_mesh(_states[key]); _states.erase(key)
	for key in _changed_meshes.keys():
		if not is_instance_valid(_changed_meshes[key].get_ref()): _changed_meshes.erase(key)
	for key in _changed_textures.keys():
		if not is_instance_valid(_changed_textures[key].get_ref()): _changed_textures.erase(key)
	var state := {"view":weakref(instance), "identity":identity, "descriptor":{}, "owned_material":0, "mesh":null, "mesh_identity":0, "mesh_dirty":false}
	_states[identity] = state
	return state

static func _disconnect_mesh(state: Dictionary) -> void:
	var identity: int = state.get("mesh_identity", 0)
	state.mesh = null; state.mesh_identity = 0
	if not _mesh_watches.has(identity): return
	var watch: Dictionary = _mesh_watches[identity]
	watch.views.erase(state.identity)
	_prune_watch(identity, watch)

static func _prune_watch(identity: int, watch: Dictionary) -> void:
	var mesh: Mesh = watch.mesh.get_ref()
	for key in watch.views.keys():
		var view: MeshInstance3D = watch.views[key].get_ref()
		if not is_instance_valid(view) or view.mesh != mesh: watch.views.erase(key)
	if mesh and not watch.views.is_empty(): return
	if mesh:
		if mesh.changed.is_connected(watch.callback): mesh.changed.disconnect(watch.callback)
		# Once observation ends an external alias may change this cached object.
		# Future new views must prepare privately rather than assume it is intact.
		_changed_meshes[identity] = weakref(mesh)
	_mesh_watches.erase(identity)

static func _mesh_changed(identity: int) -> void:
	if not _mesh_watches.has(identity): return
	var watch: Dictionary = _mesh_watches[identity]
	var mesh: Mesh = watch.mesh.get_ref()
	if mesh: _changed_meshes[identity] = weakref(mesh)
	for key in watch.views:
		if not _states.has(key): continue
		var state: Dictionary = _states[key]
		if state.get("mesh") and state.mesh.get_ref() == mesh: state.mesh_dirty = true
	_prune_watch(identity, watch)

static func _observe_mesh(instance: MeshInstance3D, state: Dictionary) -> void:
	if state.get("mesh") and state.mesh.get_ref() == instance.mesh and _mesh_watches.has(state.mesh_identity):
		state.mesh_dirty = false
		_mesh_watches[state.mesh_identity].views[state.identity] = state.view
		return
	_disconnect_mesh(state)
	state.mesh = weakref(instance.mesh) if instance.mesh else null
	state.mesh_identity = instance.mesh.get_instance_id() if instance.mesh else 0
	state.mesh_dirty = false
	if not instance.mesh: return
	var identity: int = state.mesh_identity
	if not _mesh_watches.has(identity):
		var callback := _mesh_changed.bind(identity)
		_mesh_watches[identity] = {"mesh":weakref(instance.mesh), "callback":callback, "views":{}}
		if not instance.mesh.changed.is_connected(callback): instance.mesh.changed.connect(callback)
	_mesh_watches[identity].views[state.identity] = state.view

static func seed(instance: MeshInstance3D, geom: Dictionary) -> void:
	var state := _track(instance)
	if not state.descriptor.is_empty(): return
	var descriptor := describe(geom)
	# A path alone cannot certify a saved or externally replaced live Mesh.
	# Untracked path resources are checked against prepared data on first apply.
	if not descriptor.shape.has("mesh_path") and _mesh_matches(instance.mesh, descriptor.shape):
		state.descriptor = descriptor.duplicate(true)
		_observe_mesh(instance, state)

static func _mesh_matches(mesh: Mesh, shape: Dictionary) -> bool:
	if not mesh: return false
	if shape.has("mesh_path"): return mesh.resource_path == shape.mesh_path
	if shape.get("projected", false): return false
	match int(shape.type):
		0: return mesh is PlaneMesh and mesh.size.is_equal_approx(shape.size)
		2: return mesh is SphereMesh and is_equal_approx(mesh.radius, shape.size) and is_equal_approx(mesh.height, 2 * shape.size)
		3: return mesh is CapsuleMesh and is_equal_approx(mesh.radius, shape.size.x) and is_equal_approx(mesh.height, 2 * (shape.size.x + shape.size.y))
		4: return mesh is SphereMesh and is_equal_approx(mesh.radius, 1) and is_equal_approx(mesh.height, 2)
		5: return mesh is CylinderMesh and is_equal_approx(mesh.top_radius, shape.size.x) and is_equal_approx(mesh.bottom_radius, shape.size.x) and is_equal_approx(mesh.height, 2 * shape.size.y)
		6: return mesh is BoxMesh and mesh.size.is_equal_approx(Vector3(shape.size.x, shape.size.z, shape.size.y) * 2)
		1, 7, 8:
			if not mesh is ArrayMesh or mesh.get_surface_count() != 1: return false
			if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: return false
			var arrays := mesh.surface_get_arrays(0)
			if arrays[Mesh.ARRAY_VERTEX] != shape.vertices or arrays[Mesh.ARRAY_NORMAL] != shape.normals: return false
			if shape.has_uvs and arrays[Mesh.ARRAY_TEX_UV] != shape.uvs: return false
			for index in Mesh.ARRAY_MAX:
				if index in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL] or (index == Mesh.ARRAY_TEX_UV and shape.has_uvs): continue
				if arrays[index] != null and not arrays[index].is_empty(): return false
			return true
	return false

static func _same_mesh(left: Mesh, right: Mesh) -> bool:
	if not left or not right or left.get_surface_count() != right.get_surface_count(): return false
	if not (left is ArrayMesh or left is PrimitiveMesh) or not (right is ArrayMesh or right is PrimitiveMesh): return false
	for surface in left.get_surface_count():
		var left_primitive: int = left.surface_get_primitive_type(surface) if left is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		var right_primitive: int = right.surface_get_primitive_type(surface) if right is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		if left_primitive != right_primitive: return false
		if left.surface_get_arrays(surface) != right.surface_get_arrays(surface): return false
	return true

static func _trusted_mesh(instance: MeshInstance3D, state: Dictionary, geom: Dictionary, shape: Dictionary) -> bool:
	if not instance or not instance.mesh: return false
	if not shape.has("mesh_path") and not shape.get("projected", false): return _mesh_matches(instance.mesh, shape)
	var identity := instance.mesh.get_instance_id()
	if _changed_meshes.has(identity) and _changed_meshes[identity].get_ref() == instance.mesh: return false
	if not state.get("mesh") or state.mesh.get_ref() != instance.mesh or state.mesh_dirty: return false
	# Primitive properties can change before their deferred changed signal.
	if instance.mesh is PrimitiveMesh:
		var raw := geom.duplicate()
		raw.erase("mesh_path")
		return _mesh_matches(instance.mesh, describe(raw).shape)
	return true

static func _private_material(instance: MeshInstance3D, state: Dictionary) -> bool:
	var material: Material = instance.material_override
	if not material or state.owned_material != material.get_instance_id(): return false
	# Extra references may be an unregistered external alias. Be conservative on
	# a necessary edit; unchanged results never clone merely to claim ownership.
	if material.get_reference_count() > 2: return false
	for other in _states.values():
		var view: MeshInstance3D = other.view.get_ref()
		if is_instance_valid(view) and view != instance and view.material_override == material: return false
	return true

static func _current_texture(instance: MeshInstance3D) -> Texture2D:
	if not instance: return null
	var material := instance.material_override as StandardMaterial3D
	return material.albedo_texture if material else null

static func _same_texture(left: Texture2D, right: Texture2D) -> bool:
	if not left or not right: return false
	var actual := left.get_image(); var expected := right.get_image()
	return actual and expected and actual.get_format() == expected.get_format() and actual.get_size() == expected.get_size() and actual.get_data() == expected.get_data()

static func _prepare_texture(value: Dictionary, existing: Texture2D, fresh := false) -> Dictionary:
	if value.is_empty(): return {"error":"", "texture":null}
	if value.has("path"):
		if existing and _changed_textures.has(existing.get_instance_id()) and _changed_textures[existing.get_instance_id()].get_ref() == existing: fresh = true
		if not fresh and existing and existing.resource_path == value.path: return {"error":"", "texture":existing}
		if not ResourceLoader.exists(value.path): return {"error":"Missing visual texture: " + value.path}
		var resource := ResourceLoader.load(value.path, "", ResourceLoader.CACHE_MODE_IGNORE) if fresh else ResourceLoader.load(value.path)
		if not resource is Texture2D: return {"error":"Visual texture is not a Texture2D: " + value.path}
		if not fresh and _changed_textures.has(resource.get_instance_id()) and _changed_textures[resource.get_instance_id()].get_ref() == resource:
			resource = ResourceLoader.load(value.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if not resource is Texture2D: return {"error":"Cannot refresh visual texture: " + value.path}
		if fresh and ResourceLoader.has_cached(value.path):
			var cached: Resource = ResourceLoader.load(value.path)
			if cached is Texture2D and not _same_texture(cached, resource): _changed_textures[cached.get_instance_id()] = weakref(cached)
		if fresh and existing:
			if _same_texture(existing, resource): return {"error":"", "texture":existing}
			_changed_textures[existing.get_instance_id()] = weakref(existing)
		return {"error":"", "texture":resource}
	var data: Dictionary = value.image
	if existing:
		var image := existing.get_image()
		var format: int = {1:Image.FORMAT_L8, 3:Image.FORMAT_RGB8, 4:Image.FORMAT_RGBA8}.get(int(data.get("channels", 0)), -1)
		if image and image.get_format() == format and image.get_width() == data.get("width", 0) and image.get_height() == data.get("height", 0) and image.get_data() == data.get("pixels", PackedByteArray()): return {"error":"", "texture":existing}
	var created := texture(data)
	return {"error":"" if created else "Cannot create visual texture", "texture":created}

static func _material_matches(material: Material, fields: Dictionary, target_texture: Texture2D) -> bool:
	if not material is StandardMaterial3D: return false
	var repeat: Vector2 = fields.repeat
	return material.albedo_color == fields.color and material.albedo_texture == target_texture and material.uv1_scale == Vector3(repeat.x, repeat.y, 1) and material.transparency == (BaseMaterial3D.TRANSPARENCY_ALPHA if fields.alpha else BaseMaterial3D.TRANSPARENCY_DISABLED) and is_equal_approx(material.roughness, .85)

static func prepare_update(instance: MeshInstance3D, geom: Dictionary, fresh_paths: Dictionary = {}) -> Dictionary:
	var descriptor := describe(geom)
	var state: Dictionary = _track(instance) if instance else {"descriptor":{}, "owned_material":0}
	var previous: Dictionary = state.descriptor
	var same_shape: bool = previous.get("shape", {}) == descriptor.shape
	var fresh_mesh: bool = fresh_paths.has(geom.get("mesh_path", ""))
	var mesh_changed: bool = fresh_mesh or not instance or not instance.mesh or not same_shape or not _trusted_mesh(instance, state, geom, descriptor.shape)
	var requires_validation := mesh_changed
	var mesh: Mesh
	if mesh_changed:
		if instance and not descriptor.shape.has("mesh_path") and _mesh_matches(instance.mesh, descriptor.shape): mesh = instance.mesh
		elif geom.has("mesh_path"):
			if not ResourceLoader.exists(geom.mesh_path): return {"error":"Missing visual mesh: " + str(geom.mesh_path)}
			if same_shape and instance and instance.mesh and state.get("mesh") and state.mesh.get_ref() == instance.mesh:
				_changed_meshes[instance.mesh.get_instance_id()] = weakref(instance.mesh)
			# A known live replacement/mutation must not read the same corrupted
			# shared Resource back from cache. This local data load neither replaces
			# the global cache nor qualifies on-disk artifacts for compiler reuse.
			var resource := ResourceLoader.load(geom.mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE) if fresh_mesh or (instance and instance.mesh) else ResourceLoader.load(geom.mesh_path)
			# A different view can still retain the changed Resource in the normal
			# loader cache. Bypass that known live object for a newly created view.
			if resource is Mesh and _changed_meshes.has(resource.get_instance_id()) and _changed_meshes[resource.get_instance_id()].get_ref() == resource:
				resource = ResourceLoader.load(geom.mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if not resource is Mesh: return {"error":"Visual resource is not a Mesh: " + str(geom.mesh_path)}
			if fresh_mesh and ResourceLoader.has_cached(geom.mesh_path):
				var cached: Resource = ResourceLoader.load(geom.mesh_path)
				if cached is Mesh and not _same_mesh(cached, resource): _changed_meshes[cached.get_instance_id()] = weakref(cached)
			mesh = resource
		else:
			var size: Vector3 = geom.get("source_size", geom.size)
			mesh = _create_mesh(geom, size)
			if mesh and descriptor.shape.projected: mesh = _project_texture(mesh, geom, size)
		if not mesh: return {"error":"Cannot create visual geometry: " + str(geom.get("name", "geometry"))}
		if instance and instance.mesh and _same_mesh(instance.mesh, mesh):
			_changed_meshes.erase(instance.mesh.get_instance_id())
			mesh = instance.mesh
		mesh_changed = not instance or instance.mesh != mesh
	# Compare actual owned fields even when the remembered descriptor is equal:
	# callers can replace or mutate material_override after the last application.
	var prepared_texture := _prepare_texture(descriptor.material.texture, _current_texture(instance), fresh_paths.has(geom.get("texture_path", "")))
	if not prepared_texture.error.is_empty(): return prepared_texture
	var target_texture: Texture2D = prepared_texture.texture
	var material_changed: bool = not instance or not _material_matches(instance.material_override, descriptor.material, target_texture)
	requires_validation = requires_validation or material_changed or previous.get("material", {}) != descriptor.material
	var material: StandardMaterial3D
	if material_changed:
		var private_owned := instance and _private_material(instance, state)
		if private_owned and instance.material_override is StandardMaterial3D:
			material = instance.material_override
		elif instance and instance.material_override is StandardMaterial3D:
			material = instance.material_override.duplicate()
		else: material = StandardMaterial3D.new()
	return {"error":"", "descriptor":descriptor, "mesh_changed":mesh_changed, "mesh":mesh, "material_changed":material_changed, "material":material, "texture":target_texture, "requires_validation":requires_validation}

static func apply_update(instance: MeshInstance3D, prepared: Dictionary, pose: Transform3D) -> bool:
	var changed := false
	if prepared.mesh_changed:
		instance.mesh = prepared.mesh; changed = true
	if not instance.transform.is_equal_approx(pose):
		instance.transform = pose; changed = true
	var state := _track(instance)
	if prepared.material_changed:
		var fields: Dictionary = prepared.descriptor.material
		var material: StandardMaterial3D = prepared.material
		material.albedo_color = fields.color
		material.albedo_texture = prepared.texture
		var repeat: Vector2 = fields.repeat
		material.uv1_scale = Vector3(repeat.x, repeat.y, 1)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fields.alpha else BaseMaterial3D.TRANSPARENCY_DISABLED
		material.roughness = .85
		if instance.material_override != material: instance.material_override = material
		state.owned_material = material.get_instance_id()
		changed = true
	elif instance.material_override and state.owned_material != instance.material_override.get_instance_id():
		state.owned_material = 0
	state.descriptor = prepared.descriptor.duplicate(true)
	_observe_mesh(instance, state)
	return changed

static func create(geom: Dictionary) -> MeshInstance3D:
	var prepared := prepare_update(null, geom)
	if not prepared.error.is_empty(): return null
	var instance := MeshInstance3D.new()
	var pose: Transform3D = geom.transform
	if int(geom.type) == 4: pose.basis = pose.basis.orthonormalized() * Basis.from_scale(shape_scale(geom))
	apply_update(instance, prepared, pose)
	return instance

static func texture(data: Dictionary) -> ImageTexture:
	var channels: int = int(data.get("channels", 0))
	var format: int = {1:Image.FORMAT_L8, 3:Image.FORMAT_RGB8, 4:Image.FORMAT_RGBA8}.get(channels, -1)
	var width: int = int(data.get("width", 0)); var height: int = int(data.get("height", 0))
	var pixels: PackedByteArray = data.get("pixels", PackedByteArray())
	if format < 0 or width <= 0 or height <= 0 or pixels.size() != width * height * channels: return null
	var image := Image.create_from_data(width, height, false, format, pixels)
	return ImageTexture.create_from_image(image)

static func _project_texture(source: Mesh, geom: Dictionary, size: Vector3) -> Mesh:
	if geom.has("uvs"): return source
	var arrays: Array = source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs := PackedVector2Array()
	var extent := Vector2(size.x, size.y if geom.type in [0, 1, 4, 6] else size.x)
	if geom.get("texture_uniform", false): extent = Vector2.ONE
	for vertex in vertices:
		if geom.type == 4: vertex *= Vector3(size.x, size.z, size.y)
		uvs.append(Vector2(vertex.x / maxf(extent.x, .000001), -vertex.z / maxf(extent.y, .000001)) * .5 + Vector2(.5, .5))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

static func _create_mesh(geom: Dictionary, size: Vector3) -> Mesh:
	match int(geom.type):
		0:
			var mesh := PlaneMesh.new(); mesh.size = Vector2(maxf(2 * size.x, 10), maxf(2 * size.y, 10)); return mesh
		2:
			var mesh := SphereMesh.new(); mesh.radius = size.x; mesh.height = 2 * size.x; return mesh
		3:
			var mesh := CapsuleMesh.new(); mesh.radius = size.x; mesh.height = 2 * (size.x + size.y); return mesh
		4:
			var mesh := SphereMesh.new(); mesh.radius = 1; mesh.height = 2; return mesh
		5:
			var mesh := CylinderMesh.new(); mesh.top_radius = size.x; mesh.bottom_radius = size.x; mesh.height = 2 * size.y; return mesh
		6:
			var mesh := BoxMesh.new(); mesh.size = Vector3(size.x, size.z, size.y) * 2; return mesh
		1, 7, 8:
			var mesh := ArrayMesh.new()
			var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = geom.vertices
			arrays[Mesh.ARRAY_NORMAL] = geom.normals
			if geom.has("uvs"): arrays[Mesh.ARRAY_TEX_UV] = geom.uvs
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			return mesh
	return null
