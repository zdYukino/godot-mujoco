@tool
class_name MjViewerUI
extends "ui_base.gd"
## Editable UI scene contract. This node presents values and emits actions only.
const SimulateUI = preload("simulate_ui.gd")
const Keys = preload("shortcuts.gd")
const Radio = preload("simulate_radio.gd")
@export var use_default_presenters := true
@export var automatic_overlay_layout := true
@export var render_region: Control
var runtime_world: Node3D
var frame: Dictionary = {}
var catalog: Dictionary = {}
var details: Dictionary = {}
var fields := {}
var windows := {}
var sections := {}
var subsection_targets := {}
var _catalog_slots := {}
var _catalog_roots := {}
var _catalog_fields: Array = []
var extension_help := {}
var left_panel: ScrollContainer
var right_panel: ScrollContainer
var help_label: Label
var watch_label: Label
var feedback_label: Label
var run_label: Label
var speed_label: Label
var help_hint: Label
var profiler_plots: Array = []
var sensor_plot: Control
var sensor_images: VBoxContainer
var shortcut_hints: Array[Control] = []
var managed_popups: Array[Window] = []
var sensor_versions := {}
var ui_spacing := 0
var ui_color := 0
var ui_font := 1
var native_theme: Theme
var authored_theme: Theme
var info_enabled := false
var renderer_fps := 0.0
var host_fps := 0.0
var watch_field := "qpos"
var watch_index := 0
var inspect_due := true
var updating := false
var attached := false
var key_index := -1
var selected_image_sensor := -1
var render_rect := Rect2()
var outer_rect := Rect2()
var last_profiler_time := -1.0
var feedback_deadline := 0
var feedback := "":
	set(value):
		feedback=value;feedback_deadline=Time.get_ticks_msec()+8000
		refresh_feedback()
var _ready_bindings := false
var _last_layout := Rect2()

func _ready() -> void:
	hydrate_bindings()
	resized.connect(_layout_updated)
	set_process(true)

func hydrate_bindings() -> void:
	if _ready_bindings: return
	_ready_bindings=true
	var nodes: Array[Node]=[self]
	while not nodes.is_empty():
		var node: Node=nodes.pop_back()
		nodes.append_array(node.get_children())
		if node is BaseButton:node.set_meta("viewer_authored_disabled",node.disabled)
		if node is Range or node is LineEdit:node.set_meta("viewer_authored_editable",node.editable)
		if node.has_meta("viewer_role"):
			var role := str(node.get_meta("viewer_role"))
			if role!="render_region" or not is_instance_valid(render_region):set(role,node)
		if node.has_meta("viewer_field"): fields[str(node.get_meta("viewer_field"))]=node
		if node is Control and node.has_meta("viewer_bind_action"):_wire_authored_action(node)
		if node.has_meta("viewer_overlay"): windows[str(node.get_meta("viewer_overlay"))]=node
		if node.has_meta("viewer_section"):
			var binding: Dictionary=node.get_meta("viewer_section")
			var map: Dictionary=sections
			if not map.has(binding.name): map[binding.name]={}
			map[binding.name][binding.role]=node
		if node is VBoxContainer and node.has_meta("viewer_catalog_slot"):_catalog_slots[str(node.get_meta("viewer_catalog_slot"))]=node
		if node.has_meta("viewer_subsection"): subsection_targets[str(node.get_meta("viewer_subsection"))]=node
		if node.has_meta("viewer_profiler"):
			var index: int=node.get_meta("viewer_profiler")
			if index<0 or index>=SimulateUI.PROFILER_TITLES.size():continue
			while profiler_plots.size()<=index: profiler_plots.append(null)
			profiler_plots[index]=node
		if node.has_meta("viewer_hints"): shortcut_hints.append(node)
		if node.has_meta("viewer_value_label") and node.get_parent() is HSlider: node.get_parent().set_meta("value_label",node)
	var ordered := {}
	for title in SimulateUI.LEFT+SimulateUI.RIGHT:
		if sections.has(title):ordered[title]=sections[title]
	sections=ordered
	for map in [sections]:
		for title in map:
			var row: Dictionary=map[title]
			row.panel=left_panel if SimulateUI.LEFT.has(title) else right_panel
			row.button.toggled.connect(func(value):
				row.box.visible=value;row.triangle.text="▼" if value else "◀";inspect_due=true;cancel_gesture();save_preferences();layout_changed.emit())
			row.button.gui_input.connect(func(event):
				panel_hint(event)
				if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.double_click: _fold_side.call_deferred(map,row.panel,row.button))
	for hints in shortcut_hints: hints.panel=left_panel if hints.get_meta("viewer_hints")==0 else right_panel
	if use_default_presenters:
		_wire_standard_controls()
		var captions := [["total","active","changed","evals","updates"],["improvement","gradient","lineslope"],["total","collision","prepare","solve","other"],["dof","body","constraint","sqrt(nnz)","contact","iteration"]]
		for index in SimulateUI.PROFILER_TITLES.size():
			var plot := _profiler_plot(index)
			if is_instance_valid(plot):plot.title=SimulateUI.PROFILER_TITLES[index];plot.captions=captions[index]
		if is_instance_valid(sensor_plot):sensor_plot.title="Sensor data";sensor_plot.bars=true
	refresh_help()
	_layout_updated()

func _has_field(key: String) -> bool:
	return is_instance_valid(fields.get(key))

func _profiler_plot(index: int) -> Control:
	if index<profiler_plots.size() and is_instance_valid(profiler_plots[index]):return profiler_plots[index]
	return null

func _overlay_visible(key: String) -> bool:
	return is_instance_valid(windows.get(key)) and windows[key].is_visible_in_tree()

func provides_action(action_id: StringName) -> bool:
	if str(action_id) in ["help","info","profiler","sensors"]:return is_instance_valid(windows.get(str(action_id)))
	if action_id==&"image_sensor":return is_instance_valid(windows.get("sensors")) and is_instance_valid(sensor_images)
	if action_id==&"panels":return is_instance_valid(left_panel) or is_instance_valid(right_panel)
	return true
