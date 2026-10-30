extends CanvasLayer
var slice: CheckBox
func _ready() -> void:
	call_deferred("register_viewer")
func register_viewer(_viewer: Node = null) -> void:
	var world := get_parent().get_parent()
	if not is_instance_valid(world.runtime_viewer):
		if not world.viewer_ready.is_connected(register_viewer): world.viewer_ready.connect(register_viewer,CONNECT_ONE_SHOT)
		return
	var box := VBoxContainer.new()
	slice=CheckBox.new(); slice.text="SDF 距离切片"; box.add_child(slice)
	slice.toggled.connect(func(value):get_parent().get_node("CollisionPreview").visible=value)
	world.runtime_viewer.register_extension("sdf_terrain","SDF 地形",box,"默认真实 mjGEOM_SDF（type 8），闭合分块网格；黄色轮廓是原生距离场水平切片。\n在 Godot 编辑器插件地图面板导入 assets/terrain.obj 并修改碰撞方式、深度参数，保存后运行。\n距离切片使用 Godot 诊断显示；当前原生后端不能混合 Godot 3D 覆盖层，无法使用时回退 Godot。")

func _process(_delta: float) -> void:
	if not is_instance_valid(slice): return
	slice.disabled=get_parent().get_parent().native_view_active
	slice.tooltip_text="MuJoCo 原生画面不叠加 Godot 3D 切片；切换 Godot 渲染后可用。" if slice.disabled else "原生距离场的水平采样轮廓"
