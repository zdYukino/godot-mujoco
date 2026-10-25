@tool
extends Node
const Preview = preload("res://addons/godot_mujoco/map/collision_preview.gd")
@export_range(0.1,10.0,0.1) var grid_spacing_m:=1.0
@export_range(0.001,0.1,0.001) var grid_line_width_m:=0.015
var grid_material: ShaderMaterial
var chrome: VBoxContainer
var toolbar: HFlowContainer
var help_panel: PanelContainer
var help_button: Button
var pause_button: Button
var reset_button: Button
var overlays := {}
var entities: CheckBox
var collisions: CheckBox
var status: Label
var world: Node3D
var model: Node3D
func _ready() -> void:
	world=get_parent(); model=world.get_node("Model")
	if Engine.is_editor_hint():
		apply_floor_grid(); return
	var opened: Dictionary=model.model.open_document()
	if opened.error.is_empty():
		for geom in opened.document.collision_preview(.33,65):
			var overlay:=Preview.create([geom],Transform3D.IDENTITY); add_child(overlay); overlays[geom.name]=overlay
	apply_floor_grid()
	if Engine.is_editor_hint(): return
	var layer:=CanvasLayer.new(); add_child(layer)
	chrome=VBoxContainer.new(); chrome.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(chrome)
	chrome.add_theme_constant_override("separation",8)
	chrome.add_theme_font_size_override("font_size",14)
	var panel:=PanelContainer.new(); chrome.add_child(panel)
	var margin:=MarginContainer.new(); panel.add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,8)
	var bar:=VBoxContainer.new(); margin.add_child(bar)
	toolbar=HFlowContainer.new(); toolbar.add_theme_constant_override("h_separation",8); toolbar.add_theme_constant_override("v_separation",4); bar.add_child(toolbar)
	entities=CheckBox.new(); entities.text="实体"; entities.tooltip_text="显示 / 隐藏实体视觉，不改变物理"; entities.button_pressed=true; toolbar.add_child(entities)
	collisions=CheckBox.new(); collisions.text="碰撞"; collisions.tooltip_text="独立叠加碰撞线框，不改变物理"; toolbar.add_child(collisions)
	entities.toggled.connect(func(_v): apply_display()); collisions.toggled.connect(func(_v): apply_display())
	pause_button=Button.new(); pause_button.text="暂停"; pause_button.pressed.connect(func(): world.request_pause(not world.info().paused)); toolbar.add_child(pause_button)
	reset_button=Button.new(); reset_button.text="重置"; reset_button.tooltip_text="恢复初始位置并保留当前暂停状态"; reset_button.pressed.connect(func(): world.reset_simulation()); toolbar.add_child(reset_button)
	help_button=Button.new(); help_button.text="说明 / 帮助"; help_button.toggle_mode=true; help_button.toggled.connect(set_help_visible); toolbar.add_child(help_button)
	for control in toolbar.get_children(): control.custom_minimum_size.y=30
	status=Label.new(); status.modulate=Color(.75,.78,.82); bar.add_child(status)
	help_panel=PanelContainer.new(); chrome.add_child(help_panel)
	var padding:=MarginContainer.new(); help_panel.add_child(padding)
	for side in ["left","right","top","bottom"]: padding.add_theme_constant_override("margin_"+side,12)
	var box:=VBoxContainer.new(); box.add_theme_constant_override("separation",10); padding.add_child(box)
	var title:=Label.new(); title.text=help_title(); title.add_theme_font_size_override("font_size",18); box.add_child(title)
	var explanation:=Label.new(); explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	explanation.text=help_description()
	box.add_child(explanation)
	var close:=Button.new(); close.text="收起说明"; close.pressed.connect(func(): set_help_visible(false)); box.add_child(close)
	set_help_visible(false)
	get_viewport().size_changed.connect(layout_chrome); layout_chrome()
	apply_display()

func help_title() -> String:
	return "动态形状示例"

func help_description() -> String:
	return """所有物体在同一 MuJoCo 世界中下落和接触。

实体与碰撞可独立显示；橙色线框表示碰撞边界。暂停可检查接触，重置恢复初始位置。

球、盒、圆柱、胶囊、椭球使用原生几何；圆锥使用凸网格。地板网格默认间距 1 m。

构建步骤、物理说明和素材来源见项目 README。"""

func layout_chrome() -> void:
	var width:=minf(440.0,maxf(220.0,get_viewport().get_visible_rect().size.x-24.0))
	chrome.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chrome.offset_left=-width-12; chrome.offset_right=-12; chrome.offset_top=12

func set_help_visible(value: bool) -> void:
	help_panel.visible=value
	help_button.set_pressed_no_signal(value)
	call_deferred("layout_chrome")

func apply_floor_grid() -> void:
	if not model: return
	for name in model.visuals:
		if not str(name).ends_with("floor_geom"): continue
		var mesh: MeshInstance3D=model.visuals[name]
		if not grid_material:
			grid_material=ShaderMaterial.new(); grid_material.shader=preload("floor_grid.gdshader")
		if mesh.material_override!=grid_material:
			if mesh.material_override is StandardMaterial3D: grid_material.set_shader_parameter("base_color",mesh.material_override.albedo_color)
			mesh.material_override=grid_material
		if grid_material.get_shader_parameter("spacing_m")!=grid_spacing_m: grid_material.set_shader_parameter("spacing_m",grid_spacing_m)
		if grid_material.get_shader_parameter("line_width_m")!=grid_line_width_m: grid_material.set_shader_parameter("line_width_m",grid_line_width_m)

func apply_display() -> void:
	for mesh in model.visuals.values(): mesh.visible=entities.button_pressed
	for overlay in overlays.values(): overlay.visible=collisions.button_pressed
func _process(_delta: float) -> void:
	apply_floor_grid()
	if Engine.is_editor_hint(): return
	if not model or not model.model_rid.is_valid(): return
	for geom in PhysicsServer3D.call("scene_geometry",world.space,model.model_rid):
		for name in overlays:
			if str(geom.name).ends_with(name):
				for wire in overlays[name].get_children():
					wire.global_transform=geom.transform
					if geom.type==4: wire.scale=Vector3(geom.source_size.x,geom.source_size.z,geom.source_size.y)
	if pause_button: pause_button.text="继续" if world.info().paused else "暂停"
	if status: status.text="接触数 %d · %s" % [world.info().contact_count if world.info().has("contact_count") else world.info().contact_details.size(),"暂停" if world.info().paused else "运行中"]