func inspection_request() -> Dictionary:
	return {"inspect":inspect_due or is_instance_valid(left_panel) and left_panel.is_visible_in_tree() or is_instance_valid(right_panel) and right_panel.is_visible_in_tree(),"watch_field":watch_field,"watch_index":watch_index,"sensors":_overlay_visible("sensors"),"profiler":_overlay_visible("profiler")}

func validate_scene() -> String:
	if not is_instance_valid(render_region): return "UI scene must declare a valid render_region Control."
	if render_region!=self and not is_ancestor_of(render_region): return "render_region must belong to this UI scene."
	return ""

func configure(component: Node, custom_theme: Theme, preview := false) -> void:
	hydrate_bindings();controller=component
	# An explicit component override wins; otherwise a Theme authored on the
	# UI scene root remains its base style. The default root has no Theme.
	authored_theme=custom_theme if custom_theme!=null else theme
	if authored_theme:
		theme=authored_theme
		for panel in [left_panel,right_panel]:
			if is_instance_valid(panel): panel.theme=authored_theme
	for hints in shortcut_hints: hints.visible=false
	if preview: show_preview()

func _process(_delta: float) -> void:
	if not is_instance_valid(render_region): return
	var rect := Rect2(render_region.get_global_rect().position-global_position,render_region.get_global_rect().size)
	if rect!=_last_layout:
		_last_layout=rect;render_rect=rect;outer_rect=Rect2(Vector2.ZERO,size);_layout_updated();layout_changed.emit()

func _layout_updated() -> void:
	if not automatic_overlay_layout: return
	if not is_instance_valid(render_region): return
	render_rect=Rect2(render_region.get_global_rect().position-global_position,render_region.get_global_rect().size)
	var rect := render_rect
	if is_instance_valid(windows.get("help")): windows.help.position=rect.position+Vector2(8,8);windows.help.size=Vector2(maxf(1,rect.size.x*(1-.25*int(_overlay_visible("profiler"))-.25*int(_overlay_visible("sensors")))-16),maxf(1,rect.size.y-16))
	if is_instance_valid(windows.get("profiler")): windows.profiler.position=rect.position+Vector2(rect.size.x*.75,0);windows.profiler.size=Vector2(rect.size.x*.25,rect.size.y)
	if is_instance_valid(windows.get("sensors")): windows.sensors.position=rect.position+Vector2(rect.size.x*(.5 if _overlay_visible("profiler") else .75),rect.size.y*2/3);windows.sensors.size=Vector2(rect.size.x*.25,rect.size.y/3)
	for hints in shortcut_hints:
		if is_instance_valid(hints.panel):hints.position=hints.panel.get_global_rect().position-global_position;hints.size=hints.panel.size
	_layout_status_labels()

func _layout_status_labels() -> void:
	if not automatic_overlay_layout:return
	if is_instance_valid(run_label):run_label.position=render_rect.position+Vector2(maxf(8,(render_rect.size.x-run_label.get_combined_minimum_size().x)/2),6)
	if is_instance_valid(speed_label):speed_label.position=render_rect.position+Vector2(6,6)

func _fold_side(map: Dictionary, panel: Node, toggle: Button) -> void:
	var opened := not toggle.button_pressed
	for row in map.values():
		if row.panel==panel: row.button.button_pressed=opened

func send(command: Dictionary) -> int:
	var args := command.duplicate();var action_id := str(args.get("action",""));args.erase("action")
	_emit(action_id,args);return 0
func perform(action: String, precise := false) -> void: _emit(action,{"precise":precise} if action=="copy_state" else {})
func output_directory() -> String:
	return controller.output_directory() if is_instance_valid(controller) else ""
func reload_saved() -> void: _emit("reload")
func set_fullscreen(value: bool) -> void: _emit("fullscreen",{"value":value})

func _wire_standard_controls() -> void:
	for action in SimulateUI.FILE_ACTIONS:
		if _has_field("file:"+action[1]):_wire_button(fields["file:"+action[1]],action[1])
	for key in ["help","info","profiler","sensors"]:
		if not fields.has("option:"+key):continue
		var kind: String=key;tag_action(fields["option:"+key],kind);fields["option:"+key].toggled.connect(func(value):_emit(kind,{"value":value}))
	if _has_field("pause_update"):
		tag_action(fields.pause_update,"pause_update");fields.pause_update.toggled.connect(func(value):
			if not updating:_emit("pause_update",{"enabled":value}))
	if _has_field("fullscreen"):tag_action(fields.fullscreen,"fullscreen");fields.fullscreen.toggled.connect(set_fullscreen)
	if _has_field("vsync"):tag_action(fields.vsync,"vsync");fields.vsync.toggled.connect(func(value):_emit("vsync",{"value":value}))
	if _has_field("run"):
		fields.run.item_selected.connect(func(value):
			if not updating:_emit("pause",{"value":value==0}))
		tag_action(fields.run,"pause")
	for key in ["threads","key","noise_std","noise_rate","history"]:
		if not _has_field(key):continue
		var kind: String=key;var action_id: String={"threads":"threads","key":"key_load","noise_std":"ctrl_noise","noise_rate":"ctrl_noise","history":"history_seek"}[key]
		tag_action(fields[key],action_id)
		fields[key].value_changed.connect(func(value):
			if updating: return
			var args: Dictionary={"threads":{"value":int(value)},"key":{"id":int(value)},"noise_std":{"std":value},"noise_rate":{"rate":value},"history":{"offset":int(value)}}[kind]
			if kind=="key": key_index=int(value)
			_emit(action_id,args))
	if _has_field("key_load"):tag_action(fields.key_load,"key_load");fields.key_load.pressed.connect(func():_emit("key_load",{"id":key_index}))
	if _has_field("key_save"):tag_action(fields.key_save,"key_save");fields.key_save.pressed.connect(func():_emit("key_save",{"id":key_index}))
	if _has_field("watch_edit"):
		fields.watch_edit.text_submitted.connect(func(value):_emit("watch",{"field":value,"index":watch_index}))
		tag_action(fields.watch_edit,"watch")
	for node in find_children("*","Control",true,false):
		var section := str(node.get_meta("mujoco_section",""));var title := str(node.get_meta("mujoco_name",""))
		if section=="Simulation" and node is Button and title in ["Reset","Reload","Align","Copy state"]:
			var action_id: String={"Reset":"reset_initial","Reload":"reload","Align":"align","Copy state":"copy_state"}[title]
			_wire_button(node,action_id);fields["simulation:"+action_id]=node
		if section=="Control" and node is Button and title=="Clear all": _wire_button(node,"clear_control")
		if section=="Watch" and title=="Index" and node is SpinBox:
			fields.watch_index=node;tag_action(node,"watch");node.value_changed.connect(func(value):_emit("watch",{"field":watch_field,"index":int(value)}))
		if section=="Option" and node is OptionButton:
			var key: String={"Spacing":"ui_spacing","Color":"ui_color","Font":"ui_font"}.get(title,"")
			if not key.is_empty():
				tag_action(node,key);node.item_selected.connect(func(value):_emit(key,{"value":value}))

