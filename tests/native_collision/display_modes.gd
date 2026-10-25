@tool
extends RefCounted
func run(plugin, runner) -> void:
	var view=plugin.view_controls
	var scene=EditorInterface.get_edited_scene_root()
	var nodes: Array[Node]=[]; view.scene_nodes(scene,nodes)
	var visible_before := {}
	for node in nodes:
		if node is MeshInstance3D: visible_before[node]=node.visible
	var materials := {}
	for name in plugin.panel.meshes: materials[name]=plugin.panel.meshes[name].material_override
	var before: Dictionary=plugin.state.document.snapshot()
	var settings: Dictionary=plugin.map_panel.session.specs.duplicate(true)
	for entities in [true,false]:
		for collisions in [true,false]:
			view.set_modes(entities,collisions)
			runner.check(plugin.panel.show_visuals==entities and plugin.panel.show_collisions==collisions and plugin.map_panel.show_visual==entities and plugin.map_panel.show_collision==collisions,"toolbar independent modes propagate to MJCF and map %s/%s" % [entities,collisions])
			runner.check(view.overlay_root.visible==collisions and (view.hidden_visuals.is_empty() if entities else view.hidden_visuals.size()==visible_before.size()),"scene render instances obey independent display modes")
			runner.check(visible_before.keys().all(func(node): return node.visible==visible_before[node]),"render hiding does not write scene visible properties")
			runner.check(plugin.state.document.snapshot()==before and plugin.map_panel.session.specs==settings,"display flags do not change collision or document data")
			plugin.panel.highlight_selection()
			runner.check(materials.keys().all(func(name): return plugin.panel.meshes[name].material_override==materials[name] and not materials[name].emission_enabled),"selection outline never replaces or recolors source material")
	for root in plugin.panel.collision_overlays.values():
		for wire in root.get_children():
			runner.check(wire.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_LINES,"MJCF collision representation renders as line overlay")
	var selected := EditorInterface.get_selection().get_selected_nodes()
	plugin.select_preview_target()
	runner.check(EditorInterface.get_selection().get_selected_nodes().is_empty(),"independent draft selection removes unrelated native transform gizmo")
	for node in selected:
		if is_instance_valid(node) and node.is_inside_tree(): EditorInterface.get_selection().add_node(node)
	view.set_modes(true,true)
