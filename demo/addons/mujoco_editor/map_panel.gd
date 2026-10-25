@tool
extends VBoxContainer
const SESSION_META := "mujoco_map_editor_session"
const FIELDS_META := "mujoco_map_editor_fields"
const Session = preload("res://addons/godot_mujoco/map/session.gd")
const Collision = preload("res://addons/godot_mujoco/map/collision.gd")
const Package = preload("res://addons/godot_mujoco/map/package.gd")
var layout_scroll: ScrollContainer
var layout_content: VBoxContainer
const Layout = preload("property_layout.gd")
var layout_note: Label
var plugin: EditorPlugin
var session = Session.new()
var world: Node3D
var preview: Node3D
var collision_preview: Node3D
var camera: Camera3D
var tree: Tree
var status: Label
var path_field: LineEdit
var unit: OptionButton
var axes: OptionButton
var slice_level: SpinBox
var configure_action: Button
var strategy: OptionButton
var friction: SpinBox
var layer: SpinBox
var mask: SpinBox
var native_contact: CheckBox
var advanced: LineEdit
var relations: LineEdit
var world_options: LineEdit
var parts: LineEdit
const TargetGuard = preload("map_target_guard.gd")
var scene_baselines := {}
var scene_map_id := 0
var scene_map_path := NodePath()
var scene_parent_id := 0
var scene_parent_pose := Transform3D.IDENTITY
var scene_local_pose := Transform3D.IDENTITY
var selected := ""
var items := {}
var center := Vector3.ZERO
var distance := 4.0
var yaw := .6
var pitch := .35
var orbit := false
var pan := false
var scene_preview_suppressed := false
var show_visual := true
var show_collision := true
var poll := 0.0
var highlights: MeshInstance3D

func button(row: Node, label: String, action: Callable) -> Button:
	var control := Button.new(); control.text = label; control.pressed.connect(action); row.add_child(control); return control