func apply_snapshot(snapshot: Dictionary) -> void:
	var next: Dictionary=snapshot.get("frame",{})
	if not frame.is_empty() and next.get("revision",-1)!=frame.get("revision",-1): retire_model_controls();clear_sensor_images()
	frame=next;details=snapshot.get("details",{});attached=not frame.is_empty()
	var incoming: Dictionary=snapshot.get("catalog",{})
	if incoming!=catalog:
		catalog=incoming
		if use_default_presenters: build_catalog()
	renderer_fps=snapshot.get("renderer_fps",0.);host_fps=snapshot.get("host_fps",0.)
	if use_default_presenters and not frame.is_empty():update_info()
	inspect_due=false

func apply_ui_theme() -> void:
	if authored_theme: return
	native_theme=SimulateUI.make_theme(ui_color,ui_spacing,ui_font);theme=native_theme
	for panel in [left_panel,right_panel]:
		if is_instance_valid(panel):panel.theme=native_theme
	layout_changed.emit()

func set_info(value: bool) -> void:
	info_enabled=value
	if is_instance_valid(windows.get("info")):windows.info.visible=value
	if fields.has("option:info"):fields["option:info"].set_pressed_no_signal(value)
	save_preferences()
func set_auxiliary(key: String, value: bool) -> void:
	if key=="info":set_info(value);return
	if not is_instance_valid(windows.get(key)):return
	windows[key].visible=value
	if fields.has("option:"+key):fields["option:"+key].set_pressed_no_signal(value)
	inspect_due=true;_layout_updated();save_preferences()
func set_native_panels(left: bool,right: bool) -> void:
	if is_instance_valid(left_panel):left_panel.visible=left
	if is_instance_valid(right_panel):right_panel.visible=right
	inspect_due=true;cancel_gesture();layout_changed.emit();save_preferences()
func refresh_help() -> void:
	if not fields.has("help_actions"):return
	var actions := PackedStringArray();var shortcuts := PackedStringArray()
	for row in Keys.ACTIONS:
		if is_instance_valid(controller) and not controller.action_allowed(row[1]):continue
		actions.append(row[3]);shortcuts.append(row[2])
	fields.help_actions.text="\n".join(actions);fields.help_shortcuts.text="\n".join(shortcuts)
	if not is_instance_valid(help_label):return
	var notes := PackedStringArray()
	if not is_instance_valid(controller) or controller.action_allowed("move"):
		notes.append("左拖旋转；右拖平移；中键/滚轮缩放。Shift调整方向，Alt交换左右键。")
	if not is_instance_valid(controller) or controller.action_allowed("select",{"button":1}):notes.append("左双击选择。")
	if not is_instance_valid(controller) or controller.action_allowed("parent"):notes.append("PageUp选择父级。")
	if not is_instance_valid(controller) or controller.action_allowed("select",{"button":2}):notes.append("右双击居中；Ctrl+右双击跟踪。")
	if not is_instance_valid(controller) or controller.action_allowed("perturb_begin"):
		notes.append("Ctrl+左拖旋转扰动，Ctrl+右拖平移扰动；运行施力，暂停调整自由关节/mocap姿态。")
	for key in Keys.CTRL:
		var action_id: String=Keys.CTRL[key]
		if not is_instance_valid(controller) or controller.action_allowed(action_id):notes.append("Ctrl+%s  %s" % [OS.get_keycode_string(key),{"align":"模型默认取景","reload":"重载最后保存设计","copy_state":"复制状态（Shift提高精度）","print_model":"输出模型","print_data":"输出数据","screenshot":"截图","quit":"退出运行"}.get(action_id,action_id)])
	if not is_instance_valid(controller) or controller.action_allowed("panels"):
		notes.append("Tab切换左面板；Shift+Tab切换右面板。")
		for title in sections:notes.append("Alt+%s  %s" % [SimulateUI.SECTION_KEYS[title],title])
	for group in ["geom","site"]:
		var group_keys := PackedStringArray()
		for index in 6:
			if not is_instance_valid(controller) or controller.action_allowed("group",{"name":group,"id":index}):group_keys.append(("Shift+" if group=="site" else "")+str(index))
		if not group_keys.is_empty():notes.append("%s  %s组" % ["、".join(group_keys),group.capitalize()])
	for kind in ["vis","rnd"]:
		for flag in catalog.get(kind,[]):
			if flag.get("supported",true) and not str(flag.get("shortcut","")).is_empty() and (not is_instance_valid(controller) or controller.action_allowed(kind,{"id":flag.id})):notes.append("%s  %s" % [flag.shortcut,flag.name])
	notes.append("F8–F10保留Godot调试操作；文本编辑优先。\nGodot保留场景材质与灯光；原生使用MuJoCo画面。\n运行操作不回写场景/MJCF。")
	if not is_instance_valid(controller) or controller.action_allowed("fullscreen"):notes.append("独立运行支持F5全屏；嵌入GameView由编辑器管理。")
	for key in extension_help:notes.append(str(extension_help[key]))
	help_label.text="\n"+"\n".join(notes)
func add_help(key: String, title: String, text: String) -> void:
	extension_help[key]=title+"\n"+text
	refresh_help()

func remove_help(key: String) -> void:
	extension_help.erase(key)
	refresh_help()

