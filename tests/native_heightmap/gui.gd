@tool
extends Node3D
var visual:MeshInstance3D
func _ready():
 visual=MeshInstance3D.new();$Terrain/Collision.add_child(visual)
 $Terrain/Collision.shape.changed.connect(refresh)
 refresh()
func refresh():
 if not is_instance_valid(visual):return
 var shape:HeightMapShape3D=$Terrain/Collision.shape
 var grid=MjHeightFieldData.new();grid.width=shape.map_width;grid.depth=shape.map_depth;grid.heights=shape.map_data
 visual.mesh=grid.mesh()
