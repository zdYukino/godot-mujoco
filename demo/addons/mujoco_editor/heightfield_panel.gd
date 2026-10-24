@tool
extends VBoxContainer
const Terrain=preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Grid=preload("res://addons/godot_mujoco/model/heightfield_data.gd")
var plugin:EditorPlugin
var debugger:EditorDebuggerPlugin
var target:Node3D
var draft:Resource
var baseline:Resource
var preview:MeshInstance3D
var status:Label
var heights:TextEdit
var width:SpinBox
var depth:SpinBox
var layer:SpinBox
var mask:SpinBox
var friction:SpinBox
var rough:CheckBox
var draft_material:PhysicsMaterial
var live:OptionButton
var dirty:=false
var error:=""
var selected_key:=""
var syncing:=false
var draft_layer:=1
var draft_mask:=1
var buttons:Dictionary={}
var baseline_state:Dictionary={}
var external_conflict:=false
var runtime_notices:Dictionary={}
func _ready() -> void:
	var title:=Label.new();title.text="静态高度场 / 场景设计与运行实例";add_child(title)
	var row:=HFlowContainer.new();add_child(row)
	width=_number(row,"宽",2,256);depth=_number(row,"深",2,256)
	_button(row,"创建地形",create_terrain)
	layer=_number(row,"Layer",0,4294967295);mask=_number(row,"Mask",0,4294967295);layer.value=1;mask.value=1
	layer.value_changed.connect(_parameters_changed);mask.value_changed.connect(_parameters_changed)
	row=HFlowContainer.new();add_child(row)
	friction=_number(row,"Friction",0,1);friction.step=.01;friction.value=1
	rough=CheckBox.new();rough.text="Rough";row.add_child(rough)
	friction.value_changed.connect(_parameters_changed)
	rough.toggled.connect(func(_value:bool): _parameters_changed(0))
	heights=TextEdit.new();heights.custom_minimum_size=Vector2(320,100);heights.placeholder_text="按行输入高度（米），空格分隔；固定分辨率，无雕刻";add_child(heights)
	row=HFlowContainer.new();add_child(row)
	_button(row,"预览草稿",preview_text);_button(row,"应用到场景",apply_scene);_button(row,"Discard",discard)
	_button(row,"保留草稿并采用当前基线",rebase_draft);_button(row,"撤销场景编辑",undo_scene);_button(row,"保存场景",save_scene)
	live=OptionButton.new();live.fit_to_longest_item=false;live.clip_text=true;live.custom_minimum_size.x=280;row.add_child(live);live.item_selected.connect(_live_selected)
	_button(row,"应用到运行实例",apply_live);_button(row,"移除运行地形",remove_live)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;add_child(status)
	heights.text_changed.connect(func():
		if not syncing: dirty=true;_show_status())
	debugger.changed.connect(refresh_live)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	refresh_live();_selection_changed()
func _scene_state() -> Dictionary:
	if not is_instance_valid(target) or not target.is_inside_tree(): return {}
	return {"grid":target.design.snapshot(Transform3D(),target.collision_layer,target.collision_mask) if target.design else {},"material":_material_state(target.physics_material_override)}
func _material_state(material:PhysicsMaterial) -> Dictionary:
	return {"friction":material.friction if material else 1.0,"rough":material.rough if material else false,"bounce":material.bounce if material else 0.0}
func _draft_snapshot() -> Dictionary:
	var snapshot:Dictionary=draft.snapshot(target.global_transform,draft_layer,draft_mask)
	snapshot["friction"]=-draft_material.friction if draft_material.rough else draft_material.friction
	snapshot["bounce"]=draft_material.bounce
	return snapshot
func _process(_delta:float) -> void:
	if not syncing: _sync_external()
func _sync_external() -> bool:
	var current:=_scene_state()
	if var_to_bytes(current)==var_to_bytes(baseline_state) and not external_conflict: return true
	if dirty or external_conflict:
		external_conflict=true;_clear_preview()
		error="场景设计已被 Undo/Redo 或 Inspector 修改；草稿已保留。Discard 或明确采用当前基线后再应用"
		_show_status();return false
	discard();return true
func rebase_draft() -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.design or not draft: return false
	if target.design.width!=draft.width or target.design.depth!=draft.depth:
		error="分辨率已改变，保留草稿文本；请复制后 Discard，不能自动重定尺寸";_show_status();return false
	baseline=target.design.duplicate(true);baseline_state=_scene_state();external_conflict=false;dirty=true
	error="已保留草稿；下次应用将覆盖当前场景设计";_show_status();return true
func _number(row:Control,label:String,low:float,high:float) -> SpinBox:
	var text:=Label.new();text.text=label;row.add_child(text)
	var box:=SpinBox.new();box.min_value=low;box.max_value=high;box.step=1;box.value=low;row.add_child(box);return box