func show_preview() -> void:
	var marker := Label.new();marker.name="PreviewData";marker.text="预览数据 · F5后绑定真实仿真";marker.position=Vector2(280,10);marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(marker,false,Node.INTERNAL_MODE_BACK)
	if not use_default_presenters:return
	frame={"revision":0,"time":0.,"paused":true,"history_count":1,"history_offset":0,"speed_percent":100.,"camera":{"type":0},"settings":{},"stats":{}}
	catalog={"cameras":["Free"],"labels":["None"],"frames":["None"],"nkey":0}
	details={"joints":[{"id":0,"name":"Preview joint","value":.2,"min":-1.,"max":1.,"limited":true,"disabled":true}],"controls":[{"id":0,"name":"Preview control","value":.3,"min":-1.,"max":1.,"limited":true,"disabled":true}],"equalities":[{"id":0,"name":"Preview equality","value":false}],"sensors":[]}
	build_catalog();update_info()
	for node in find_children("*","Control",true,false):node.mouse_filter=Control.MOUSE_FILTER_IGNORE

func section_box(section: String) -> VBoxContainer:
	if subsection_targets.has(section):return subsection_targets[section]
	if _catalog_roots.has(section):return _catalog_roots[section]
	return sections[section].box

func button(section: String, text: String, action: Callable, target: Control = null) -> Button:
	var widget := Button.new();widget.text=text;widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;widget.pressed.connect(action);(section_box(section) if target==null else target).add_child(widget);native_item(widget,section,text,"BUTTON");tag_action(widget,{"Copy camera":"copy_camera","Clear all":"clear_control"}.get(text,"panels"));return widget

func check(section: String, text: String, value: bool, action: Callable, target: Control = null) -> CheckBox:
	var widget := CheckBox.new();widget.text=text;widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;widget.button_pressed=value;widget.toggled.connect(action);(section_box(section) if target==null else target).add_child(widget);native_item(widget,section,text,"CHECK")
	if section=="Logging":tag_action(widget,"logging")
	return widget

func explanation(section: String, text: String) -> Label:
	var label := Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; section_box(section).add_child(label); return label

func select_option(section: String, title: String, options: Array, selected: int, action: Callable) -> OptionButton:
	var row := HBoxContainer.new(); section_box(section).add_child(row)
	var label := Label.new(); label.text=title; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var widget := OptionButton.new()
	for value in options: widget.add_item(value)
	widget.custom_minimum_size.x=110
	if not options.is_empty():widget.select(clampi(selected,0,options.size()-1))
	widget.item_selected.connect(action);row.add_child(widget);native_item(widget,section,title,"SELECT")
	if section=="Rendering":tag_action(widget,{"Camera":"camera","Label":"label","Frame":"frame","Sensor":"image_sensor"}.get(title,"visual"))
	manage_popup(widget.get_popup())
	return widget

func radio_option(section: String, title: String, options: Array, selected: int, action: Callable) -> Control:
	if not title.is_empty(): explanation(section,title)
	var radio := Radio.new();section_box(section).add_child(radio);radio.setup(options,selected);radio.item_selected.connect(action);native_item(radio,section,title,"RADIO");return radio

func subsection(section: String, title: String, opened := true) -> void:
	var parent: VBoxContainer=_catalog_roots.get(section,sections[section].box)
	var toggle := Button.new();toggle.text=title;toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT;toggle.theme_type_variation="MuJoCoSubsection";toggle.action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS;toggle.toggle_mode=true;toggle.button_pressed=opened;parent.add_child(toggle);native_item(toggle,section,title,"SEPARATOR")
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",2);box.visible=opened;parent.add_child(box);subsection_targets[section]=box
	toggle.toggled.connect(func(value):box.visible=value;cancel_gesture())

func numeric_slider(section: String, title: String, low: float, high: float, value: float, step: float, action: Callable) -> HSlider:
	var row := HBoxContainer.new();section_box(section).add_child(row)
	if not title.is_empty():
		var label := Label.new();label.text=title;label.custom_minimum_size.x=110;row.add_child(label)
	var widget := HSlider.new();widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;widget.custom_minimum_size=Vector2(70,24);widget.min_value=low;widget.max_value=high;widget.step=step;widget.value=value;widget.value_changed.connect(action);row.add_child(widget)
	var text := Label.new();text.text=String.num(value,4);text.mouse_filter=Control.MOUSE_FILTER_IGNORE;widget.add_child(text);text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);text.position.x=5
	widget.value_changed.connect(func(current):text.text=String.num(current,4))
	widget.set_meta("value_label",text);native_item(widget,section,title,"SLIDER")
	if title=="Tree depth":tag_action(widget,"tree_depth")
	return widget

func paired_grid(section: String) -> GridContainer:
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",4);grid.add_theme_constant_override("v_separation",3);section_box(section).add_child(grid);return grid

func set_slider_value(slider: HSlider, value: float) -> void:
	if not is_instance_valid(slider):return
	slider.set_value_no_signal(value)
	if slider.has_meta("value_label"): slider.get_meta("value_label").text=String.num(slider.value,4)

func update_key_controls(count: int) -> void:
	key_index=int(frame.get("key",-1))
	var key: HSlider=fields.get("key")
	if is_instance_valid(key):
		# Bounds can clamp and emit changes; synchronization is never a Load key.
		var blocked := key.is_blocking_signals();key.set_block_signals(true)
		key.min_value=-1 if count==0 else 0;key.max_value=-1 if count==0 else count-1
		key.editable=count>0;set_slider_value(key,float(key_index));key_index=int(key.value)
		key.set_block_signals(blocked);key.set_meta("viewer_capability_disabled",count==0)
	for name in ["key_load","key_save"]:
		if _has_field(name):fields[name].disabled=count==0;fields[name].set_meta("viewer_capability_disabled",count==0)

func native_item(widget: Control, section: String, title: String, kind: String, shortcut := "") -> void:
	if not sections.has(section): return
	if widget is Button or widget is Label: widget.clip_text=true
	widget.set_meta("mujoco_section",section);widget.set_meta("mujoco_name",title);widget.set_meta("mujoco_item",kind)
	if not shortcut.is_empty(): widget.set_meta("mujoco_shortcut",shortcut);widget.tooltip_text=shortcut

