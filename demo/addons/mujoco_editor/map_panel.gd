@tool
extends VBoxContainer
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Collision = preload("res://addons/godot_mujoco/map/collision.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var plugin: EditorPlugin
var session = Session.new()
var viewport: SubViewport
var world: Node3D
var preview: Node3D
var collision_preview: Node3D
var camera: Camera3D
var tree: Tree
var status: Label
var path_field: LineEdit
var unit: OptionButton
var axes: OptionButton
var strategy: OptionButton
var friction: SpinBox
var layer: SpinBox
var mask: SpinBox
var parts: LineEdit
var selected := ""
var items := {}
var center := Vector3.ZERO
var distance := 4.0
var yaw := .6
var pitch := .35
var orbit := false
var pan := false
var show_visual := true
var show_collision := true
var poll := 0.0
var highlights: MeshInstance3D

func button(row: Node, label: String, action: Callable) -> void:
	var control := Button.new(); control.text = label; control.pressed.connect(action); row.add_child(control)

func _ready() -> void:
	custom_minimum_size = Vector2(600,440)
	var row := HFlowContainer.new(); add_child(row)
	path_field = LineEdit.new(); path_field.placeholder_text = "静态地图源文件路径"; path_field.custom_minimum_size.x = 250; row.add_child(path_field)
	button(row,"浏览",browse)
	unit = OptionButton.new()
	for label in ["选择单位", "m", "cm", "mm"]: unit.add_item(label)
	row.add_child(unit)
	axes = OptionButton.new()
	for label in ["Y_UP", "Z_UP"]: axes.add_item(label)
	row.add_child(axes)
	button(row,"导入（保留脏数据）",func(): import_source(false))
	button(row,"明确丢弃并重导入",confirm_reload)
	button(row,"打开地图包",browse_package)
	button(row,"保存独立地图包",save_package)
	button(row,"Apply 到编辑场景",apply_scene)
	button(row,"导入高度契约",browse_height)
	row = HFlowContainer.new(); add_child(row)
	button(row,"聚焦全图",func(): focus(""))
	button(row,"聚焦选中",func(): focus(selected))
	button(row,"选中显隐",toggle_selected)
	button(row,"视觉显隐",func(): show_visual = not show_visual; if preview: preview.visible = show_visual)
	button(row,"碰撞线框",func(): show_collision = not show_collision; if collision_preview: collision_preview.visible = show_collision)
	button(row,"撤销草稿",func(): session.history.undo(); rebuild())
	button(row,"重做草稿",func(): session.history.redo(); rebuild())
	var note := Label.new(); note.text = "右键轨道 · 中键平移 · 滚轮缩放 · 左键精确选面 | 视觉就绪 ≠ 物理验证通过 | 运行地图需显式重新运行；地形运行 Apply 使用地形面板"; add_child(note)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; add_child(split)
	tree = Tree.new(); tree.custom_minimum_size.x = 230; tree.hide_root = false; split.add_child(tree); tree.item_selected.connect(select_tree)
	var container := SubViewportContainer.new(); container.stretch = true; container.size_flags_horizontal = Control.SIZE_EXPAND_FILL; container.size_flags_vertical = Control.SIZE_EXPAND_FILL; container.custom_minimum_size = Vector2(400,260); split.add_child(container)
	viewport = SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(600,320); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(viewport)
	world = Node3D.new(); viewport.add_child(world)
	camera = Camera3D.new(); camera.current = true; world.add_child(camera)
	var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-45,-25,0); world.add_child(light)
	var env := WorldEnvironment.new(); env.environment = Environment.new(); env.environment.background_mode = Environment.BG_COLOR; env.environment.background_color = Color(.08,.10,.13); env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color = Color.WHITE; env.environment.ambient_light_energy = .5; world.add_child(env)
	container.gui_input.connect(input_view)
	row = HFlowContainer.new(); add_child(row)
	strategy = OptionButton.new()
	for label in ["visual","box","sphere","capsule","cylinder","compound_boxes"]: strategy.add_item(label)
	strategy.add_item("SDF（原生探针通过，编辑器尚未接入）"); strategy.set_item_disabled(strategy.item_count-1,true)
	row.add_child(strategy)
	friction = number(row,"摩擦",0,1,.01); friction.value = 1
	layer = number(row,"Layer",0,4294967295,1); layer.value = 1
	mask = number(row,"Mask",0,4294967295,1); mask.value = 1
	parts = LineEdit.new(); parts.placeholder_text = '组合 JSON: [{"center":[0,0,0],"size":[1,1,1]}]'; parts.custom_minimum_size.x = 290; row.add_child(parts)
	button(row,"验证并应用碰撞草稿",configure)
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status)
	update_camera(); refresh_status()