func _ready() -> void:
	var base: Node = EditorInterface.get_base_control() if plugin else self
	if base.has_meta(SESSION_META): session = base.get_meta(SESSION_META)
	base.set_meta(SESSION_META,session)
	if plugin:
		var lifetime := base.get_node_or_null("MuJoCoMapSessionLifetime")
		if not lifetime:
			lifetime=preload("session_lifetime.gd").new(); lifetime.name="MuJoCoMapSessionLifetime"; base.add_child(lifetime)
		lifetime.session=session

	custom_minimum_size = Vector2(300,180)
	layout_scroll = ScrollContainer.new(); layout_scroll.name="MapScroll"
	layout_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL; layout_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	layout_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; layout_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; layout_scroll.follow_focus=true
	add_child(layout_scroll)
	layout_content=VBoxContainer.new(); layout_content.name="MapContent"; layout_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; layout_scroll.add_child(layout_content)
	var row := VBoxContainer.new(); Layout.group(layout_content,"导入 / 独立包").add_child(row)
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
	row = VBoxContainer.new(); Layout.group(layout_content,"主视图显示 / 草稿历史",false).add_child(row)
	button(row,"聚焦全图",func(): focus(""))
	button(row,"聚焦选中",func(): focus(selected))
	button(row,"选中显隐",toggle_selected)
	slice_level = number(row,"SDF 切片高度比例",0,1,.01); slice_level.value=.33
	button(row,"更新距离切片",func(): session.view.sdf_slice=slice_level.value; session.dirty=true; rebuild())
	button(row,"撤销草稿",func(): session.history.undo(); rebuild())
	button(row,"重做草稿",func(): session.history.redo(); rebuild())
	layout_note = Label.new(); layout_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; layout_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL; layout_note.text = "碰撞：真实凸包/基础体/高度场；SDF 65×65 原生距离切片（红内/蓝外/黄零轮廓，采样近似） | 原生 3D 导航 · 左键选草稿网格 · 场景地图变换轴操作整张地图；子项仅右侧参数编辑 · 独立草稿无拖拽变换轴 | 视觉就绪 ≠ 物理验证通过 | 运行地图需显式重新运行；地形运行 Apply 使用地形面板"; layout_content.add_child(layout_note)
	tree = Tree.new(); tree.custom_minimum_size = Vector2(0,160); layout_content.add_child(tree); tree.item_selected.connect(select_tree)
	world = plugin.create_preview_root("MapDraft") if plugin else Node3D.new()
	# Logic harnesses reuse their SceneTree viewport; they never create a preview viewport.
	if not plugin: get_tree().root.add_child(world)
	camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d() if plugin else get_viewport().get_camera_3d()
	row = VBoxContainer.new(); Layout.group(layout_content,"选中对象 · 基本碰撞").add_child(row)
	strategy = OptionButton.new()
	for label in ["visual","box","sphere","capsule","cylinder","compound_boxes"]: strategy.add_item(label)
	for mode in Session.Native.MODES: strategy.add_item(mode)
	strategy.add_item("hfield（使用高度契约导入）"); strategy.set_item_disabled(strategy.item_count-1,true)
	strategy.select(9) # preferred SDF candidate, never auto-applied
	row.add_child(strategy)
	strategy.item_selected.connect(func(_index): refresh_contact_controls())
	friction = number(row,"摩擦",0,1,.01); friction.value = 1
	layer = number(row,"Layer",0,4294967295,1); layer.value = 1
	mask = number(row,"Mask",0,4294967295,1); mask.value = 1
	var basic_row := row
	row = VBoxContainer.new(); Layout.group(layout_content,"选中对象 · 高级接触 / 组合",false).add_child(row)
	parts = LineEdit.new(); parts.placeholder_text = '组合 JSON: [{"center":[0,0,0],"size":[1,1,1]}]'; parts.custom_minimum_size.x = 250; row.add_child(parts)
	native_contact = CheckBox.new(); native_contact.text="使用 MuJoCo 原生接触"; row.add_child(native_contact)
	native_contact.toggled.connect(func(_on): refresh_contact_controls())
	advanced = LineEdit.new(); advanced.placeholder_text = '原生接触 JSON: {"condim":3,"friction":[1,.005,.0001]}'; advanced.custom_minimum_size.x = 250; row.add_child(advanced)
	advanced.text_changed.connect(func(_text): refresh_contact_controls())
	configure_action=button(basic_row,"验证并应用碰撞草稿",configure)
	row = VBoxContainer.new(); Layout.group(layout_content,"全局 · 地图世界参数",false).add_child(row)
	world_options = LineEdit.new(); world_options.placeholder_text = '世界高级 JSON（空保持默认）: {"solver":"Newton","nativeccd":true}'; world_options.custom_minimum_size.x = 250; row.add_child(world_options)
	world_options.tooltip_text="MuJoCo nativeccd 是凸碰撞算法开关，不是 PhysX 连续碰撞。此组作用于整个地图。"
	button(row,"应用世界设置",func():
		var value: Variant = JSON.parse_string(world_options.text if not world_options.text.is_empty() else "{}")
		if value is Dictionary: session.configure_world(value)
		else: session.error = "世界设置必须为 JSON 对象"
		rebuild())
	row=VBoxContainer.new(); Layout.group(layout_content,"全局 · pair / exclude",false).add_child(row)
	relations=LineEdit.new(); relations.placeholder_text='地图原生节点关系 JSON: {"pairs":[{"first":"节点路径","second":"另一节点路径","condim":3}],"excludes":[]}'; relations.custom_minimum_size.x=250; row.add_child(relations)
	button(row,"应用 pair/exclude",func():
		var value: Variant=JSON.parse_string(relations.text if not relations.text.is_empty() else "{}")
		if value is Dictionary: session.configure_relations(value)
		else: session.error="关系配置必须为 JSON 对象"
		rebuild())
	refresh_contact_controls()
	status = Label.new(); status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; layout_content.add_child(status)
	layout_scroll.resized.connect(update_layout); update_layout()
	update_camera(); refresh_status(); rebuild()
	if base.has_meta(FIELDS_META):
		var saved: Dictionary = base.get_meta(FIELDS_META)
		var binding: Dictionary=saved.get("binding",{})
		for key in binding:
			if key!="preview_pose": set(key,binding[key])
		world.transform=binding.get("preview_pose",Transform3D.IDENTITY)
		rebuild()
		selected=saved.get("selected","")
		if items.has(selected): items[selected].select(0); select_tree()
		for key in ["path_field","advanced","parts","relations","world_options"]: get(key).text=saved.get(key,"")
		for key in ["unit","axes","strategy"]: get(key).select(saved.get(key,0))
		for key in ["friction","layer","mask","slice_level"]: get(key).value=saved.get(key,1)
		native_contact.set_pressed_no_signal(saved.get("native_contact",false)); refresh_contact_controls()


