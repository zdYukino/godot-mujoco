@tool
extends HBoxContainer
const Guard = preload("map_target_guard.gd")
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Preview = preload("res://addons/godot_mujoco/map/collision_preview.gd")
const Overlay = preload("res://addons/godot_mujoco/model/collision_overlay.gd")
const Visual = preload("res://addons/godot_mujoco/model/model_visual.gd")
const META := "mujoco_render_modes"
var plugin: EditorPlugin
var entities := true
var collisions := false
var menu: MenuButton
var overlay_root: Node3D
var hidden_visuals: Array[MeshInstance3D] = []
var signature := ""
var tick := 0.0
func _ready() -> void:
	menu=MenuButton.new(); menu.text="MuJoCo 显示"; add_child(menu)
	menu.tooltip_text="显示实体 / 显示碰撞网格独立勾选；橙色碰撞线框、青色选择框。仅编辑可视化，不改变物理或保存显隐。"
	menu.get_popup().add_check_item("显示实体",0)
	menu.get_popup().add_check_item("显示碰撞网格",1)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("橙色碰撞边界 · 青色选择框",2); menu.get_popup().set_item_disabled(3,true)
	var saved: Dictionary=EditorInterface.get_base_control().get_meta(META,{"entities":true,"collisions":false})
	entities=saved.entities; collisions=saved.collisions
	menu.get_popup().id_pressed.connect(func(id):
		if id==0: set_modes(not entities,collisions)
		elif id==1: set_modes(entities,not collisions))
	overlay_root=plugin.create_preview_root("SceneCollisionOverlay")
	apply_modes()
func set_modes(show_entities: bool,show_collisions: bool) -> void:
	entities=show_entities; collisions=show_collisions; apply_modes()

func apply_modes() -> void:
	menu.get_popup().set_item_checked(0,entities); menu.get_popup().set_item_checked(1,collisions)
	if plugin.panel:
		plugin.panel.show_visuals=entities; plugin.panel.show_collisions=collisions; plugin.panel.update_overlay_visibility()
	if plugin.map_panel:
		plugin.map_panel.show_visual=entities; plugin.map_panel.show_collision=collisions
		if plugin.map_panel.preview: plugin.map_panel.preview.visible=entities and not plugin.map_panel.scene_preview_suppressed
		if plugin.map_panel.collision_preview: plugin.map_panel.collision_preview.visible=collisions
	if overlay_root: overlay_root.visible=collisions
	EditorInterface.get_base_control().set_meta(META,{"entities":entities,"collisions":collisions})
	update_scene()
func _process(delta: float) -> void:
	tick+=delta
	if tick>=.25: tick=0; update_scene()
func restore_visuals() -> void:
	for mesh in hidden_visuals:
		if is_instance_valid(mesh): RenderingServer.instance_set_visible(mesh.get_instance(),mesh.is_visible_in_tree())
	hidden_visuals.clear()
func scene_nodes(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child in node.get_children(): scene_nodes(child,output)
func update_scene() -> void:
	restore_visuals()
	for preview in plugin.preview_roots:
		if is_instance_valid(preview) and preview.name=="TerrainDraft": preview.visible=entities
	var root:=EditorInterface.get_edited_scene_root()
	if not root:
		for child in overlay_root.get_children(): child.free()
		signature=""; return
	var nodes: Array[Node]=[]; scene_nodes(root,nodes)
	var values:=[]
	for node in nodes:
		if node is MeshInstance3D and not entities:
			RenderingServer.instance_set_visible(node.get_instance(),false); hidden_visuals.append(node)
		if node is Model: values.append([node.get_instance_id(),node.global_transform,node.model.snapshot if node.model else {}])
		elif node is CollisionShape3D: values.append([node.get_instance_id(),node.global_transform,node.shape.get_instance_id() if node.shape else 0,Guard.value_state(node.shape,{}),node.disabled])
		elif node is Terrain: values.append([node.get_instance_id(),node.global_transform,node.design.snapshot(Transform3D.IDENTITY,node.collision_layer,node.collision_mask) if node.design else {}])
		elif node.has_meta("map_specs"): values.append([node.get_instance_id(),node.global_transform,node.get("native_collisions")])
	var next:=str(hash(var_to_bytes(values)))
	if next==signature: return
	signature=next
	for child in overlay_root.get_children(): child.free()
	var unsupported:=0
	for node in nodes:
		if node is Model and node.model:
			var opened: Dictionary=node.model.open_document()
			if not opened.error.is_empty(): unsupported+=1; continue
			var overlay:=Preview.create(opened.document.collision_preview(.33,65),node.global_transform)
			unsupported+=overlay.get_meta("unsupported_preview").size(); overlay_root.add_child(overlay)
		elif node is Terrain and node.design:
			var wire:=Overlay.wireframe(node.design.mesh()); wire.transform=node.global_transform; overlay_root.add_child(wire)
		elif node is CollisionShape3D and node.shape and not node.disabled:
			var geom: Dictionary={"transform":node.global_transform,"size":Vector3.ONE,"type":-1}
			if node.shape is BoxShape3D: geom.type=6; geom.size=Vector3(node.shape.size.x,node.shape.size.z,node.shape.size.y)*.5
			elif node.shape is SphereShape3D: geom.type=2; geom.size.x=node.shape.radius
			elif node.shape is CylinderShape3D: geom.type=5; geom.size=Vector3(node.shape.radius,node.shape.height*.5,0)
			elif node.shape is CapsuleShape3D: geom.type=3; geom.size=Vector3(node.shape.radius,maxf(0,node.shape.height*.5-node.shape.radius),0)
			else: unsupported+=1; continue
			geom.preview_kind="analytic_boundary"; overlay_root.add_child(Preview.create([geom],Transform3D.IDENTITY))
		elif node.has_meta("map_specs"):
			var entries: Variant=node.get("native_collisions")
			if entries is Array:
				for entry in entries:
					var doc: RefCounted=ClassDB.instantiate("MjEditorDocument")
					if doc.restore(entry.snapshot): overlay_root.add_child(Preview.create(doc.collision_preview(.33,65),node.global_transform*entry.pose))
					else: unsupported+=1
	menu.get_popup().set_item_text(3,"未支持/不可加载：%d（请检查类型）" % unsupported if unsupported else "橙色碰撞边界 · 青色选择框")
	overlay_root.visible=collisions
func shutdown() -> void:
	restore_visuals()
	if is_instance_valid(overlay_root): overlay_root.free()
