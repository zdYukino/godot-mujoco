@tool
extends EditorNode3DGizmoPlugin
func _get_gizmo_name() -> String: return "MuJoCo joints"
func _has_gizmo(node: Node3D) -> bool: return node.has_method("author_kind") and node.author_kind() == "joint"
func _init() -> void:
	create_material("axis",Color(1,.8,.2))
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	var kind: String = node.get("mjcf/type")
	var points := PackedVector3Array()
	if kind in ["hinge","slide"]:
		points = PackedVector3Array([Vector3(0,-.25,0),Vector3(0,.25,0),Vector3(0,.25,0),Vector3(.04,.18,0),Vector3(0,.25,0),Vector3(-.04,.18,0)])
	else:
		for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]: points.append(-axis*.08); points.append(axis*.08)
	gizmo.add_lines(points,get_material("axis",gizmo))
	gizmo.add_collision_segments(points)