func number(row: Node, title: String, low: float, high: float, step: float) -> SpinBox:
	var label := Label.new(); label.text = title; row.add_child(label)
	var field := SpinBox.new(); field.min_value = low; field.max_value = high; field.step = step; row.add_child(field); return field

func browse() -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.glb,*.gltf,*.obj,*.stl ; 静态几何"]); add_child(dialog)
	dialog.file_selected.connect(func(path): path_field.text = path; dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func import_source(discard: bool) -> bool:
	if not session.import_file(path_field.text,unit.get_item_text(unit.selected),axes.get_item_text(axes.selected),discard): refresh_status(); return false
	reset_independent_preview()
	selected = ""; rebuild(); focus(""); return true

func confirm_reload() -> void:
	var dialog := ConfirmationDialog.new(); dialog.dialog_text = "明确丢弃地图本地碰撞/摩擦草稿并重新读取来源？失败保持旧地图；可先保存地图包。"; add_child(dialog)
	dialog.confirmed.connect(func(): import_source(true); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()

func clear_preview() -> void:
	if preview: preview.free(); preview = null
	if collision_preview: collision_preview.free(); collision_preview = null
	if highlights: highlights.free(); highlights = null

func rebuild() -> void:
	clear_preview()
	tree.clear(); items.clear()
	if not session.visual: refresh_status(); return
	preview = session.visual.duplicate(); world.add_child(preview); preview.visible = show_visual and not scene_preview_suppressed
	build_tree(session.visual,null)
	collision_preview = Node3D.new(); world.add_child(collision_preview); collision_preview.visible = show_collision
	for mesh in session.meshes():
		var path := str(session.visual.get_path_to(mesh)); var spec: Dictionary = session.specs.get(path,{})
		if spec.get("kind","visual") == "visual": continue
		if Session.Native.uses_native(spec):
			var native := Session.Native.build(mesh,session.visual,spec,session.world_settings)
			if native.error.is_empty():
				var geometry: Array = native.document.collision_preview(session.view.get("sdf_slice",.33),65)
				collision_preview.add_child(preload("res://addons/godot_mujoco/map/collision_preview.gd").create(geometry,native.pose))
			continue
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
	native_contact.set_pressed_no_signal(spec.get("native_contact",false))
	advanced.editable = native_contact.button_pressed or spec.get("kind","sdf") in Session.Native.MODES
	advanced.tooltip_text = "原生接触三摩擦/condim/求解参数；基础体和高度场必须显式勾选，未勾选保留旧 Godot 材质"
	for i in strategy.item_count:
		if strategy.get_item_text(i) == spec.get("kind","sdf"): strategy.select(i)
	advanced.text = JSON.stringify(spec.get("contact",{})); world_options.text = JSON.stringify(session.world_settings)
	friction.value = spec.get("friction",1); layer.value = spec.get("layer",1); mask.value = spec.get("mask",1)
	strategy.disabled=not session.visual.get_node_or_null(NodePath(selected)) is MeshInstance3D
	for terrain in session.terrains:
		if selected == terrain.name:
			strategy.select(strategy.item_count-1); strategy.disabled=true
			native_contact.set_pressed_no_signal(terrain.has("native_contact")); advanced.text=JSON.stringify(terrain.get("native_contact",{})); advanced.editable=native_contact.button_pressed
			friction.value = terrain.material.friction; layer.value = terrain.get("layer",1); mask.value = terrain.get("mask",1)
	var values := []
	for part in spec.get("parts",[]): values.append({"center":[part.center.x,part.center.y,part.center.z],"size":[part.size.x,part.size.y,part.size.z]})
	parts.text = JSON.stringify(values)
	refresh_contact_controls(); show_bounds(); refresh_status()
	if plugin and tree.has_focus(): plugin.select_preview_target(selected)

func show_bounds() -> void:
	if highlights: highlights.free(); highlights = null
	if not session.visual or not session.visual.has_node(NodePath(selected)): return
	var bounds: AABB = session.bounds(session.visual.get_node(NodePath(selected)))
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_LINES)
	for i in 8:
		for bit in [1,2,4]:
			if (i & bit) == 0: surface.add_vertex(bounds.get_endpoint(i)); surface.add_vertex(bounds.get_endpoint(i | bit))
	highlights = MeshInstance3D.new(); highlights.mesh = surface.commit(); var material := StandardMaterial3D.new(); material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color = Color(.2,1,.6); material.no_depth_test = true; highlights.material_override = material; world.add_child(highlights)

func configure() -> bool:
	for terrain in session.terrains:
		if selected == terrain.name:
			var contact: Variant=JSON.parse_string(advanced.text if not advanced.text.is_empty() else "{}")
			if native_contact.button_pressed and not contact is Dictionary: session.error="接触 JSON 必须为对象"; refresh_status(); return false
			var ok: bool=session.configure_terrain_native(terrain.name,contact if native_contact.button_pressed else null,{"friction":friction.value,"layer":int(layer.value),"mask":int(mask.value)})
			rebuild(); return ok
	var spec := {"kind":strategy.get_item_text(strategy.selected),"friction":friction.value,"layer":int(layer.value),"mask":int(mask.value)}
	spec.native_contact=native_contact.button_pressed
	if Session.Native.uses_native(spec):
		var contact: Variant = JSON.parse_string(advanced.text if not advanced.text.is_empty() else "{}")
		if not contact is Dictionary: session.error = "接触设置必须为 JSON 对象"; refresh_status(); return false
		spec.contact = contact
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
	if plugin: plugin.frame_preview(world.global_transform*center,distance)

func update_camera() -> void:
	# Keep package view metadata, but never mutate the editor-owned camera.
	session.view.camera = {"center":center,"distance":distance,"yaw":yaw,"pitch":pitch}

func pick(point: Vector2) -> bool:
	if not is_instance_valid(camera): camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if not camera: return false
	if not preview or not preview.visible: return false
	var origin := camera.project_ray_origin(point); var direction := camera.project_ray_normal(point); var nearest := INF; var path := ""
	for mesh in session.meshes(preview):
		if not mesh.is_visible_in_tree(): continue
		var pose := world.global_transform * Collision.pose_of(mesh,preview); var inverse := pose.affine_inverse(); var local_origin := inverse*origin; var local_direction := inverse.basis*direction
		if not mesh.mesh.get_aabb().intersects_ray(local_origin,local_direction): continue
		var faces: PackedVector3Array = mesh.mesh.get_faces()
		for i in range(0,faces.size(),3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
			if hit != null:
				var length: float = origin.distance_to(pose*hit)
				if length < nearest: nearest = length; path = str(preview.get_path_to(mesh))
	if items.has(path):
		items[path].select(0); tree.scroll_to_item(items[path]); select_tree()
		if plugin: plugin.select_preview_target(selected)
		return true
	return false

func refresh_status() -> void:
	if not status: return
	refresh_contact_controls()
	var state: Dictionary = session.watch.inspect(session.dirty)
	status.text = str(session.last_collision_attempt) + "\n" + state.state + " | " + session.error + " | " + "; ".join(session.diagnostics)
	if session.visual:
		var meshes: Array = session.meshes(); var triangles := 0; var materials := 0
		for mesh in meshes:
			triangles += mesh.mesh.get_faces().size()/3
			for i in mesh.mesh.get_surface_count():
				if mesh.get_active_material(i): materials += 1
		var bounds: AABB = session.bounds(session.visual.get_node(NodePath(selected)) if session.visual.has_node(NodePath(selected)) else session.visual)
		status.text += "\n选中节点路径: " + selected
		status.text += "\n网格 %d / 三角形 %d / 材质 %d | 尺寸 m: %s | 源单位: %s | 碰撞配置 %d；物理验证待独立运行" % [meshes.size(),triangles,materials,str(bounds.size),session.unit,session.specs.size()]
		if session.specs.has(selected): status.text += "\nrequested/actual: " + str(session.specs[selected].get("capability",{}))
		if session.specs.has(selected) and session.visual.has_node(NodePath(selected)) and not Session.Native.uses_native(session.specs[selected]):
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
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_RESOURCES; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.json ; 地图 manifest"]); add_child(dialog)
	dialog.file_selected.connect(func(path): open_package(path.get_base_dir()); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func open_package(path: String) -> bool:
	if session.dirty: session.error = "先保存或明确重导入丢弃本地草稿"; refresh_status(); return false
	var error := Package.validate(path)
	if not error.is_empty(): session.error = error; refresh_status(); return false
	var scene := ResourceLoader.load(path.path_join("map.tscn"),"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not scene: session.error = "地图场景资源加载失败"; refresh_status(); return false
	var node := scene.instantiate()
	if not node: session.error = "地图场景实例化失败"; refresh_status(); return false
	var visual := node.get_node_or_null("Visual")
	if not visual is Node3D or not node.get_node_or_null("Physics") is Node3D:
		node.free(); session.error = "地图结构缺少 Visual/Physics"; refresh_status(); return false
	for key in ["map_specs","map_view","source_hashes","contract"]:
		if not node.get_meta(key,null) is Dictionary:
			node.free(); session.error = "地图元数据缺失或类型错误: " + key; refresh_status(); return false
	if not node.get_meta("map_terrains",[]) is Array or not node.get_meta("diagnostics",[]) is Array:
		node.free(); session.error = "地图地形/诊断元数据类型错误"; refresh_status(); return false
	for design in node.get_meta("map_terrains",[]):
		if not design is Dictionary or not design.get("name") is String or not design.get("grid") is MjHeightFieldData or not design.get("pose") is Transform3D or not design.get("material") is PhysicsMaterial:
			node.free(); session.error = "地图地形元数据不完整"; refresh_status(); return false
	for key in ["map_world_settings","map_contact_relations"]:
		if not node.get_meta(key,{}) is Dictionary: node.free(); session.error="地图元数据类型错误: "+key; refresh_status(); return false
	var view: Dictionary = node.get_meta("map_view",{})
	var saved_view: Variant = view.get("camera",{})
	if not saved_view is Dictionary or not saved_view.get("center",Vector3.ZERO) is Vector3:
		node.free(); session.error = "地图相机设置无效"; refresh_status(); return false
	for key in ["distance","yaw","pitch"]:
		var value: Variant = saved_view.get(key,4.0 if key=="distance" else .3)
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value) or (key=="distance" and value<=0):
			node.free(); session.error = "地图相机参数无效: " + key; refresh_status(); return false
	var contract_check: Dictionary = node.get_meta("contract")
	if contract_check.get("unit") not in ["m","cm","mm"] or contract_check.get("axes") not in ["Y_UP","Z_UP"] or not contract_check.get("source","") is String:
		node.free(); session.error = "地图来源/单位契约无效"; refresh_status(); return false
	if not view.get("hidden",[]) is Array:
		node.free(); session.error = "地图显隐设置无效"; refresh_status(); return false
	for hidden in view.get("hidden",[]):
		if not hidden is String:
			node.free(); session.error = "地图显隐节点路径无效"; refresh_status(); return false
	node.remove_child(visual)
	session.contact_relations=node.get_meta("map_contact_relations",{}); session.world_settings = node.get_meta("map_world_settings",{}); session.close(); session.history = UndoRedo.new(); session.terrains = node.get_meta("map_terrains",[]); session.visual = visual; session.specs = node.get_meta("map_specs",{}); session.view = node.get_meta("map_view",{}); session.watch.hashes = node.get_meta("source_hashes",{}); session.diagnostics = node.get_meta("diagnostics",[])
	var contract: Dictionary = node.get_meta("contract",{}); session.unit = contract.get("unit", ""); session.axes = contract.get("axes", ""); session.source = contract.get("source", ""); session.watch.source = session.source
	restore_terrain_meshes()
	node.free(); selected = ""; session.dirty = false; session.error = "已打开独立包；原来源缺失只影响重导入"
	var saved: Dictionary = session.view.get("camera",{})
	center = saved.get("center",Vector3.ZERO); distance = saved.get("distance",4.0); yaw = saved.get("yaw",.6); pitch = saved.get("pitch",.35)
	slice_level.value=session.view.get("sdf_slice",.33); relations.text=JSON.stringify(session.contact_relations); world_options.text=JSON.stringify(session.world_settings)
	reset_independent_preview()
	rebuild(); update_camera(); return true

func apply_scene() -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if not root or not root is Node3D: session.error = "先打开一个 Node3D 编辑场景"; refresh_status(); return false
	if not root.global_transform.is_finite() or not root.global_basis.is_equal_approx(root.global_basis.orthonormalized()) or root.global_basis.determinant() < 0:
		session.error = "地图父场景必须为无缩放/镜像/剪切的刚性变换"; refresh_status(); return false
	var old: Node = root.get_node_or_null(scene_map_path if not scene_map_path.is_empty() else NodePath("StaticMap"))
	if not scene_map_path.is_empty() and not old:
		session.error="原场景地图已移除；请重新载入地图，当前草稿保留"; refresh_status(); return false
	if old and (not old is Node3D or not old.has_meta("map_specs")):
		session.error = "场景目标已有非地图同名对象"; refresh_status(); return false
	if old==root:
		session.error="不能替换编辑场景根；请把地图放在 Node3D 宿主下再 Apply"; refresh_status(); return false
	if not scene_map_path.is_empty() and (not scene_baselines.has(old.get_instance_id()) or scene_baselines[old.get_instance_id()]!=TargetGuard.fingerprint(old)):
		session.error="场景地图身份或配置已被外部修改；当前草稿保留，请保存后重新载入目标"; refresh_status(); return false
	var parent: Node3D = old.get_parent() if old else root
	var pose: Transform3D = old.transform if old else Transform3D.IDENTITY
	if not scene_map_path.is_empty() and (parent.get_instance_id()!=scene_parent_id or not parent.global_transform.is_equal_approx(scene_parent_pose) or not old.transform.is_equal_approx(scene_local_pose)):
		session.error="地图或父节点的变换已在场景中变化；请保存草稿并重新载入目标后 Apply"; refresh_status(); return false
	if not parent.global_transform.is_finite() or not parent.global_basis.is_equal_approx(parent.global_basis.orthonormalized()) or parent.global_basis.determinant()<0 or not pose.is_finite() or not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant()<0:
		session.error="地图与父节点必须为无缩放/镜像/剪切的刚性变换"; refresh_status(); return false
	var built: Dictionary = session.build_scene()
	if not built.error.is_empty(): session.error = built.error; refresh_status(); return false
	var map: Node3D = built.scene
	map.transform=pose
	if old: map.name=old.name
	if old: scene_baselines[old.get_instance_id()]=TargetGuard.fingerprint(old)
	var undo := plugin.get_undo_redo(); undo.create_action("Apply 静态地图设计",UndoRedo.MERGE_DISABLE,root)
	if old: undo.add_do_method(parent,"remove_child",old); undo.add_undo_reference(old)
	undo.add_do_method(parent,"add_child",map,true); undo.add_do_method(session,"own_scene",map,root); undo.add_do_reference(map); undo.add_undo_method(parent,"remove_child",map)
	if old:
		undo.add_undo_method(parent,"add_child",old)
		undo.add_undo_method(session,"own_scene",old,root)
	undo.commit_action()
	scene_baselines[map.get_instance_id()]=TargetGuard.fingerprint(map)
	clear_preview(); scene_preview_suppressed=true; scene_map_id=map.get_instance_id()
	scene_map_path=root.get_path_to(map); world.global_transform=map.global_transform
	scene_parent_id=parent.get_instance_id(); scene_parent_pose=parent.global_transform; scene_local_pose=map.transform
	session.error = "地图设计已 Apply；场景 Undo/Redo 可用，运行实例需显式重启。地形运行修改可用地形面板事务 Apply。"; refresh_status(); return true

func own_scene(node: Node, root: Node) -> void:
	session.own_scene(node,root)

func browse_height() -> void:
	var dialog := FileDialog.new(); dialog.access = FileDialog.ACCESS_FILESYSTEM; dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE; dialog.filters = PackedStringArray(["*.json ; 高度契约 JSON（含 file）"]); add_child(dialog)
	dialog.file_selected.connect(func(path):
		var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not contract is Dictionary or not contract.get("file") is String: session.error = "高度契约 JSON 必须含 file"
		else: session.import_height(path.get_base_dir().path_join(contract.file),contract,path)
		rebuild(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.7)

func sync_bound_preview_pose() -> void:
	if not plugin or scene_map_path.is_empty() or not is_instance_valid(world): return
	var root:=EditorInterface.get_edited_scene_root()
	var target: Node=root.get_node_or_null(scene_map_path) if root else null
	# Follow only this draft's known authored identities (including own Undo/Redo).
	# This is a render pose, not acceptance of external edits: keep the captured
	# parent/local poses and content baselines unchanged for Apply conflict checks.
	if target is Node3D and scene_baselines.has(target.get_instance_id()):
		world.global_transform=target.global_transform

func _process(delta: float) -> void:
	sync_bound_preview_pose()
	poll += delta
	if poll >= 2: poll = 0; refresh_status()

func shutdown() -> void:
	var saved := {"selected":selected,"native_contact":native_contact.button_pressed,"binding":{}}
	for key in ["scene_baselines","scene_map_id","scene_map_path","scene_parent_id","scene_parent_pose","scene_local_pose","scene_preview_suppressed","show_visual","show_collision"]: saved.binding[key]=get(key)
	saved.binding["preview_pose"]=world.transform
	for key in ["path_field","advanced","parts","relations","world_options"]: saved[key]=get(key).text
	for key in ["unit","axes","strategy"]: saved[key]=get(key).selected
	for key in ["friction","layer","mask","slice_level"]: saved[key]=get(key).value
	if plugin: EditorInterface.get_base_control().set_meta(FIELDS_META,saved)
	else: session.close()
	if is_instance_valid(world): world.free()


func refresh_contact_controls() -> void:
	var kind:=strategy.get_item_text(strategy.selected)
	var capable := session.visual != null and session.visual.get_node_or_null(NodePath(selected)) is MeshInstance3D
	parts.editable=capable and kind=="compound_boxes"
	configure_action.disabled=not capable
	configure_action.tooltip_text="请选择地图网格或高度场" if not capable else "验证后显式写入草稿；场景与 runtime 不自动应用"
	var parser := JSON.new()
	var contact: Variant=parser.data if parser.parse(advanced.text)==OK else null
	var native_enabled:=native_contact.button_pressed or kind in Session.Native.MODES
	var friction_override: bool=native_enabled and contact is Dictionary and contact.has("friction")
	friction.editable=capable and kind!="visual" and not friction_override
	friction.tooltip_text="高级接触 JSON 的三摩擦值覆盖此基本值，请在高级分组编辑" if friction_override else "基本滑动摩擦；高级接触 friction 可覆盖"
	layer.editable=capable and kind!="visual"; mask.editable=capable and kind!="visual"
	var unsupported:=not capable or (not strategy.disabled and kind in ["compound_boxes","visual"])
	native_contact.disabled=unsupported
	native_contact.tooltip_text="compound_boxes 仅支持原有 Godot 组合路径，尚未接入原生接触 JSON；visual 不生成碰撞" if unsupported else "显式使用 MuJoCo 接触，保留未选用时的 Godot 材质语义"

	if not capable: native_contact.tooltip_text="请选择地图网格或高度场；全局参数在单独分组编辑"
	advanced.editable=not unsupported and (native_contact.button_pressed or kind in Session.Native.MODES)

# A right dock never requests the old preview width.
func update_layout() -> void:
	custom_minimum_size.x = 0

# An explicit Inspector action loads an independent draft. Selection alone never
# replaces dirty work, and Apply still goes through the existing scene history.
func open_scene_map(node: Node3D) -> bool:
	if session.dirty:
		session.error="先保存独立地图包，再载入其他场景地图；当前草稿已保留"; refresh_status(); return false
	var visual := node.get_node_or_null("Visual") as Node3D
	if not visual or not node.has_meta("map_specs") or not node.has_meta("contract"):
		session.error="场景节点不是已 Apply 的静态地图"; refresh_status(); return false
	for key in ["map_specs","contract","map_world_settings","map_contact_relations","map_view","source_hashes"]:
		if not node.get_meta(key,{}) is Dictionary:
			session.error="场景地图元数据无效: "+key; refresh_status(); return false
	if not node.get_meta("map_terrains",[]) is Array or not node.get_meta("diagnostics",[]) is Array:
		session.error="场景地图地形 / 诊断元数据无效"; refresh_status(); return false
	var edited := EditorInterface.get_edited_scene_root()
	if not edited or (node!=edited and not edited.is_ancestor_of(node)):
		session.error="地图必须属于当前编辑场景"; refresh_status(); return false
	for design in node.get_meta("map_terrains",[]):
		if not design is Dictionary or not design.get("name") is String or not design.get("grid") is MjHeightFieldData or not design.get("pose") is Transform3D or not design.get("material") is PhysicsMaterial:
			session.error="场景地图地形元数据不完整"; refresh_status(); return false
	var copy := visual.duplicate() as Node3D
	session.close(); session.history=UndoRedo.new(); session.visual=copy
	session.specs=node.get_meta("map_specs").duplicate(true)
	session.terrains=node.get_meta("map_terrains",[]).duplicate(true)
	restore_terrain_meshes()
	session.world_settings=node.get_meta("map_world_settings",{}).duplicate(true)
	session.contact_relations=node.get_meta("map_contact_relations",{}).duplicate(true)
	session.view=node.get_meta("map_view",{}).duplicate(true)
	session.watch.hashes=node.get_meta("source_hashes",{}).duplicate(true)
	var contract: Dictionary=node.get_meta("contract")
	session.source=contract.get("source",""); session.watch.source=session.source
	session.unit=contract.get("unit","m"); session.axes=contract.get("axes","Y_UP")
	session.diagnostics=node.get_meta("diagnostics",[]).duplicate()
	session.dirty=false; session.error="已载入场景地图为独立草稿；保存包 / Apply 均需明确操作"
	scene_baselines={node.get_instance_id():TargetGuard.fingerprint(node)}
	scene_map_id=node.get_instance_id(); scene_map_path=EditorInterface.get_edited_scene_root().get_path_to(node); world.global_transform=node.global_transform
	scene_parent_id=node.get_parent().get_instance_id(); scene_parent_pose=node.get_parent().global_transform if node.get_parent() is Node3D else Transform3D.IDENTITY; scene_local_pose=node.transform
	scene_preview_suppressed=true # The scene already draws the authored visual in this same viewport.
	selected=""; world_options.text=JSON.stringify(session.world_settings); relations.text=JSON.stringify(session.contact_relations)
	rebuild(); return true

func toggle_visual_preview() -> void:
	if scene_preview_suppressed or not preview:
		scene_preview_suppressed=false; show_visual=true; rebuild()
	else:
		show_visual=not show_visual; preview.visible=show_visual

func toggle_collision_preview() -> void:
	if not collision_preview:
		show_collision=true; rebuild()
	else: show_collision=not show_collision
	if collision_preview: collision_preview.visible=show_collision

func reset_independent_preview() -> void:
	# Apply hides the draft while the authored scene supplies the visual. That
	# display mode belongs to that scene target, not the next imported document.
	scene_baselines.clear()
	scene_map_id=0; scene_map_path=NodePath(); scene_parent_id=0; world.transform=Transform3D.IDENTITY
	scene_preview_suppressed=false

func restore_terrain_meshes() -> void:
	for design in session.terrains:
		if session.visual.has_node(NodePath(design.name)): continue
		var mesh := MeshInstance3D.new(); mesh.name = design.name; mesh.mesh = design.grid.mesh(); mesh.transform = design.pose; session.visual.add_child(mesh); mesh.owner = session.visual