func _button(row:Control,label:String,action:Callable) -> void:
	var button:=Button.new();button.text=label;button.pressed.connect(action);row.add_child(button);buttons[label]=button
func _parameters_changed(_value:float) -> void:
	if not syncing and is_instance_valid(target): dirty=true;_show_status()
func _selection_changed() -> void:
	var nodes:=EditorInterface.get_selection().get_selected_nodes()
	var candidate:Node3D=nodes[0] if nodes.size()==1 and nodes[0] is Terrain else null
	select_target(candidate)
func select_target(node:Node3D) -> bool:
	if node==target: _sync_external();return true
	if dirty: error="草稿保留在当前地形；先应用或 Discard，再切换选择";_show_status();return false
	_clear_preview();target=node;discard();return true
func discard() -> void:
	_clear_preview();dirty=false;external_conflict=false;error="";draft=null;baseline=null;draft_material=null
	if is_instance_valid(target) and not target.is_inside_tree(): target=null
	if is_instance_valid(target) and target.design:
		baseline=target.design.duplicate(true);draft=baseline.duplicate(true)
		draft_material=target.physics_material_override.duplicate(true) if target.physics_material_override else PhysicsMaterial.new()
		draft_layer=target.collision_layer;draft_mask=target.collision_mask
	baseline_state=_scene_state()
	_sync_fields();_show_status()
func _sync_fields() -> void:
	syncing=true
	if draft:
		friction.value=draft_material.friction;rough.button_pressed=draft_material.rough
		width.value=draft.width;depth.value=draft.depth;layer.value=draft_layer;mask.value=draft_mask
		var rows:=PackedStringArray()
		var stride:=maxi(1,draft.width)
		for start in range(0,draft.heights.size(),stride):
			var cells:=PackedStringArray()
			for index in range(start,mini(start+stride,draft.heights.size())): cells.append(str(draft.heights[index]))
			rows.append(" ".join(cells))
		heights.text="\n".join(rows)
	else: heights.text=""
	width.editable=not is_instance_valid(target);depth.editable=not is_instance_valid(target)
	syncing=false
func preview_text() -> bool:
	if not _sync_external(): return false
	if not is_instance_valid(target) or not draft: error="请选择已保存场景中的专用地形";_show_status();return false
	var tokens:=heights.text.replace("\n"," ").replace("\t"," ").split(" ",false)
	if tokens.size()!=draft.width*draft.depth: error="高度数量必须等于宽 × 深";_show_status();return false
	var values:=PackedFloat32Array()
	for token in tokens:
		if not token.is_valid_float() or not is_finite(token.to_float()) or absf(token.to_float())>10000:
			error="高度必须是有限数值，范围 ±10000 米";_show_status();return false
		values.append(token.to_float())
	draft_material.friction=friction.value;draft_material.rough=rough.button_pressed
	if draft_material.bounce!=0:
		error="地形材质 Bounce 必须为 0；请在 Inspector 修正后 Discard";_show_status();return false
	draft.heights=values;draft_layer=int(layer.value);draft_mask=int(mask.value)
	error=draft.validate()
	if not error.is_empty(): _show_status();return false
	dirty=draft.heights!=baseline.heights or draft_layer!=target.collision_layer or draft_mask!=target.collision_mask or _material_state(draft_material)!=baseline_state.material
	error="";_clear_preview();preview=MeshInstance3D.new();preview.mesh=draft.mesh();target.add_child(preview)
	var original=target.get_node_or_null("HeightfieldVisual")
	if original: original.visible=false
	_show_status();return true
func apply_scene() -> bool:
	if not preview_text(): return false
	if not dirty: _clear_preview();return true
	var undo:=plugin.get_undo_redo();undo.create_action("修改 MuJoCo 静态地形",UndoRedo.MERGE_DISABLE,target)
	undo.add_do_property(target,"design",draft.duplicate(true));undo.add_undo_property(target,"design",target.design)
	for item in [["collision_layer",draft_layer],["collision_mask",draft_mask]]:
		undo.add_do_property(target,item[0],item[1]);undo.add_undo_property(target,item[0],target.get(item[0]))
	# Material drafts are local to this terrain. Keep sharing for grid-only edits;
	# material edits create an independent resource, while Undo restores the exact
	# original reference so earlier Inspector history still targets that resource.
	if _material_state(draft_material)!=_material_state(target.physics_material_override):
		undo.add_do_property(target,"physics_material_override",draft_material.duplicate(true))
		undo.add_undo_property(target,"physics_material_override",target.physics_material_override)
	undo.commit_action();EditorInterface.mark_scene_as_unsaved();discard();return true
