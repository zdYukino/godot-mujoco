@tool
extends EditorInspectorPlugin
const Model = preload("res://addons/godot_mujoco/model/model_instance.gd")
const Terrain = preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const World = preload("res://addons/godot_mujoco/model/runtime_world.gd")
const Geom = preload("res://addons/godot_mujoco/model/geom_node.gd")
const Appearance = preload("res://addons/godot_mujoco/model/geom_appearance.gd")
const CollisionProperty = preload("collision_property.gd")
var plugin: EditorPlugin
var creating_editor := false
func _can_handle(object: Object) -> bool:
	return object is Geom or object is Model or object is Terrain or object is World or (object is Node3D and object.has_meta("map_specs"))
func _parse_begin(object: Object) -> void:
	if object is Geom: return
	var note := Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	note.text="在场景树与 Inspector 编辑设计，Ctrl+S 保存。运行中修改会自动暂停，后台编译成功后手动继续。"
	add_custom_control(note)
	var button := Button.new(); button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if object is Model:
		button.text="显示模型操作"
		button.disabled=not object.design
		button.pressed.connect(func():
			if not is_instance_valid(object): return
			plugin.panel.select(object); plugin.reveal_scope(0))
	elif object is Terrain:
		button.text="编辑此地形 / 显式 Apply"
		button.pressed.connect(func():
			if is_instance_valid(object) and plugin.heightfield_panel.select_target(object): plugin.reveal_scope(2))
	elif object is World:
		note.text="全局 · World 参数\nworld_design 定义整个 MuJoCo 世界的选项。物理设计修改会暂停运行世界并重新验证。"
		button.free(); return
	else:
		button.text="载入此场景地图到右侧草稿"
		button.pressed.connect(func():
			if is_instance_valid(object) and plugin.map_panel.open_scene_map(object): plugin.reveal_scope(1))
	add_custom_control(button)

func _parse_group(object: Object, group: String) -> void:
	if not object is Geom or group != "Visibility" or object.item().is_empty(): return
	var editors := []
	# Instantiate first: Godot's factory consults the inspector plugins' pending
	# editor lists, so interleaved registration would reuse the previous control.
	for field in Appearance.fields():
		var editor := EditorInspector.instantiate_property_editor(object, field.type, field.name, field.hint, field.hint_string, field.usage)
		editor.tooltip_text = "写回 MJCF；仅修改当前 geom。\n不透明度：0 完全透明，1 完全不透明。贴图留空可清除。"
		editors.append(editor)
	var fields := Appearance.fields()
	for index in fields.size(): add_property_editor(fields[index].name, editors[index], false, fields[index].label)

func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
	if creating_editor: return false
	if object is Geom and Appearance.handles(name): return true
	if not name.begins_with("mjcf/collision_"): return false
	if object is Geom:
		var labels := {"mode":"碰撞表示","sdf_depth":"SDF 深度","maxhullvert":"凸包顶点上限","actual":"有效碰撞","world":"世界检测策略"}
		var key := name.trim_prefix("mjcf/collision_")
		add_property_editor(name,CollisionProperty.new(name),false,labels.get(key,key))
		return true
	if object is World:
		creating_editor = true
		var editor := EditorInspector.instantiate_property_editor(object,type,name,hint_type,hint_string,usage_flags,wide)
		creating_editor = false
		var labels := {"nativeccd":"原生凸碰撞算法","multiccd":"多接触点检测","ccd_iterations":"凸检测迭代","ccd_tolerance":"凸检测容差","sdf_iterations":"SDF 迭代","sdf_initpoints":"SDF 初始搜索点"}
		editor.tooltip_text = "作用于整个 World，所有模型继承。nativeccd 开启为 GJK/EPA，关闭为 libccd/MPR；multiccd 为多接触点检测，不是时域连续防穿透。"
		add_property_editor(name,editor,false,labels.get(name.trim_prefix("mjcf/collision_"),name))
		return true
	return false
