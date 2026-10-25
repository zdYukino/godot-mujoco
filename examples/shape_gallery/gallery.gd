extends Node
const Preview = preload("res://addons/godot_mujoco/map/collision_preview.gd")
var overlays := {}
var entities: CheckBox
var collisions: CheckBox
var status: Label
var world: Node3D
var model: Node3D
func _ready() -> void:
	world=get_parent(); model=world.get_node("Model")
	var opened: Dictionary=model.model.open_document()
	if opened.error.is_empty():
		for geom in opened.document.collision_preview(.33,65):
			var overlay:=Preview.create([geom],Transform3D.IDENTITY); add_child(overlay); overlays[geom.name]=overlay
	var layer:=CanvasLayer.new(); add_child(layer)
	var panel:=PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); panel.position=Vector2(-330,12); panel.custom_minimum_size.x=318; layer.add_child(panel)
	var box:=VBoxContainer.new(); panel.add_child(box)
	var title:=Label.new(); title.text="动态形状 · 同一 MuJoCo 世界"; box.add_child(title)
	entities=CheckBox.new(); entities.text="显示实体"; entities.button_pressed=true; box.add_child(entities)
	collisions=CheckBox.new(); collisions.text="显示碰撞网格"; box.add_child(collisions)
	entities.toggled.connect(func(_v): apply_display()); collisions.toggled.connect(func(_v): apply_display())
	for label in ["球：native sphere", "正方体：native box", "圆柱：native cylinder", "圆锥：mesh / compiled convex hull", "胶囊：native capsule", "椭球：native ellipsoid", "额外小球下落到盒上，验证物体间接触", "橙色线框为碰撞边界；显隐不改变物理", "天空：Poly Haven / Greg Zaal / CC0", "临时原创基础地板；最终外观待确认"]:
		var text:=Label.new(); text.text=label; text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; box.add_child(text)
	var pause:=Button.new(); pause.text="暂停 / 继续"; pause.pressed.connect(func(): world.request_pause(not world.info().paused)); box.add_child(pause)
	var reset:=Button.new(); reset.text="复位并再次下落"; reset.pressed.connect(func(): world.reset_simulation()); box.add_child(reset)
	status=Label.new(); box.add_child(status)
	apply_display()
func apply_display() -> void:
	for mesh in model.visuals.values(): mesh.visible=entities.button_pressed
	for overlay in overlays.values(): overlay.visible=collisions.button_pressed
func _process(_delta: float) -> void:
	if not model or not model.model_rid.is_valid(): return
	for geom in PhysicsServer3D.call("scene_geometry",world.space,model.model_rid):
		for name in overlays:
			if str(geom.name).ends_with(name):
				for wire in overlays[name].get_children():
					wire.global_transform=geom.transform
					if geom.type==4: wire.scale=Vector3(geom.source_size.x,geom.source_size.z,geom.source_size.y)
	if status: status.text="接触数 %d · %s" % [world.info().contact_count if world.info().has("contact_count") else world.info().contact_details.size(),"暂停" if world.info().paused else "运行中"]