func get_native_ui_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for panel in [left_panel,right_panel]:
		if not is_instance_valid(panel):continue
		for control in panel.find_children("*","Control",true,false):
			if control.has_meta("mujoco_item"):
				result.append({"section":control.get_meta("mujoco_section"),"name":control.get_meta("mujoco_name"),"item":control.get_meta("mujoco_item"),"shortcut":control.get_meta("mujoco_shortcut",""),"disabled":bool(control.get_meta("mujoco_disabled")) if control.has_meta("mujoco_disabled") else bool(control.get("disabled")) if control is BaseButton else not bool(control.get("editable")) if control is Range or control is LineEdit else false,"reason":control.tooltip_text,"path":str(control.get_path())})
	return result

func retire_model_controls() -> void:
	# These callbacks capture model-local integer IDs. End their input lifetime
	# before the viewer can stamp commands with a replacement world's revision.
	var roots := {}
	var retired_keys: Array=[]
	for key in fields.keys():
		var name := str(key)
		if not name.begins_with("joint:") and not name.begins_with("control:") and not name.begins_with("equality:"): continue
		var widget: Object=fields[key]
		if is_instance_valid(widget) and widget is Node:
			widget.set_block_signals(true)
			if widget is Range: widget.editable=false
			elif widget is BaseButton: widget.disabled=true
			var parts := name.split(":")
			var base := parts[0]+":"+parts[1]
			var root: Node=fields.get(base+":row",widget)
			if not is_instance_valid(root): root=widget
			roots[root.get_instance_id()]=root
		retired_keys.append(key)
	for key in retired_keys: fields.erase(key)
	for root in roots.values():
		if root.is_inside_tree():
			var focus: Control=root.get_viewport().gui_get_focus_owner()
			if is_instance_valid(focus) and (root==focus or root.is_ancestor_of(focus)): focus.release_focus()
		if root is CanvasItem: root.hide()
		if root.get_parent(): root.get_parent().remove_child(root)
		root.queue_free()

func retire_catalog_controls() -> void:
	# Fixed-camera/image-sensor callbacks also carry model-local IDs. Retire
	# only presenter-owned descendants; the editable slots and authored content stay.
	for title in ["Rendering","Visualization","Group enable"]:subsection_targets.erase(title)
	for root in _catalog_roots.values():
		if not is_instance_valid(root):continue
		var nodes: Array[Node]=[root]
		while not nodes.is_empty():
			var node: Node=nodes.pop_back();nodes.append_array(node.get_children(true))
			if node is Window:node.hide()
			elif node is Control:
				node.set_block_signals(true)
				if node.has_focus():node.release_focus()
				if node is BaseButton:node.disabled=true
				elif node is Slider or node is SpinBox or node is LineEdit:node.editable=false
		root.hide()
		if root.get_parent():root.get_parent().remove_child(root)
		root.queue_free()
	_catalog_roots.clear()
	for key in _catalog_fields:fields.erase(key)
	_catalog_fields.clear()

func build_catalog() -> void:
	managed_popups=managed_popups.filter(func(popup):return is_instance_valid(popup))
	retire_catalog_controls()
	var authored_fields := fields.keys()
	for title in ["Rendering","Visualization","Group enable"]:
		if not sections.has(title):continue
		# Rebuild only presenter-owned rows inside the authored layout slot.
		# Theme, authored children and surrounding containers remain untouched.
		var root := VBoxContainer.new();root.name="ModelOptions";root.add_theme_constant_override("separation",2)
		var slot: VBoxContainer=_catalog_slots.get(title,sections[title].box)
		slot.add_child(root);_catalog_roots[title]=root
	if sections.has("Rendering"):
		fields.camera_choice=select_option("Rendering","Camera",catalog.get("cameras",[]),0,func(id):send({"action":"camera","id":id}))
		for kind in ["labels","frames"]:
			var action := "label" if kind=="labels" else "frame"
			fields[action+"_choice"]=select_option("Rendering",kind.capitalize().trim_suffix("s"),catalog.get(kind,[]),0,func(value):send({"action":action,"value":value}))
		button("Rendering","Copy camera",func():send({"action":"copy_camera"}))
		for kind in ["vis","rnd"]:
			subsection("Rendering","Model Elements" if kind=="vis" else "OpenGL Effects")
			var flag_grid := paired_grid("Rendering")
			for definition in catalog.get(kind,[]):
				var action: String=kind; var id: int=definition.id
				var widget := check("Rendering",definition.name,definition.value,func(value):
					if not updating: send({"action":action,"id":id,"value":value}),flag_grid)
				widget.disabled=not definition.supported;widget.tooltip_text=definition.reason;widget.set_meta("mujoco_shortcut",str(definition.shortcut));fields["%s:%d" % [action,id]]=widget
			if kind=="vis":
				fields.tree_depth=numeric_slider("Rendering","Tree depth",0,20,0,1,func(value):
					if not updating: send({"action":"tree_depth","value":int(value)}))
				var flex := numeric_slider("Rendering","Flex layer",0,10,0,1,func(_value):pass);flex.editable=false;flex.tooltip_text="Current rigid model has no flex."
				var sensor_choices: Array=["All"]
				for sensor in catalog.get("image_sensors",[]): sensor_choices.append(sensor.name)
				if sensor_choices.size()>1:
					fields.image_sensor=select_option("Rendering","Sensor",sensor_choices,0,func(id):
						_emit("image_sensor",{"id":-1 if id==0 else int(catalog.image_sensors[id-1].id)}))

	for definition in (catalog.get("groups",[]) if sections.has("Group enable") else []):
		subsection("Group enable",str(definition.name).capitalize()+" groups")
		var group_grid := paired_grid("Group enable")
		for i in 6:
			var group_name: String=definition.name; var index: int=i
			var widget := check("Group enable","%s %d" % [group_name.capitalize(),i],true,func(value):
				if not updating: send({"action":"group","name":group_name,"id":index,"value":value}),group_grid)
			widget.disabled=not definition.supported;widget.tooltip_text="Current supported model has no flex/skin" if widget.disabled else "";fields["group:%s:%d" % [group_name,i]]=widget
			if group_name in ["geom","site"]: widget.set_meta("mujoco_shortcut",("Shift+" if group_name=="site" else "")+str(i))
	var previous_group := ""
	for definition in (catalog.get("visual",[]) if sections.has("Visualization") else []):
		var field_name: String=definition.name;var pieces := field_name.split(".",false)
		var group: String=SimulateUI.visual_section(field_name)
		if group!=previous_group:
			if previous_group=="Free Camera": button("Visualization","Align",func():send({"action":"align"}))
			subsection("Visualization",group,not group in ["Scale","RGBA"]);previous_group=group
		var label_text: String=SimulateUI.VISUAL_NAMES.get(field_name,pieces[-1].capitalize())
		if definition.integer and definition.values.size()==1:
			var options: Array=["No","Yes"] if field_name=="global.orthographic" else ["Box","Ellipsoid"] if field_name=="global.ellipsoidinertia" else ["Off","On"]
			var widget := radio_option("Visualization",label_text,options,int(definition.values[0]),func(value):send({"action":"visual","name":field_name,"values":[value]}))
			tag_action(widget,"visual",{"name":field_name})
			widget.set_meta("mujoco_disabled",not definition.get("supported",true));widget.tooltip_text=definition.get("reason","")
			for child in widget.get_children(): child.disabled=not definition.get("supported",true);child.tooltip_text=definition.get("reason","")
		else:
			var row := VBoxContainer.new();section_box("Visualization").add_child(row)
			var label := Label.new();label.text=label_text;row.add_child(label)
			var edit := LineEdit.new();edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(edit);native_item(edit,"Visualization",label_text,"EDIT");tag_action(edit,"visual",{"name":field_name})
			var texts := PackedStringArray()
			for value in definition.values: texts.append(String.num(value,6))
			edit.text=", ".join(texts);edit.editable=definition.get("supported",true);edit.tooltip_text=definition.get("reason","")
			edit.text_submitted.connect(func(text):
				var parsed: Array=[]
				for part in text.replace(","," ").split(" ",false):
					if not part.is_valid_float(): feedback="Invalid numeric visual parameter";return
					parsed.append(float(part))
				send({"action":"visual","name":field_name,"values":parsed}))
	var count: int=catalog.get("nkey",0)
	update_key_controls(count)
	for name in ["key","key_load","key_save"]:
		if _has_field(name):fields[name].tooltip_text=catalog.get("keyframe_reason","Current compiled model has no keyframes.") if count==0 else "Session keyframes; no editor/design writeback."
	if _has_field("file:save_xml"):
		var save_xml: BaseButton=fields["file:save_xml"]
		save_xml.set_meta("viewer_capability_disabled",not catalog.get("save_xml_supported",true));save_xml.disabled=not catalog.get("save_xml_supported",true);save_xml.tooltip_text="Committed XML source is unavailable." if save_xml.disabled else ""
	for key in fields:
		if not authored_fields.has(key):_catalog_fields.append(key)
	refresh_help()

