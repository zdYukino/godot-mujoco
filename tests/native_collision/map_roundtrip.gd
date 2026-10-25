@tool
extends RefCounted
func run(plugin, runner, original_package: String) -> void:
	var map=plugin.map_panel
	var root=EditorInterface.get_edited_scene_root()
	var original_root_pose: Transform3D=root.transform
	root.transform=Transform3D(Basis(Vector3.UP,.35),Vector3(3,2,-4))
	var old: Node3D=root.get_node("StaticMap")
	old.transform=Transform3D(Basis(Vector3.UP,-.6),Vector3(4,1,2))
	var local_pose: Transform3D=old.transform
	var global_pose: Transform3D=old.global_transform
	runner.check(map.open_scene_map(old),"roundtrip loads translated rotated scene map")
	runner.check(map.world.global_transform.is_equal_approx(global_pose),"preview uses map global pose")
	var selection_before:=EditorInterface.get_selection().get_selected_nodes()
	var camera:=EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var camera_before: Transform3D=camera.global_transform
	map.focus("")
	await plugin.get_tree().create_timer(.5).timeout
	runner.check(not camera.global_transform.is_equal_approx(camera_before),"native frame moves editor camera for off-origin map")
	var framed: Vector2=camera.unproject_position(map.world.global_transform*map.center)
	var viewport_size: Vector2=EditorInterface.get_editor_viewport_3d(0).size
	runner.check(not camera.is_position_behind(map.world.global_transform*map.center) and framed.distance_to(viewport_size*.5)<viewport_size.length()*.15,"native framing places off-origin bounds near viewport center")
	runner.check(EditorInterface.get_selection().get_selected_nodes()==selection_before and old.owner==root,"native framing preserves actual selection and scene ownership")
	var root_pose: Transform3D=root.transform
	root.position.x+=1
	runner.check(not map.apply_scene() and root.get_node("StaticMap")==old,"parent pose conflict rejects Apply without replacing target")
	root.transform=root_pose
	runner.check(map.apply_scene(),"roundtrip Apply transformed map")
	map.toggle_collision_preview()
	runner.check(map.collision_preview.visible and not map.preview.visible,"first collision toggle after Apply shows overlay without duplicate visual")
	var replacement: Node3D=root.get_node("StaticMap")
	runner.check(replacement!=old and replacement.transform.is_equal_approx(local_pose) and replacement.global_transform.is_equal_approx(global_pose),"Apply preserves local and global map poses")
	var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(root))
	history.undo()
	runner.check(root.get_node("StaticMap")==old and old.global_transform.is_equal_approx(global_pose) and old.owner==root and old.get_node("Visual").owner==root,"Undo restores original identity pose and owners")
	history.redo()
	runner.check(root.get_node("StaticMap")==replacement and replacement.global_transform.is_equal_approx(global_pose),"Redo restores replacement identity and pose")
	# Reopen also replaces a nested renamed map in its actual parent.
	var parent:=Node3D.new(); parent.name="MapParent"; root.add_child(parent); parent.owner=root
	parent.transform=Transform3D(Basis(Vector3.UP,.2),Vector3(-2,0,5))
	replacement.reparent(parent); replacement.name="PlacedMap"
	var nested_pose: Transform3D=replacement.transform
	global_pose=replacement.global_transform
	runner.check(map.open_scene_map(replacement) and map.apply_scene(),"nested renamed map Apply targets original parent")
	var nested: Node3D=parent.get_node("PlacedMap")
	runner.check(not root.has_node("StaticMap") and nested.transform.is_equal_approx(nested_pose) and nested.global_transform.is_equal_approx(global_pose),"nested Apply preserves parent name and transforms")
	history.undo(); runner.check(parent.get_node("PlacedMap")==replacement,"nested Undo identity")
	history.redo(); runner.check(parent.get_node("PlacedMap")==nested,"nested Redo identity")
	# Apply's authored-scene display mode must not hide independent imports.
	map.path_field.text="res://fixtures/box.glb"; map.unit.select(1)
	runner.check(map.import_source(false) and map.show_visual and map.show_collision and map.preview.visible and map.world.transform==Transform3D.IDENTITY,"Apply then import restores independent visible preview")
	plugin.show_scope(1)
	runner.check(map.pick(map.camera.unproject_position(Vector3.ZERO)),"newly imported draft remains pickable")
	map.show_visual=false; map.show_collision=false
	runner.check(map.import_source(true) and not map.show_visual and not map.show_collision and not map.preview.visible,"new import preserves explicit user display preferences")
	map.show_visual=true; map.show_collision=true; map.rebuild()
	runner.check(map.apply_scene(),"Apply independently imported map")
	plugin.scene_switched(root); await runner.settle()
	runner.check(not map.scene_preview_suppressed and map.preview.visible,"scene switch releases obsolete authored-scene display suppression")
	runner.check(map.open_package(original_package) and map.show_visual and map.show_collision and map.preview.visible,"Apply then open package restores visible preview")
	# Ordinary heightfields live outside Visual in authored maps.
	var contract: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://fixtures/ramp.height.json"))
	if contract.is_empty():
		contract={"width":3,"depth":2,"spacing_x":1,"spacing_z":1,"unit":"m","row_order":"increasing_z","encoding":"float32_le"}
	runner.check(map.session.import_height("res://fixtures/ramp.raw",contract),"heightfield added to map draft")
	runner.check(map.apply_scene(),"ordinary heightfield map Apply")
	var authored: Node3D=root.get_node("StaticMap")
	var name: String=map.session.terrains[0].name
	runner.check(authored.has_node(NodePath(name)) and not authored.has_node(NodePath("Visual/"+name)),"ordinary authored heightfield is outside Visual")
	var packed: Dictionary=map.Package.pack(map.session,"res://roundtrip_height")
	runner.check(packed.error.is_empty() and map.open_scene_map(authored) and map.items.has(name),"scene load restores heightfield draft tree item")
	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(authored.get_node(NodePath(name)))
	await runner.settle()
	runner.check(plugin.scope.selected==1 and map.selected==name and map.strategy.disabled and not map.configure_action.disabled,"scene heightfield selection drives map properties")
	map.friction.value=.62
	runner.check(map.configure() and map.apply_scene(),"heightfield friction roundtrip Apply")
	authored=root.get_node("StaticMap")
	runner.check(is_equal_approx(authored.get_node(NodePath(name)).physics_material_override.friction,.62),"ordinary heightfield material preserves edited friction")
	packed=map.Package.pack(map.session,"res://roundtrip_height")
	runner.check(packed.error.is_empty() and map.open_scene_map(authored),"reopen edited heightfield scene")
	map.items[name].select(0); map.select_tree(); map.native_contact.set_pressed_no_signal(true); map.advanced.text='{"condim":4,"friction":[0.7,0.02,0.001]}'
	runner.check(map.configure() and map.apply_scene(),"heightfield native contact roundtrip Apply")
	authored=root.get_node("StaticMap")
	runner.check(authored.native_collisions.size()>0 and authored.has_node(NodePath("Visual/"+name)),"native heightfield stays in native collision and Visual paths")
	packed=map.Package.pack(map.session,"res://roundtrip_height")
	runner.check(packed.error.is_empty() and map.open_scene_map(authored) and map.items.has(name),"native heightfield scene reopen preserves tree item")
	map.items[name].select(0); map.select_tree()
	runner.check(map.native_contact.button_pressed and JSON.parse_string(map.advanced.text).condim==4,"native heightfield parameters survive scene roundtrip")
	# Restore the shared fixture for the lifecycle and narrow-dock tests.
	map.open_package(original_package); map.apply_scene()
	root.transform=original_root_pose