func undo_scene() -> void:
	if dirty: error="先应用或 Discard 草稿";_show_status();return
	if not is_instance_valid(target): return
	var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(target))
	if history.has_undo(): history.undo();discard()
	else: error="没有可撤销的场景编辑";_show_status()
func save_scene() -> void:
	if not _sync_external(): return
	if dirty: error="先应用草稿到场景，再保存";_show_status();return
	var root:=EditorInterface.get_edited_scene_root()
	if not root or root.scene_file_path.is_empty(): error="请先将场景另存为项目文件";_show_status();return
	EditorInterface.save_scene_as(root.scene_file_path,false)
	error=""
	_show_status()
func create_terrain() -> void:
	if dirty: error="先应用或 Discard 草稿";_show_status();return
	var root:=EditorInterface.get_edited_scene_root()
	if not root is Node3D: error="请打开 Node3D 场景";_show_status();return
	var node:=Terrain.new();node.name="Heightfield"
	var grid:=Grid.new();grid.width=int(width.value);grid.depth=int(depth.value);grid.heights.resize(grid.width*grid.depth);grid.heights.fill(0)
	node.design=grid
	var undo:=plugin.get_undo_redo();undo.create_action("创建 MuJoCo 静态地形",UndoRedo.MERGE_DISABLE,root)
	undo.add_do_method(root,"add_child",node);undo.add_do_method(node,"set_owner",root);undo.add_do_reference(node)
	undo.add_undo_method(root,"remove_child",node);undo.commit_action()
	EditorInterface.mark_scene_as_unsaved();EditorInterface.get_selection().clear();EditorInterface.get_selection().add_node(node)
func refresh_live() -> void:
	for key in runtime_notices.keys():
		if not debugger.instances.has(key) and not debugger.outcomes.has(key): runtime_notices.erase(key)
	live.clear();live.add_item("选择运行实例（启动 F5/F6）");live.set_item_metadata(0,"")
	for key in debugger.instances:
		var info:Dictionary=debugger.instances[key]
		live.add_item(str(info.path)+" ["+str(info.id).right(8)+"]");live.set_item_metadata(live.item_count-1,key)
		live.get_popup().set_item_tooltip(live.item_count-1,str(info.path)+" ["+str(info.id)+"]")
		if key==selected_key: live.select(live.item_count-1)
	if not debugger.instances.has(selected_key):
		if debugger.outcomes.has(selected_key):
			live.add_item("已移除 ["+selected_key+"]");live.set_item_metadata(live.item_count-1,selected_key);live.select(live.item_count-1)
		else: selected_key=""
	_show_status()
func _live_selected(index:int) -> void:
	selected_key=str(live.get_item_metadata(index));_show_status()
func apply_live() -> bool:
	if not preview_text(): return false
	if not debugger.instances.has(selected_key): runtime_notices[selected_key]="请选择可用运行实例";_show_status();return false
	var ok:bool=debugger.send(selected_key,"apply",{"snapshot":_draft_snapshot()})
	runtime_notices[selected_key]="accepted，等待物理边界完成" if ok else "请求未接受：实例 pending 或已停止"
	_show_status();return ok
func remove_live() -> bool:
	var ok:bool=debugger.send(selected_key,"remove",{})
	runtime_notices[selected_key]="accepted，等待移除完成" if ok else "移除未接受"
	_show_status();return ok
func _runtime_status() -> String:
	var info:Dictionary=debugger.instances.get(selected_key,{})
	if info.get("pending",false): return "pending"
	if not str(info.get("error","")).is_empty(): return "error: "+str(info.error)
	var result:Dictionary=debugger.outcomes.get(selected_key,{})
	if not result.is_empty(): return "completed revision="+str(result.revision) if result.success else "failed: "+str(result.error)
	return runtime_notices.get(selected_key,"idle" if not info.is_empty() else "未选择")
func _show_status() -> void:
	if not status: return
	var info:Dictionary=debugger.instances.get(selected_key,{})
	status.text="设计: %s | dirty=%s conflict=%s | 运行目标: %s revision=%s %s | %s" % [target.name if is_instance_valid(target) else "未选择",dirty,external_conflict,selected_key,info.get("revision","-"),_runtime_status(),error]
func _clear_preview() -> void:
	if is_instance_valid(preview): preview.free()
	preview=null
	if is_instance_valid(target):
		var original=target.get_node_or_null("HeightfieldVisual")
		if original: original.visible=true
func shutdown() -> void:
	_clear_preview()
	if debugger.changed.is_connected(refresh_live): debugger.changed.disconnect(refresh_live)
	var selection:=EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_selection_changed): selection.selection_changed.disconnect(_selection_changed)