func sync_numeric(section: String, rows: Array, action: String) -> void:
	if not sections.has(section):return
	var alive := {}
	for data in rows:
		var key := "%s:%d" % [action,data.id]; alive[key]=true
		var widget: SpinBox=fields.get(key)
		var slider: HSlider=fields.get(key+":slider")
		if not is_instance_valid(widget):
			var row := VBoxContainer.new();sections[section].box.add_child(row)
			var caption := Label.new();caption.clip_text=true;row.add_child(caption);fields[key+":label"]=caption
			var line := HBoxContainer.new();row.add_child(line)
			slider=HSlider.new();slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(slider);fields[key+":slider"]=slider
			widget=SpinBox.new();widget.custom_minimum_size.x=100;widget.step=.001;widget.update_on_text_changed=false;line.add_child(widget);fields[key]=widget;fields[key+":row"]=row
			var id: int=data.id;var command: String=action;var spin: SpinBox=widget
			native_item(slider,section,str(data.name),"SLIDERNUM")
			widget.value_changed.connect(func(value):
				if not updating: send({"action":command,"id":id,"value":value}))
			slider.value_changed.connect(func(value):
				if not updating: spin.value=value)
		fields[key+":label"].text=str(data.name)
		widget.editable=not data.disabled;widget.allow_greater=not data.limited;widget.allow_lesser=not data.limited;widget.min_value=data.min;widget.max_value=data.max
		slider.min_value=data.min;slider.max_value=data.max;slider.step=.001;slider.editable=not data.disabled
		widget.tooltip_text=("Pause simulation to edit scalar joints." if action=="joint" else "Actuator group is disabled by the Physics design.") if data.disabled else ""
		slider.tooltip_text=widget.tooltip_text
		if not widget.get_line_edit().has_focus(): widget.set_value_no_signal(data.value)
		slider.set_value_no_signal(data.value)
	for key in fields.keys():
		if str(key).begins_with(action+":") and str(key).count(":")==1 and not alive.has(key):
			if is_instance_valid(fields.get(key+":row")): fields[key+":row"].queue_free()
			for suffix in ["",":row",":slider",":label"]: fields.erase(key+suffix)

