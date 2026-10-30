@tool
extends Node
@export_range(0.1,10.0,0.1) var grid_spacing_m:=1.0
@export_range(0.001,0.1,0.001) var grid_line_width_m:=0.015
var grid_material: ShaderMaterial
var world: Node3D
var model: Node3D
func _ready() -> void:
	world=get_parent(); model=world.get_node("Model")
	apply_floor_grid()
	if not Engine.is_editor_hint(): call_deferred("register_viewer")
func register_viewer(_viewer: Node = null) -> void:
	if not is_instance_valid(world.runtime_viewer):
		if not world.viewer_ready.is_connected(register_viewer): world.viewer_ready.connect(register_viewer,CONNECT_ONE_SHOT)
		return
	var note := Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.text=help_title()
	world.runtime_viewer.register_extension("gallery",help_title(),note,help_description())
func help_title() -> String:
	return "动态形状示例"
func help_description() -> String:
	return "所有物体在同一 MuJoCo 世界中下落和接触。球、盒、圆柱、胶囊、椭球使用原生几何；圆锥使用凸网格。地板网格默认间距 1 m。\nTab / Shift+Tab 开关原版左右面板；Simulation 控制暂停和重置，F1 帮助，F2 MuJoCo Info。Rendering / Group enable 控制显示，F11 仅为 Godot 附加功能，不改变物理。素材来源见项目 README。"
func apply_floor_grid() -> void:
	if not model or has_meta("benchmark_common"): return
	for name in model.visuals:
		if not str(name).ends_with("floor_geom"): continue
		var mesh: MeshInstance3D=model.visuals[name]
		if not grid_material:
			grid_material=ShaderMaterial.new(); grid_material.shader=preload("floor_grid.gdshader")
			grid_material.set_shader_parameter("base_color",Color(.25,.28,.32,1))
		if mesh.material_override!=grid_material:
			if mesh.material_override is StandardMaterial3D: grid_material.set_shader_parameter("base_color",mesh.material_override.albedo_color)
			elif mesh.material_override is ShaderMaterial:
				var color: Variant=mesh.material_override.get_shader_parameter("base_color")
				if color is Color: grid_material.set_shader_parameter("base_color",color)
			mesh.material_override=grid_material
		if grid_material.get_shader_parameter("spacing_m")!=grid_spacing_m: grid_material.set_shader_parameter("spacing_m",grid_spacing_m)
		if grid_material.get_shader_parameter("line_width_m")!=grid_line_width_m: grid_material.set_shader_parameter("line_width_m",grid_line_width_m)

func _process(_delta: float) -> void:
	apply_floor_grid()
