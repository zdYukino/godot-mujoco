@tool
extends RefCounted
func run(plugin,runner,map: Node3D) -> void:
	var scene:=EditorInterface.get_edited_scene_root()
	var visual: MeshInstance3D=plugin.map_panel.session.meshes(map.get_node("Visual"))[0]
	var path:=str(map.get_node("Visual").get_path_to(visual))
	plugin.select_preview_target(path)
	runner.check(EditorInterface.get_selection().get_selected_nodes()==[map],"draft map pick targets common transform root, never visual-only child")
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(visual)
	await runner.settle()
	runner.check(EditorInterface.get_selection().get_selected_nodes()==[map],"direct scene-tree visual selection redirects unsafe child gizmo to map root")
	var physics: Node3D=map.get_node("Physics").get_child(0)
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(physics)
	await runner.settle()
	runner.check(EditorInterface.get_selection().get_selected_nodes()==[map],"direct physics-child selection also redirects to common map root")
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(visual); EditorInterface.get_selection().add_node(physics)
	await runner.settle()
	runner.check(EditorInterface.get_selection().get_selected_nodes()==[map],"multi-selected map children collapse to one safe transform root")
	var panel=plugin.map_panel
	panel.show_collision=true; panel.rebuild(); await runner.settle()
	var wires: Array=panel.session.meshes(panel.collision_preview)
	runner.check(not wires.is_empty(),"bound draft has concrete collision overlay geometry")
	var wire_before: Dictionary={}
	for wire in wires: wire_before[wire]=wire.global_transform
	var baseline_pose: Transform3D=panel.scene_local_pose
	var baseline_parent: Transform3D=panel.scene_parent_pose
	var baseline_content: Dictionary=panel.scene_baselines.duplicate(true)
	var before:=map.transform
	var visual_before:=visual.global_transform
	var physics_before:=physics.global_transform
	var delta:=Transform3D(Basis(Vector3.UP,.7),Vector3(6,3,-2))
	var global_before:=map.global_transform
	var after: Transform3D=map.get_parent().global_transform.affine_inverse()*delta*global_before
	var undo=plugin.get_undo_redo()
	undo.create_action("Map native transform regression",UndoRedo.MERGE_DISABLE,map)
	undo.add_do_property(map,"transform",after); undo.add_undo_property(map,"transform",before); undo.commit_action()
	runner.check(visual.global_transform.is_equal_approx(delta*visual_before) and physics.global_transform.is_equal_approx(delta*physics_before),"native root transform moves authored visual and ordinary physics together")
	await runner.settle()
	runner.check(panel.world.global_transform.is_equal_approx(map.global_transform) and wires.all(func(wire): return wire.global_transform.is_equal_approx(delta*wire_before[wire])),"bound collision overlay follows actual root translation and rotation in world coordinates")
	runner.check(panel.scene_local_pose==baseline_pose and panel.scene_parent_pose==baseline_parent and panel.scene_baselines==baseline_content and not panel.apply_scene(),"render pose sync preserves baseline and still rejects stale draft Apply")
	var history=undo.get_history_undo_redo(undo.get_object_history_id(scene))
	history.undo(); await runner.settle()
	runner.check(wires.all(func(wire): return wire.global_transform.is_equal_approx(wire_before[wire])),"bound collision overlay follows native transform Undo")
	runner.check(map.transform.is_equal_approx(before) and visual.global_transform.is_equal_approx(visual_before) and physics.global_transform.is_equal_approx(physics_before),"root transform Undo restores visual and collision positions")
	history.redo(); await runner.settle()
	runner.check(wires.all(func(wire): return wire.global_transform.is_equal_approx(delta*wire_before[wire])),"bound collision overlay follows native transform Redo")
	runner.check(map.transform.is_equal_approx(after) and physics.global_transform.is_equal_approx(delta*physics_before),"root transform Redo keeps visual and collision aligned")
	var host:=Node3D.new(); host.name="MovedMapHost"
	var copy: Node3D=map.duplicate(); copy.transform=map.global_transform; host.add_child(copy)
	plugin.map_panel.session.own_scene(copy,host)
	var expected: Dictionary={}
	for mesh in plugin.map_panel.session.meshes(map.get_node("Visual")): expected[str(map.get_path_to(mesh))]=mesh.global_transform
	copy.set_meta("expected_visual_transforms",expected)
	var packed:=PackedScene.new(); packed.pack(host)
	runner.check(ResourceSaver.save(packed,"res://MovedMap.tscn")==OK,"save moved map for independent runtime physics reopen")
	host.free()
	var reopened: Node3D=load("res://MovedMap.tscn").instantiate(); scene.add_child(reopened)
	var restored: Node3D=reopened.get_node("StaticMap")
	runner.check(restored.global_transform.is_equal_approx(scene.global_transform*map.global_transform) and restored.native_collisions==map.native_collisions,"saved map retains root pose and native collision local definitions")
	reopened.free()
	history.undo()