func update_info() -> void:
	if frame.is_empty(): return
	updating=true
	if is_instance_valid(left_panel) and left_panel.visible or is_instance_valid(right_panel) and right_panel.visible:
		sync_numeric("Joint",details.get("joints",[]),"joint"); sync_numeric("Control",details.get("controls",[]),"control")
		var active_equalities := {}
		for data in (details.get("equalities",[]) if sections.has("Equality") else []):
			var key := "equality:%d" % data.id
			active_equalities[key]=true
			var widget: CheckBox=fields.get(key)
			if not is_instance_valid(widget):
				var id: int=data.id
				widget=check("Equality",data.name,data.value,func(value):
					if not updating: send({"action":"equality","id":id,"value":value}))
				fields[key]=widget
			widget.text=data.name
			widget.set_pressed_no_signal(data.value)
		for key in fields.keys():
			if str(key).begins_with("equality:") and not active_equalities.has(key):
				if is_instance_valid(fields[key]): fields[key].queue_free()
				fields.erase(key)
		if is_instance_valid(watch_label):watch_label.text="%s[%d] = %s" % [watch_field,watch_index,str(details.get("watch_value",details.get("watch_error","等待数据")))]
		if details.has("physics"): update_physics_inspector(details.physics)
		update_logging()
	if _has_field("fullscreen"):fields.fullscreen.set_pressed_no_signal(get_tree().root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN])
	if _has_field("vsync"):fields.vsync.set_pressed_no_signal(DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED)
	if _has_field("run"):fields.run.select(0 if frame.paused else 1)
	if _has_field("history"):
		fields.history.min_value=-maxi(0,int(frame.history_count)-1);fields.history.max_value=0;set_slider_value(fields.history,frame.history_offset)
	if _has_field("key"):set_slider_value(fields.key,int(frame.get("key",key_index)));key_index=int(fields.key.value)
	set_slider_value(fields.get("threads"),frame.get("num_threads",0))
	set_slider_value(fields.get("noise_std"),frame.get("noise_std",0));set_slider_value(fields.get("noise_rate"),frame.get("noise_rate",0))
	if _has_field("pause_update"):fields.pause_update.set_pressed_no_signal(frame.get("pause_update",false))
	refresh_native_info()
	if is_instance_valid(run_label):run_label.text=("PAUSE"+(" (%d)" % frame.history_offset if int(frame.history_offset)<0 else "")) if frame.paused else ""
	if is_instance_valid(speed_label):speed_label.text="%.3f%%" % frame.speed_percent if absf(float(frame.speed_percent)-100)>.001 else ""
	_layout_status_labels()
	var settings: Dictionary=frame.get("settings",{})
	if is_instance_valid(fields.get("tree_depth")): set_slider_value(fields.tree_depth,settings.get("bvh_depth",0))
	if is_instance_valid(fields.get("camera_choice")):
		var mode: int=frame.camera.get("type",0)
		fields.camera_choice.select(2+int(frame.camera.fixed_id) if mode==2 else 1 if mode==1 else 0)
	for action in ["frame","label"]:
		if is_instance_valid(fields.get(action+"_choice")) and fields[action+"_choice"].item_count>0: fields[action+"_choice"].select(settings.get(action,0))
	for action in ["vis","rnd"]:
		var values: Array=settings.get(action,[])
		for i in values.size():
			var widget: CheckBox=fields.get("%s:%d" % [action,i])
			if is_instance_valid(widget): widget.set_pressed_no_signal(values[i])
	for group_name in settings.get("groups",{}):
		for i in 6:
			var widget: CheckBox=fields.get("group:%s:%d" % [group_name,i])
			if is_instance_valid(widget): widget.set_pressed_no_signal(settings.groups[group_name][i])
	updating=false
	var profiler: Dictionary=frame.get("stats",{}).get("profiler",{})
	if _overlay_visible("profiler"):
		# Each official figure is optional in an authored scene. Keep its fixed
		# category index even when other plots were removed; never fill holes.
		var counts_plot := _profiler_plot(0);var costs_plot := _profiler_plot(1)
		var timing_plot := _profiler_plot(2);var sizes_plot := _profiler_plot(3)
		var solver: int=details.get("physics",{}).get("solver",2)
		var counts: Array=["total","active","changed","evals","updates"].slice(0,3 if solver==0 else 4 if solver==1 else 5)
		var costs: Array=["improvement"] if solver==0 else ["improvement","gradient","lineslope"]
		if is_instance_valid(counts_plot) and counts_plot.captions!=counts:counts_plot.captions=counts;counts_plot.queue_redraw()
		if is_instance_valid(costs_plot) and costs_plot.captions!=costs:costs_plot.captions=costs;costs_plot.queue_redraw()
		if not profiler.is_empty() and float(profiler.get("time",-1))!=last_profiler_time:
			last_profiler_time=float(profiler.time)
			if is_instance_valid(counts_plot):counts_plot.set_series(profiler.get("counts",[]))
			if is_instance_valid(costs_plot):costs_plot.set_series(profiler.get("costs",[]))
			if is_instance_valid(timing_plot):
				timing_plot.title="CPU time (msec)" if profiler.get("timing_available",false) else "CPU timing unavailable"
				if profiler.get("timing_available",false):timing_plot.append_sample(profiler.get("timing_ms",[]))
			if is_instance_valid(sizes_plot):sizes_plot.append_sample(profiler.get("sizes",[]))
	if _overlay_visible("sensors"):update_sensors()

func build_physics_row(item: Array) -> void:
	var key: String=item[1]
	if SimulateUI.PHYSICS_ENUMS.has(key):
		var choice := select_option("Physics",item[0],SimulateUI.PHYSICS_ENUMS[key],0,func(_value):pass);choice.disabled=true;choice.tooltip_text="Physics design is read-only at runtime. Edit in Godot editor.";fields.physics_rows[key]=choice
	else:
		var row := VBoxContainer.new();section_box("Physics").add_child(row)
		var label := Label.new();label.text=item[0];row.add_child(label)
		var edit := LineEdit.new();edit.editable=false;edit.tooltip_text="Physics design is read-only at runtime. Edit in Godot editor.";row.add_child(edit);native_item(edit,"Physics",item[0],"EDIT");fields.physics_rows[key]=edit

func update_physics_inspector(values: Dictionary) -> void:
	if not sections.has("Physics"):return
	if not fields.has("physics_rows"):
		fields.physics_rows={}
		for group in SimulateUI.PHYSICS_GROUPS:
			if group[0]=="Contact Override": continue
			if not str(group[0]).is_empty(): subsection("Physics",group[0],group[0]=="Physical Parameters")
			for item in group[1]: build_physics_row(item)
		for kind in ["disable","enable"]:
			subsection("Physics",kind.capitalize()+" Flags",false)
			var names: Array=catalog.get("physics_"+kind+"_names",[])
			for index in names.size():
				var check_box := check("Physics",names[index],false,func(_value):pass);check_box.disabled=true;check_box.tooltip_text="Physics design is read-only at runtime.";fields.physics_rows[kind+":"+str(index)]=check_box
		for group in SimulateUI.PHYSICS_GROUPS:
			if group[0]=="Contact Override":
				subsection("Physics",group[0])
				for item in group[1]: build_physics_row(item)
		subsection("Physics","Actuator Group Enable")
		for index in 6:
			var check_box := check("Physics","Act Group %d" % index,true,func(_value):pass);check_box.disabled=true;check_box.tooltip_text="Actuator design groups are read-only at runtime.";fields.physics_rows["actuator:"+str(index)]=check_box
	for key in fields.physics_rows:
		var widget: Control=fields.physics_rows[key]
		if str(key).contains(":"):
			var parts := str(key).split(":");var bit := 1<<int(parts[1]);var raw: int=values.get("disableactuator" if parts[0]=="actuator" else str(parts[0])+"flags",0)
			widget.set_pressed_no_signal(not bool(raw&bit) if parts[0]=="actuator" else bool(raw&bit))
		elif widget is OptionButton: widget.select(int(values.get(key,0)))
		else: widget.text=str(values.get(key,"No data"))