func number(row: Node, title: String, low: float, high: float, step: float) -> SpinBox:
	var label := Label.new(); label.text = title; row.add_child(label)
	var field := SpinBox.new(); field.min_value = low; field.max_value = high; field.step = step; row.add_child(field); return field

func browse() -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.glb,*.gltf,*.obj,*.stl ; 静态几何"]); add_child(dialog)
	dialog.file_selected.connect(func(path): path_field.text = path; dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func import_source(discard: bool) -> bool:
	if not session.import_file(path_field.text,unit.get_item_text(unit.selected),axes.get_item_text(axes.selected),discard): refresh_status(); return false
	selected = ""; rebuild(); focus(""); return true

func confirm_reload() -> void:
	var dialog := ConfirmationDialog.new(); dialog.dialog_text = "明确丢弃地图本地碰撞/摩擦草稿并重新读取来源？失败保持旧地图；可先保存地图包。"; add_child(dialog)
	dialog.confirmed.connect(func(): import_source(true); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()

func rebuild() -> void:
	if preview: preview.free(); preview = null
	if collision_preview: collision_preview.free(); collision_preview = null
	if highlights: highlights.free(); highlights = null
	tree.clear(); items.clear()
	if not session.visual: refresh_status(); return
	preview = session.visual.duplicate(); world.add_child(preview); preview.visible = show_visual
	build_tree(session.visual,null)
	collision_preview = Node3D.new(); world.add_child(collision_preview); collision_preview.visible = show_collision
	for mesh in session.meshes():
		var path := str(session.visual.get_path_to(mesh)); var spec: Dictionary = session.specs.get(path,{})
		if spec.get("kind","visual") == "visual": continue
		var result := Collision.build(mesh,session.visual,spec)
		if result.error.is_empty(): collision_preview.add_child(Collision.wireframe(result.body)); result.body.free()
	for terrain in session.terrains:
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
		var faces: PackedVector3Array = terrain.grid.mesh().get_faces()
		for i in range(0,faces.size(),3):
			for edge in [[0,1],[1,2],[2,0]]: surface.add_vertex(faces[i+edge[0]]); surface.add_vertex(faces[i+edge[1]])
		var wire := MeshInstance3D.new(); wire.mesh = surface.commit(); wire.transform = terrain.pose
		var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.no_depth_test = true; material.albedo_color = Color(1,.65,.05); wire.material_override = material; collision_preview.add_child(wire)
	for path in session.view.get("hidden",[]):
		if preview.has_node(NodePath(path)): preview.get_node(NodePath(path)).hide()
	if items.has(selected): items[selected].select(0)
	refresh_status()

func build_tree(node: Node, parent: TreeItem) -> void:
	var item := tree.create_item(parent); var path := str(session.visual.get_path_to(node)); item.set_metadata(0,path); items[path] = item
	var suffix := ""
	if node is MeshInstance3D: suffix = " [视觉 / " + session.specs.get(path,{}).get("kind","无碰撞") + "]"
	item.set_text(0,str(node.name)+suffix)
	for child in node.get_children(): build_tree(child,item)

func select_tree() -> void:
	var item := tree.get_selected()
	if not item: return
	selected = item.get_metadata(0); var spec: Dictionary = session.specs.get(selected,{})
	for i in strategy.item_count:
		if strategy.get_item_text(i) == spec.get("kind","visual"): strategy.select(i)
	friction.value = spec.get("friction",1); layer.value = spec.get("layer",1); mask.value = spec.get("mask",1)
	for terrain in session.terrains:
		if selected == terrain.name: friction.value = terrain.material.friction; layer.value = terrain.get("layer",1); mask.value = terrain.get("mask",1)
	var values := []
	for part in spec.get("parts",[]): values.append({"center":[part.center.x,part.center.y,part.center.z],"size":[part.size.x,part.size.y,part.size.z]})
	parts.text = JSON.stringify(values)
	show_bounds(); refresh_status()

func show_bounds() -> void:
	if highlights: highlights.free(); highlights = null
	if not session.visual or not session.visual.has_node(NodePath(selected)): return
	var bounds: AABB = session.bounds(session.visual.get_node(NodePath(selected)))
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
	for i in 8:
		for bit in [1,2,4]:
			if (i & bit) == 0: surface.add_vertex(bounds.get_endpoint(i)); surface.add_vertex(bounds.get_endpoint(i | bit))
	var origin := bounds.get_center(); var length := maxf(.01,bounds.size.length()*.25)
	for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
		surface.add_vertex(origin); surface.add_vertex(origin+axis*length)
	highlights = MeshInstance3D.new(); highlights.mesh = surface.commit(); var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(.2,1,.6); material.no_depth_test = true; highlights.material_override = material; world.add_child(highlights)

func configure() -> bool:
	for terrain in session.terrains:
		if selected == terrain.name:
			var ok: bool = session.configure_terrain(terrain.name,friction.value,int(layer.value),int(mask.value)); rebuild(); return ok
	var spec := {"kind":strategy.get_item_text(strategy.selected),"friction":friction.value,"layer":int(layer.value),"mask":int(mask.value)}
	if spec.kind == "compound_boxes":
		var values: Variant = JSON.parse_string(parts.text)
		if not values is Array: session.error = "组合 JSON 必须为数组"; refresh_status(); return false
		var boxes := []
		for value in values:
			if not value is Dictionary or not value.get("center") is Array or not value.get("size") is Array or value.center.size()!=3 or value.size.size()!=3: session.error = "每个组合需要三个 center/size 数值"; refresh_status(); return false
			for number_value in value.center + value.size:
				if typeof(number_value) not in [TYPE_INT,TYPE_FLOAT]: session.error = "组合数据必须为数值"; refresh_status(); return false
			boxes.append({"center":Vector3(value.center[0],value.center[1],value.center[2]),"size":Vector3(value.size[0],value.size[1],value.size[2])})
		spec.parts = boxes
	var ok: bool = session.configure(selected,spec); rebuild(); return ok

func toggle_selected() -> void:
	if not preview or not preview.has_node(NodePath(selected)): return
	var hidden: Array = session.view.get("hidden",[])
	if selected in hidden: hidden.erase(selected)
	else: hidden.append(selected)
	session.view.hidden = hidden; session.dirty = true; rebuild()

func focus(path: String) -> void:
	if not session.visual: return
	var bounds: AABB = session.bounds(session.visual.get_node(NodePath(path)) if not path.is_empty() and session.visual.has_node(NodePath(path)) else session.visual)
	center = bounds.get_center(); distance = maxf(.01,bounds.size.length()*1.5); update_camera()

func update_camera() -> void:
	camera.position = center + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.near = maxf(.00001,distance/10000); camera.far = maxf(100,distance*100)
	camera.look_at(center)
	session.view.camera = {"center":center,"distance":distance,"yaw":yaw,"pitch":pitch}

func input_view(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: orbit = event.pressed
		if event.button_index == MOUSE_BUTTON_MIDDLE: pan = event.pressed
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(.001,distance*.85)
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(1e8,distance/.85)
			if event.button_index == MOUSE_BUTTON_LEFT: pick(event.position)
	if event is InputEventMouseMotion:
		if orbit: yaw -= event.relative.x*.008; pitch = clampf(pitch+event.relative.y*.008,-1.5,1.5)
		if pan: center += (-camera.basis.x*event.relative.x+camera.basis.y*event.relative.y)*distance/500
	update_camera()

func pick(point: Vector2) -> void:
	if not preview or not show_visual: return
	var origin := camera.project_ray_origin(point); var direction := camera.project_ray_normal(point); var nearest := INF; var path := ""
	for mesh in session.meshes(preview):
		if not mesh.is_visible_in_tree(): continue
		var pose := Collision.pose_of(mesh,preview); var inverse := pose.affine_inverse(); var local_origin := inverse*origin; var local_direction := inverse.basis*direction
		if not mesh.mesh.get_aabb().intersects_ray(local_origin,local_direction): continue
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
			if hit != null:
				var length: float = origin.distance_to(pose*hit)
				if length < nearest: nearest = length; path = str(preview.get_path_to(mesh))
	if items.has(path): items[path].select(0); tree.scroll_to_item(items[path]); select_tree()

func refresh_status() -> void:
	if not status: return
	var state: Dictionary = session.watch.inspect(session.dirty)
	status.text = state.state + " | " + session.error + " | " + "; ".join(session.diagnostics)
	if session.visual:
		var meshes: Array = session.meshes(); var triangles := 0; var materials := 0
		for mesh in meshes:
			triangles += mesh.mesh.get_faces().size()/3
			for i in mesh.mesh.get_surface_count():
				if mesh.get_active_material(i): materials += 1
		var bounds: AABB = session.bounds(session.visual.get_node(NodePath(selected)) if session.visual.has_node(NodePath(selected)) else session.visual)
		status.text += "\n网格 %d / 三角形 %d / 材质 %d | 尺寸 m: %s | 源单位: %s | 碰撞配置 %d；物理验证待独立运行" % [meshes.size(),triangles,materials,str(bounds.size),session.unit,session.specs.size()]
		if session.specs.has(selected) and session.visual.has_node(NodePath(selected)):
			var result := Collision.build(session.visual.get_node(NodePath(selected)),session.visual,session.specs[selected])
			if result.error.is_empty():
				status.text += "\n碰撞顶点采样误差 m: %.6f（非 Hausdorff，不保证门洞正确；需实际测试）" % result.body.get_meta("vertex_error_m")
				result.body.free()
		if not state.changes.is_empty(): status.text += "\n源变化: " + ", ".join(state.changes)

func save_package() -> void:
	var result := Package.pack(session,"res://static_maps")
	session.error = result.error if not result.error.is_empty() else "已保存 " + result.path
	if result.error.is_empty(): EditorInterface.get_resource_filesystem().scan()
	refresh_status()

func browse_package() -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_RESOURCES; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["manifest.json ; 地图 manifest"]); add_child(dialog)
	dialog.file_selected.connect(func(path): open_package(path.get_base_dir()); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func open_package(path: String) -> bool:
	if session.dirty: session.error = "先保存或明确重导入丢弃本地草稿"; refresh_status(); return false
	var error := Package.validate(path)
	if not error.is_empty(): session.error = error; refresh_status(); return false
	var scene := ResourceLoader.load(path.path_join("map.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not scene: return false
	var node := scene.instantiate(); var visual := node.get_node("Visual"); node.remove_child(visual)
	session.close(); session.history = UndoRedo.new(); session.terrains = node.get_meta("map_terrains",[]); session.visual = visual; session.specs = node.get_meta("map_specs",{}); session.view = node.get_meta("map_view",{}); session.watch.hashes = node.get_meta("source_hashes",{}); session.diagnostics = node.get_meta("diagnostics",[])
	var contract: Dictionary = node.get_meta("contract",{}); session.unit = contract.get("unit", ""); session.axes = contract.get("axes", ""); session.source = contract.get("source", ""); session.watch.source = session.source
	for design in session.terrains:
		var mesh := MeshInstance3D.new(); mesh.name = design.name; mesh.mesh = design.grid.mesh(); mesh.transform = design.pose; session.visual.add_child(mesh); mesh.owner = session.visual
	node.free(); selected = ""; session.dirty = false; session.error = "已打开独立包；原来源缺失只影响重导入"
	var saved: Dictionary = session.view.get("camera",{})
	center = saved.get("center",Vector3.ZERO); distance = saved.get("distance",4.0); yaw = saved.get("yaw",.6); pitch = saved.get("pitch",.35)
	rebuild(); update_camera(); return true

func apply_scene() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if not root or not root is Node3D: session.error = "先打开一个 Node3D 编辑场景"; refresh_status(); return false
	if not root.global_transform.is_finite() or not root.global_basis.is_equal_approx(root.global_basis.orthonormalized()) or root.global_basis.determinant() < 0:
		session.error = "地图父场景必须为无缩放/镜像/剪切的刚性变换"; refresh_status(); return false
	var built: Dictionary = session.build_scene()
	if not built.error.is_empty(): session.error = built.error; refresh_status(); return false
	var map: Node3D = built.scene
	var old: Node = root.get_node_or_null("StaticMap")
	if old and not old.has_meta("map_specs"):
		map.free(); session.error = "场景已有非地图 StaticMap 同名对象"; refresh_status(); return false
	var undo := plugin.get_undo_redo(); undo.create_action("Apply 静态地图设计",UndoRedo.MERGE_DISABLE,root)
	if old: undo.add_do_method(root,"remove_child",old); undo.add_undo_reference(old)
	undo.add_do_method(root,"add_child",map,true); undo.add_do_method(self,"own_scene",map,root); undo.add_do_reference(map); undo.add_undo_method(root,"remove_child",map)
	if old: undo.add_undo_method(root,"add_child",old)
	undo.commit_action()
	session.error = "地图设计已 Apply；场景 Undo/Redo 可用，运行实例需显式重启。地形运行修改可用地形面板事务 Apply。"; refresh_status(); return true

func own_scene(node: Node, root: Node) -> void:
	node.owner = root
	for child in node.get_children(): own_scene(child,root)

func browse_height() -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.json ; 高度契约 JSON（含 file）"]); add_child(dialog)
	dialog.file_selected.connect(func(path):
		var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not contract is Dictionary or not contract.get("file") is String: session.error = "高度契约 JSON 必须含 file"
		else: session.import_height(path.get_base_dir().path_join(contract.file),contract)
		rebuild(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func _process(delta: float) -> void:
	poll += delta
	if poll >= 2: poll = 0; refresh_status()

func shutdown() -> void:
	session.close()
