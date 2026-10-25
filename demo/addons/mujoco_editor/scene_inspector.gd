@tool
extends EditorInspectorPlugin
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
var plugin: EditorPlugin
func _can_handle(object: Object) -> bool:
	return object is Model or object is Terrain or object is World or (object is Node3D and object.has_meta("map_specs"))
func _parse_begin(object: Object) -> void:
	var note := Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.text="场景设计属性 · 修改后保存场景；运行实例只通过显式 Apply 更新。"
	add_custom_control(note)
	var button := Button.new(); button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if object is Model:
		button.text="在右侧编辑此 MJCF 模型草稿"
		button.disabled=not object.model or object.model.resource_path.is_empty()
		button.tooltip_text="加载独立模型包，保留来源保护；已有未保存文档须先保存。"
		button.pressed.connect(func():
			if is_instance_valid(object) and object.model and plugin.panel.open_project_model(object.model.resource_path): plugin.reveal_scope(0))
	elif object is Terrain:
		button.text="编辑此地形 / 显式 Apply"
		button.pressed.connect(func():
			if is_instance_valid(object) and plugin.heightfield_panel.select_target(object): plugin.reveal_scope(2))
	elif object is World:
		note.text="全局 · World 参数\nworld_model 定义整个 MuJoCo 世界的选项。nativeccd 是凸碰撞算法开关；修改设计后需显式重启运行世界。"
		button.free(); return
	else:
		button.text="载入此场景地图到右侧草稿"
		button.pressed.connect(func():
			if is_instance_valid(object) and plugin.map_panel.open_scene_map(object): plugin.reveal_scope(1))
	add_custom_control(button)