func update_logging() -> void:
	if not sections.has("Logging"):return
	if not details.has("logging"): return
	var log: Dictionary=details.logging
	if not fields.has("log_console"):
		fields.log_console=check("Logging","Console",log.console,func(value):
			if not updating: send({"action":"logging","console":value}))
		fields.log_file=check("Logging","File",log.file,func(value):
			if not updating:
				var folder := output_directory(); send({"action":"logging","file":value,"path":folder+"/MUJOCO_LOG.TXT"}))
		subsection("Logging","Info topics")
		for i in log.topic_names.size():
			var index: int=i
			fields["topic:%d" % i]=check("Logging",log.topic_names[i],bool(log.topics&(1<<i)),func(value):
				if not updating:
					var topics: int=details.logging.topics
					send({"action":"logging","topics":topics|(1<<index) if value else topics&~(1<<index)}))
	fields.log_console.set_pressed_no_signal(log.console); fields.log_file.set_pressed_no_signal(log.file)
	for i in log.topic_names.size(): fields["topic:%d" % i].set_pressed_no_signal(bool(log.topics&(1<<i)))

func clear_sensor_images() -> void:
	sensor_versions.clear()
	if is_instance_valid(sensor_images):
		for child in sensor_images.get_children(): child.queue_free()
	for key in fields.keys():
		if str(key).begins_with("sensor_image:") or key=="sensor_note": fields.erase(key)

func update_sensors() -> void:
	var values := PackedFloat64Array(); var names: Array=[]; var images := 0
	for sensor in details.get("sensors",[]):
		if not sensor.image:
			for value in sensor.get("values",[]): values.append(value)
			names.append(sensor.name); continue
		images+=1
		if not is_instance_valid(sensor_images):continue
		if selected_image_sensor>=0 and sensor.id!=selected_image_sensor: continue
		if not sensor.has("rgb") or sensor_versions.get(sensor.id)==sensor.version: continue
		sensor_versions[sensor.id]=sensor.version
		var key := "sensor_image:%d" % sensor.id
		var texture: TextureRect=fields.get(key)
		if not is_instance_valid(texture):
			var label := Label.new();label.text=sensor.name;label.add_theme_font_size_override("font_size",12);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;sensor_images.add_child(label)
			texture=TextureRect.new(); texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; texture.custom_minimum_size=Vector2(80,60); sensor_images.add_child(texture); fields[key]=texture
		texture.texture=ImageTexture.create_from_image(Image.create_from_data(sensor.width,sensor.height,false,Image.FORMAT_RGB8,sensor.rgb))
	if is_instance_valid(sensor_plot):
		sensor_plot.title="Sensor data / cutoff" if not values.is_empty() else "No numeric data"
		sensor_plot.set_series([values]);sensor_plot.captions=names
	if not is_instance_valid(sensor_images):return
	if not fields.has("sensor_note"):
		fields.sensor_note=Label.new();fields.sensor_note.add_theme_font_size_override("font_size",11);fields.sensor_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;fields.sensor_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sensor_images.add_child(fields.sensor_note)
	fields.sensor_note.text="无图像传感器数据\n需模型提供生产数据" if images==0 or sensor_versions.is_empty() else "用户图像传感器 · 当前生产数据"

func status_row_end() -> float:
	var end := 42.0
	for label in [run_label,speed_label]:
		if is_instance_valid(label) and label.visible and not label.text.is_empty():
			end=maxf(end,label.position.y-render_rect.position.y+maxf(label.size.y,label.get_combined_minimum_size().y)+8)
	return end

func refresh_feedback() -> void:
	if not is_instance_valid(feedback_label): return
	feedback_label.text=feedback;feedback_label.visible=not feedback.is_empty() and Time.get_ticks_msec()<feedback_deadline
	var available: float=render_rect.size.x*(.75 if _overlay_visible("profiler") else 1.0)
	feedback_label.size.x=maxf(1,available-16)
	var y := status_row_end()
	feedback_label.position=render_rect.position+Vector2(8,y)

func refresh_native_info() -> void:
	if not is_instance_valid(windows.get("info")) or not is_instance_valid(fields.get("info_label")) or frame.is_empty():return
	var stats: Dictionary=frame.get("stats",{})
	var profiler: Dictionary=stats.get("profiler",{})
	var lines := PackedStringArray(["MuJoCo Info","Time       %.3f" % frame.time,"Size       %d contacts · %d constraints" % [stats.get("contacts",0),stats.get("constraints",0)]])
	if stats.get("timing_available",false): lines.append("CPU        %.3f ms" % stats.get("cpu_ms",0))
	lines.append("Solver     %.2f · %d iterations" % [stats.get("solver_log_error",0),stats.get("solver_iterations",0)])
	lines.append("FPS        %.1f" % renderer_fps)
	lines.append("Memory     %.1f / %.1f MiB" % [stats.get("arena_used_bytes",0)/1048576.0,stats.get("arena_bytes",0)/1048576.0])
	if stats.get("energy_enabled",false): lines.append("Energy     %.5f" % stats.energy)
	if stats.get("fwdinv_enabled",false):
		var values := PackedStringArray()
		for value in stats.fwdinv: values.append("%.1f" % (log(maxf(1e-15,float(value)))/log(10.0)))
		lines.append("FwdInv log10  "+" ".join(values))
	if stats.get("islands_enabled",false): lines.append("Islands    %d" % stats.get("islands",0))
	fields.info_label.text="\n".join(lines)
	windows.info.size=fields.info_label.get_combined_minimum_size()+Vector2(12,8)
	windows.info.position=render_rect.position+Vector2(8,maxf(4,render_rect.size.y-windows.info.size.y-8))

func panel_hint(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if is_instance_valid(help_hint):help_hint.visible=event.pressed
		for hints in shortcut_hints: hints.visible=event.pressed and is_instance_valid(hints.panel) and hints.panel.visible;hints.queue_redraw()
