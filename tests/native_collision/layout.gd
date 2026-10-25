extends SceneTree
var passed:=0
var failed:=0
func _initialize(): call_deferred("run")
func check(ok: bool,label: String):
	if ok: passed+=1
	else: failed+=1
	print("PASS " if ok else "FAIL ",label)
func settle():
	for i in 8: await process_frame
func collect_actions(node: Node, out: Array[Control]):
	if node is Button and not node is OptionButton and not node is CheckBox: out.append(node)
	for child in node.get_children(): collect_actions(child,out)
func run():
	var panel:=preload("res://addons/mujoco_editor/map_panel.gd").new()
	root.add_child(panel); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var controls: Array[Control]=[panel.path_field,panel.unit,panel.axes,panel.strategy,panel.native_contact,panel.advanced,panel.world_options,panel.relations,panel.parts,panel.friction,panel.layer,panel.mask,panel.slice_level]
	collect_actions(panel.layout_content,controls)
	var names:=controls.filter(func(c):return c is Button).map(func(c):return c.text)
	check("保存独立地图包" in names and "Apply 到编辑场景" in names and "验证并应用碰撞草稿" in names,"required actions retained")
	for size_value in [Vector2i(1180,812),Vector2i(900,500),Vector2i(640,400),Vector2i(420,360),Vector2i(320,240)]:
		root.size=size_value; panel.layout_scroll.scroll_vertical=0; panel.layout_scroll.scroll_horizontal=0
		await settle()
		var bounds:=panel.layout_scroll.get_global_rect()
		check(panel.size.x<=size_value.x+1 and panel.size.y<=size_value.y+1,"dock not expanded beyond host "+str(size_value))
		check(panel.layout_note.autowrap_mode==TextServer.AUTOWRAP_WORD_SMART and panel.layout_note.size.x<=bounds.size.x+1,"instruction wraps within dock "+str(size_value))
		check(panel.preview_split.vertical==(bounds.size.x<640),"preview orientation responsive "+str(size_value))
		var vertical:=panel.layout_scroll.get_v_scroll_bar(); var horizontal:=panel.layout_scroll.get_h_scroll_bar()
		check(panel.layout_content.size.y<=bounds.size.y+1 or (vertical.visible and vertical.max_value>vertical.page),"overflow is reachable by scrollbar when needed "+str(size_value))
		var reached:=0
		for control in controls:
			# This moves only the public scroll container; no button signal/click is invoked.
			panel.layout_scroll.ensure_control_visible(control); await settle()
			var viewport:=panel.layout_scroll.get_global_rect()
			if vertical.visible: viewport.size.x-=vertical.size.x
			if horizontal.visible: viewport.size.y-=horizontal.size.y
			var rect:=control.get_global_rect()
			if viewport.grow(1).encloses(rect) and control.is_visible_in_tree(): reached+=1
			else: print("UNREACHABLE ",size_value," ",control.get_class()," ",control.get("text")," control=",rect," viewport=",viewport)
		check(reached==controls.size(),"all %d workflow controls fit scroll viewport %s" % [controls.size(),str(size_value)])
		check(not horizontal.visible,"no horizontal clipping or compulsory horizontal scrolling "+str(size_value))
	panel.shutdown(); panel.free()
	print("NATIVE_LAYOUT_RESULT ",JSON.stringify({"passed":passed,"failed":failed,"scope":"headless measured bounds and scroll reachability; no mouse GUI acceptance claimed"})); quit(0 if failed==0 else 1)
