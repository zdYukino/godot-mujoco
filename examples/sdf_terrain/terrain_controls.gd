extends CanvasLayer
func _ready() -> void:
	var box:=VBoxContainer.new(); box.position=Vector2(14,14); add_child(box)
	var panel:=PanelContainer.new(); box.add_child(panel)
	var bar:=HBoxContainer.new(); panel.add_child(bar)
	var entities:=CheckBox.new(); entities.text="实体"; entities.button_pressed=true; bar.add_child(entities)
	var collisions:=CheckBox.new(); collisions.text="SDF 距离切片"; bar.add_child(collisions)
	var label:=Label.new(); label.text="例程3 · 台阶 / 洼地 / 崎岖路面 · m · seed 20261026"; bar.add_child(label)
	var help:=Button.new(); help.text="说明 / 帮助"; help.toggle_mode=true; bar.add_child(help)
	var note:=Label.new(); note.text="默认真实 mjGEOM_SDF（type 8），闭合分块网格；不是凸包。黄色轮廓是原生距离场水平切片，不是视觉三角网格。\n可在插件地图面板导入 assets/terrain.obj，右侧选择碰撞方式、深度参数，保存 / Apply / 重开。"; note.visible=false; box.add_child(note)
	help.toggled.connect(func(value): note.visible=value)
	entities.toggled.connect(func(value): get_parent().get_node("Visual").visible=value)
	collisions.toggled.connect(func(value): get_parent().get_node("CollisionPreview").visible=value)
