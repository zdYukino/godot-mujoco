class_name MjRuntimeViewer
extends Node
signal world_changed(world: Node3D)
signal viewer_command_finished(result: Dictionary)
var command_request := 0
var last_error := ""
var last_result := {}
## One authoritative MuJoCo interaction/UI controller for both renderers.
const Keys = preload("shortcuts.gd")
const ViewerWindow = preload("viewer_window.gd")
const Plot = preload("plot.gd")
const SystemPerformance = preload("performance.gd")
const SimulateUI = preload("simulate_ui.gd")
const Radio = preload("simulate_radio.gd")
const ShortcutHints = preload("shortcut_hints.gd")
var runtime_world: Node3D
var environment_host: Node
var source_viewport: Viewport
var camera: Camera3D
var frame: Dictionary = {}
var catalog: Dictionary = {}
var details: Dictionary = {}
var known_revision := -1
var seeded_revision := -1
var presented_revision := -1
var presented_frame_id := 0
var sequence := 0
var pending := {}
var layer: CanvasLayer
var scene_input: Control
var controls: Window
var windows := {}
var sections := {}
var extras_sections := {}
var subsection_targets := {}
var left_panel: ScrollContainer
var right_panel: ScrollContainer
var outer_rect := Rect2()
var render_rect := Rect2()
var layout_generation := 0
var presented_layout := -1
var applied_layout := -1
var frames_retiring := false
var frame_retire_request := 0
var retire_target := {}
var info_enabled := false
var ui_spacing := 0
var ui_color := 0
var ui_font := 1
var native_theme: Theme
var authored_seed := {}
var key_index := -1
var selected_image_sensor := -1
var run_label: Label
var speed_label: Label
var shortcut_hints: Array[Control] = []
var managed_popups: Array[Window] = []
var feedback_label: Label
var feedback_deadline := 0
var status: Label
var hud: Label
var help_label: Label
var profiler_plots: Array = []
var sensor_plot: Control
var sensor_images: VBoxContainer
var sensor_versions := {}
var fields := {}
var metrics := {"fps":true,"cpu":false,"ram":false,"gpu":false,"vram":false,"timing":false}
var overlay_enabled := true
var metric_checks := {}
var overlay_check: CheckBox
var output_path := "user://mujoco_viewer"
var performance_source := SystemPerformance.new()
var system_metrics := {}
var next_info := 0
var next_system := 0
var fps_at := 0
var fps_count := 0
var renderer_fps := 0.0
var host_fps := 0.0
var last_native_frame := -1
var last_backend := ""
var inspect_due := true
var watch_field := "qpos"
var watch_index := 0
var watch_label: Label
var feedback := "":
	set(value):
		feedback=value;feedback_deadline=Time.get_ticks_msec()+8000
		refresh_feedback()
var dragging := false
var dragging_perturb := false
var logical_button := 0
var last_click := 0
var last_click_button := 0
var last_global_event := 0
var updating := false
var attached := false
var preference_queue: Array[Dictionary] = []
var config := ConfigFile.new()
var config_path := ""
var extensions := {}
var extension_help := {}
var help_hint: Label
var rebuilding := false
var next_preference_save := 0
var display_preferences_pending := {}
var last_profiler_time := -1.0
var geometry_targets := {}
var reload_source_path := ""
var reload_world_path := NodePath(".")
var owns_root_disable := false
var saved_root_disable := false
var camera_to_restore := {}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	name="MuJoCoRuntimeViewer"
	config_path="user://mujoco_viewer_%s.cfg" % ProjectSettings.globalize_path("res://").sha256_text().substr(0,12)
	config.load(config_path)
	# v2 separates the old mixed F2/performance settings. Never restore a mixed Info consumer.
	overlay_enabled=config.get_value("godot_ui","performance_overlay",config.get_value("ui","overlay",true))
	info_enabled=config.get_value("simulate_ui","info",false)
	ui_spacing=config.get_value("simulate_ui","spacing",0)
	ui_color=config.get_value("simulate_ui","color",0)
	ui_font=config.get_value("simulate_ui","font",1)
	for key in metrics: metrics[key]=config.get_value("metrics",key,metrics[key])
	output_path=config.get_value("ui","output",output_path)
	layer=CanvasLayer.new(); layer.layer=80; add_child(layer)
	scene_input=Control.new(); scene_input.name="SimulationInput"; scene_input.mouse_filter=Control.MOUSE_FILTER_STOP; layer.add_child(scene_input)
	scene_input.gui_input.connect(scene_event)
	left_panel=make_sidebar("MuJoCoLeftPanel",SimulateUI.LEFT)
	right_panel=make_sidebar("MuJoCoRightPanel",SimulateUI.RIGHT)
	left_panel.visible=config.get_value("simulate_ui","left",true)
	right_panel.visible=config.get_value("simulate_ui","right",true)
	apply_ui_theme()
	hud=Label.new(); hud.name="GodotPerformanceOverlay"; hud.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(hud)
	hud.add_theme_color_override("font_shadow_color",Color.BLACK); hud.add_theme_constant_override("shadow_offset_x",1); hud.add_theme_constant_override("shadow_offset_y",1)
	controls=make_window("Godot 附加功能 · F11",Vector2i(560,700)); controls.close_requested.connect(func():set_controls_visible(false))
	var scroll := ScrollContainer.new(); scroll.follow_focus=true; controls.add_child(scroll); scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var contents := VBoxContainer.new(); contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(contents)
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; contents.add_child(status)
	for title in ["Renderer","Performance","Tools","Examples"]: add_section(contents,title,controls,true)
	var help := make_overlay("help"); windows.help=help
	var help_box := VBoxContainer.new();help_box.mouse_filter=Control.MOUSE_FILTER_IGNORE;help.add_child(help_box);help_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var help_rows := HBoxContainer.new();help_rows.mouse_filter=Control.MOUSE_FILTER_IGNORE;help_rows.add_theme_constant_override("separation",12);help_box.add_child(help_rows)
	for column in ["help_actions","help_shortcuts"]:
		var label := Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",12);help_rows.add_child(label);fields[column]=label
	help_label=Label.new();help_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;help_label.add_theme_font_size_override("font_size",12);help_box.add_child(help_label)
	var info := make_overlay("info"); windows.info=info; info.visible=info_enabled
	var info_label := Label.new(); info_label.name="MuJoCoInfo"; info_label.mouse_filter=Control.MOUSE_FILTER_IGNORE; info.add_child(info_label); fields.info_label=info_label
	var profiler := make_overlay("profiler"); windows.profiler=profiler
	var plots := VBoxContainer.new(); plots.mouse_filter=Control.MOUSE_FILTER_IGNORE; plots.add_theme_constant_override("separation",0); profiler.add_child(plots); plots.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for title in SimulateUI.PROFILER_TITLES:
		var plot := Plot.new(); plot.title=title; plot.custom_minimum_size=Vector2(100,60); plot.size_flags_horizontal=Control.SIZE_EXPAND_FILL; plot.size_flags_vertical=Control.SIZE_EXPAND_FILL; plots.add_child(plot); profiler_plots.append(plot)
	profiler_plots[0].captions=["total","active","changed","evals","updates"]
	profiler_plots[1].captions=["improvement","gradient","lineslope"]
	profiler_plots[2].captions=["total","collision","prepare","solve","other"]
	profiler_plots[3].captions=["dof","body","constraint","sqrt(nnz)","contact","iteration"]
	var sensors := make_overlay("sensors"); windows.sensors=sensors
	var sensor_box := VBoxContainer.new(); sensor_box.mouse_filter=Control.MOUSE_FILTER_IGNORE; sensors.add_child(sensor_box); sensor_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sensor_plot=Plot.new(); sensor_plot.title="Sensor data"; sensor_plot.custom_minimum_size=Vector2(100,100); sensor_plot.size_flags_vertical=Control.SIZE_EXPAND_FILL; sensor_box.add_child(sensor_plot)
	sensor_plot.bars=true
	sensor_images=VBoxContainer.new(); sensor_images.mouse_filter=Control.MOUSE_FILTER_IGNORE; sensor_box.add_child(sensor_images)
	build_static_controls()
	feedback_label=Label.new();feedback_label.name="MuJoCoFeedback";feedback_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;feedback_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;feedback_label.add_theme_color_override("font_color",Color(1,.85,.5));feedback_label.add_theme_color_override("font_shadow_color",Color.BLACK);feedback_label.add_theme_constant_override("shadow_offset_x",1);feedback_label.add_theme_constant_override("shadow_offset_y",1);layer.add_child(feedback_label);feedback_label.visible=false
	run_label=Label.new();run_label.add_theme_font_size_override("font_size",28);run_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(run_label)
	speed_label=Label.new();speed_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;layer.add_child(speed_label)
	refresh_help()
	help_hint=Label.new(); help_hint.text=""; help_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(help_hint); help_hint.visible=false
	for panel in [left_panel,right_panel]:
		var hints := ShortcutHints.new();hints.panel=panel;layer.add_child(hints);shortcut_hints.append(hints)
	controls.window_input.connect(panel_hint)
	if is_instance_valid(runtime_world): bind_world(runtime_world)
	RenderingServer.frame_post_draw.connect(after_draw)
	fps_at=Time.get_ticks_msec()
	get_tree().node_added.connect(owned_window_added)
	# Include internal controls once: LineEdit/TextEdit and SpinBox menus are
	# native Godot children, and may already exist before this viewer is ready.
	var nodes: Array[Node]=get_children(true)
	while not nodes.is_empty():
		var node: Node=nodes.pop_back()
		owned_window_added(node)
		nodes.append_array(node.get_children(true))

func owned_window_added(node: Node) -> void:
	# All ordinary scene nodes return immediately. Menus created lazily or in
	# dynamic extensions are watched only while they belong to this viewer.
	if node is Window and node!=controls and is_ancestor_of(node): manage_popup(node as Window)
func manage_popup(popup: Window) -> void:
	if popup==controls or not is_ancestor_of(popup): return
	managed_popups=managed_popups.filter(func(value):return is_instance_valid(value))
	if not managed_popups.has(popup): managed_popups.append(popup)
	var input := owned_popup_input.bind(popup)
	if not popup.window_input.is_connected(input): popup.window_input.connect(input)
	var leaving := forget_owned_popup.bind(popup)
	if not popup.tree_exiting.is_connected(leaving): popup.tree_exiting.connect(leaving)
func forget_owned_popup(popup: Window) -> void:
	managed_popups.erase(popup)
func owned_popup_input(event: InputEvent, popup: Window) -> void:
	# A control can be reparented out of an extension. Its former callback
	# must never intercept input in an unrelated runtime/editor window.
	if is_inside_tree() and is_instance_valid(popup) and is_ancestor_of(popup): global_input(event,popup)

func make_window(title: String, initial_size: Vector2i) -> Window:
	get_viewport().gui_embed_subwindows=true
	var panel := ViewerWindow.new(); panel.viewer=self; panel.title=title; panel.force_native=false; panel.unresizable=false; panel.min_size=Vector2i(360,240); panel.size=initial_size; panel.visible=false
	add_child(panel); panel.position=Vector2i(40,50)
	panel.close_requested.connect(func():panel.hide();save_preferences())
	return panel

func make_sidebar(panel_name: String, titles: Array) -> ScrollContainer:
	var panel := ScrollContainer.new(); panel.name=panel_name; panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; panel.follow_focus=true
	layer.add_child(panel)
	var margin := MarginContainer.new(); margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL; margin.add_theme_constant_override("margin_left",5); margin.add_theme_constant_override("margin_right",5); panel.add_child(margin)
	var contents := VBoxContainer.new(); contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL; contents.add_theme_constant_override("separation",3); margin.add_child(contents)
	for title in titles: add_section(contents,title,panel,false)
	panel.gui_input.connect(panel_hint)
	return panel

func add_section(contents: VBoxContainer, title: String, panel: Node, extra: bool) -> void:
	var toggle := Button.new(); toggle.text=title; toggle.name=title.replace(" ","")+"Section"; toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT; toggle.toggle_mode=true;toggle.action_mode=BaseButton.ACTION_MODE_BUTTON_PRESS;toggle.theme_type_variation="MuJoCoSection"
	toggle.button_pressed=extra or title in ["File","Option","Simulation"];toggle.tooltip_text="Alt+"+SimulateUI.SECTION_KEYS.get(title,"")

	contents.add_child(toggle)
	var triangle := Label.new();triangle.text="▼" if toggle.button_pressed else "◀";triangle.mouse_filter=Control.MOUSE_FILTER_IGNORE;toggle.add_child(triangle);triangle.anchor_left=1;triangle.anchor_right=1;triangle.anchor_top=.5;triangle.anchor_bottom=.5;triangle.offset_left=-16;triangle.offset_right=-2;triangle.offset_top=-7;triangle.offset_bottom=7
	var box := VBoxContainer.new(); box.name=title.replace(" ","")+"Contents"; box.add_theme_constant_override("separation",2); box.visible=toggle.button_pressed; contents.add_child(box)
	var map: Dictionary=extras_sections if extra else sections
	map[title]={"button":toggle,"box":box,"panel":panel,"triangle":triangle}
	if not extra: native_item(toggle,title,title,"SECTION",toggle.tooltip_text)
	toggle.toggled.connect(func(value):box.visible=value;triangle.text="▼" if value else "◀";inspect_due=true;cancel_gesture();save_preferences())
	toggle.gui_input.connect(func(event):
		panel_hint(event)
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.double_click:
			sync_section_side.call_deferred(map,panel,toggle)
			inspect_due=true)
func sync_section_side(map: Dictionary, panel: Node, toggle: Button) -> void:
	for section in map.values():
		if section.panel==panel: section.button.set_pressed_no_signal(toggle.button_pressed);section.box.visible=toggle.button_pressed;section.triangle.text="▼" if toggle.button_pressed else "◀"


func make_overlay(key: String) -> Control:
	var panel := Control.new(); panel.name="MuJoCo"+key.capitalize()+"Overlay"; panel.mouse_filter=Control.MOUSE_FILTER_IGNORE; panel.clip_contents=true; panel.visible=false; layer.add_child(panel)
	panel.add_theme_color_override("font_shadow_color",Color.BLACK); panel.add_theme_constant_override("shadow_offset_x",1); panel.add_theme_constant_override("shadow_offset_y",1)
	return panel

func apply_ui_theme() -> void:
	native_theme=SimulateUI.make_theme(ui_color,ui_spacing,ui_font)
	left_panel.theme=native_theme; right_panel.theme=native_theme
	for panel in [left_panel,right_panel]:
		for box in panel.find_children("*","VBoxContainer",true,false): box.add_theme_constant_override("separation",2+4*ui_spacing)
	if attached: update_viewport_rect()

func section_box(section: String) -> VBoxContainer:
	return subsection_targets[section] if subsection_targets.has(section) else sections[section].box if sections.has(section) else extras_sections[section].box
func button(section: String, text: String, action: Callable, target: Control = null) -> Button:
	var widget := Button.new();widget.text=text;widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;widget.pressed.connect(action);(section_box(section) if target==null else target).add_child(widget);native_item(widget,section,text,"BUTTON");return widget
func check(section: String, text: String, value: bool, action: Callable, target: Control = null) -> CheckBox:
	var widget := CheckBox.new();widget.text=text;widget.size_flags_horizontal=Control.SIZE_EXPAND_FILL;widget.button_pressed=value;widget.toggled.connect(action);(section_box(section) if target==null else target).add_child(widget);native_item(widget,section,text,"CHECK");return widget
func explanation(section: String, text: String) -> Label:
	var label := Label.new(); label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; section_box(section).add_child(label); return label
func select_option(section: String, title: String, options: Array, selected: int, action: Callable) -> OptionButton:
	var row := HBoxContainer.new(); section_box(section).add_child(row)
	var label := Label.new(); label.text=title; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var widget := OptionButton.new()
	for value in options: widget.add_item(value)
	widget.custom_minimum_size.x=110;widget.select(selected);widget.item_selected.connect(action);row.add_child(widget);native_item(widget,section,title,"SELECT")
	manage_popup(widget.get_popup())
	return widget
func radio_option(section: String, title: String, options: Array, selected: int, action: Callable) -> Control:
	if not title.is_empty(): explanation(section,title)
	var radio := Radio.new();section_box(section).add_child(radio);radio.setup(options,selected);radio.item_selected.connect(action);native_item(radio,section,title,"RADIO");return radio
func subsection(section: String, title: String, opened := true) -> void:
	var parent: VBoxContainer=sections[section].box
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
	return widget
func paired_grid(section: String) -> GridContainer:
	var grid := GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",4);grid.add_theme_constant_override("v_separation",3);section_box(section).add_child(grid);return grid
func set_slider_value(slider: HSlider, value: float) -> void:
	slider.set_value_no_signal(value)
	if slider.has_meta("value_label"): slider.get_meta("value_label").text=String.num(slider.value,4)

func update_key_controls(count: int) -> void:
	var key: HSlider=fields.key
	# Range bound changes may clamp the value and emit value_changed. This
	# synchronization must never manufacture a user Load key command.
	var blocked := key.is_blocking_signals()
	key.set_block_signals(true)
	key.min_value=-1 if count==0 else 0
	key.max_value=-1 if count==0 else count-1
	key.editable=count>0
	set_slider_value(key,float(frame.get("key",-1)))
	key_index=int(key.value)
	key.set_block_signals(blocked)
	fields.key_load.disabled=count==0;fields.key_save.disabled=count==0

func native_item(widget: Control, section: String, title: String, kind: String, shortcut := "") -> void:
	if not sections.has(section): return
	if widget is Button or widget is Label: widget.clip_text=true
	widget.set_meta("mujoco_section",section);widget.set_meta("mujoco_name",title);widget.set_meta("mujoco_item",kind)
	if not shortcut.is_empty(): widget.set_meta("mujoco_shortcut",shortcut);widget.tooltip_text=shortcut
func get_native_ui_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for panel in [left_panel,right_panel]:
		for control in panel.find_children("*","Control",true,false):
			if control.has_meta("mujoco_item"):
				result.append({"section":control.get_meta("mujoco_section"),"name":control.get_meta("mujoco_name"),"item":control.get_meta("mujoco_item"),"shortcut":control.get_meta("mujoco_shortcut",""),"disabled":bool(control.get_meta("mujoco_disabled")) if control.has_meta("mujoco_disabled") else bool(control.get("disabled")) if control is BaseButton else not bool(control.get("editable")) if control is Range or control is LineEdit else false,"reason":control.tooltip_text,"path":str(control.get_path())})
	return result

func build_static_controls() -> void:
	var file_grid := paired_grid("File")
	for item in SimulateUI.FILE_ACTIONS:
		var action: String=item[1]
		fields["file:"+action]=button("File",item[0],func():perform(action),file_grid)
		fields["file:"+action].set_meta("mujoco_shortcut",{"print_model":"Ctrl+M","print_data":"Ctrl+D","quit":"Ctrl+Q","screenshot":"Ctrl+P"}.get(action,""))
	var option_grid := paired_grid("Option")
	for key in ["help","info","profiler","sensors"]:
		var kind: String=key
		fields["option:"+key]=check("Option",SimulateUI.OVERLAY_LABELS[key],info_enabled if key=="info" else false,func(value):set_auxiliary(kind,value),option_grid)
		fields["option:"+key].set_meta("mujoco_shortcut",{"help":"F1","info":"F2","profiler":"F3","sensors":"F4"}[key])
	fields.pause_update=check("Option","Pause update",false,func(value):
		if not updating: send({"action":"pause_update","enabled":value}),option_grid)
	fields.fullscreen=check("Option","Fullscreen",get_tree().root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN],set_fullscreen,option_grid)
	if is_embedded_game(): fields.fullscreen.disabled=true;fields.fullscreen.tooltip_text="Embedded GameView size belongs to the Godot editor. Run standalone for fullscreen."
	fields.vsync=check("Option","Vertical Sync",DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED,func(value):DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED),option_grid)
	var busy := check("Option","Busy Wait",false,func(_value):pass,option_grid); busy.disabled=true; busy.tooltip_text="Godot owns the event/render loop; simulate's busy-wait scheduler is not used."
	select_option("Option","Spacing",["Tight","Wide"],ui_spacing,func(value):ui_spacing=value;apply_ui_theme();save_preferences())
	select_option("Option","Color",["Default","Orange","White","Black"],ui_color,func(value):ui_color=value;apply_ui_theme();save_preferences())
	select_option("Option","Font",["50 %","100 %","150 %","200 %","250 %","300 %"],ui_font,func(value):ui_font=value;apply_ui_theme();save_preferences())
	fields.run=radio_option("Simulation","",["Pause","Run"],1,func(value):
		if not updating: send({"action":"pause","value":value==0}))
	fields.threads=numeric_slider("Simulation","Num threads",0,10,0,1,func(value):
		if not updating: send({"action":"threads","value":int(value)}))
	var simulation_grid := paired_grid("Simulation")
	button("Simulation","Reset",func():send({"action":"reset_initial"}),simulation_grid)
	button("Simulation","Reload",reload_saved,simulation_grid)
	button("Simulation","Align",func():send({"action":"align"}),simulation_grid)
	button("Simulation","Copy state",func():send({"action":"copy_state","precise":Input.is_key_pressed(KEY_SHIFT)}),simulation_grid)
	fields.key=numeric_slider("Simulation","Key",0,0,0,1,func(value):
		if not updating: key_index=int(value);send({"action":"key_load","id":key_index}))
	var key_grid := paired_grid("Simulation")
	fields.key_load=button("Simulation","Load key",func():send({"action":"key_load","id":key_index}),key_grid)
	fields.key_save=button("Simulation","Save key",func():send({"action":"key_save","id":key_index}),key_grid)
	for key in ["std","rate"]:
		var kind: String=key
		fields["noise_"+key]=numeric_slider("Simulation","Noise scale" if key=="std" else "Noise rate",0,1 if key=="std" else 4,0,.01,func(value):
			if not updating: send({"action":"ctrl_noise",kind:value}))
	subsection("Simulation","History")
	fields.history=numeric_slider("Simulation","",0,0,0,1,func(value):
		if not updating: send({"action":"history_seek","offset":int(value)}))
	var watch_row := HBoxContainer.new(); sections.Watch.box.add_child(watch_row)
	var watch_caption := Label.new(); watch_caption.text="Field"; watch_row.add_child(watch_caption)
	var watch := LineEdit.new(); watch.text=watch_field; watch.size_flags_horizontal=Control.SIZE_EXPAND_FILL; watch.placeholder_text="mjData numeric field"; watch_row.add_child(watch)
	fields.watch_edit=watch; watch.text_submitted.connect(func(value):watch_field=value;inspect_due=true)
	var index := SpinBox.new(); index.prefix="Index "; index.min_value=0; index.max_value=100000000; sections.Watch.box.add_child(index); index.value_changed.connect(func(value):watch_index=int(value);inspect_due=true)
	native_item(watch,"Watch","Field","EDITTXT")
	native_item(index,"Watch","Index","EDITINT")
	watch_label=explanation("Watch","");native_item(watch_label,"Watch","Value","STATIC")
	explanation("Physics","Read-only design. Edit in Godot editor.")
	button("Control","Clear all",func():send({"action":"clear_control"}))
	fields.backend_choice=select_option("Renderer","Requested backend",["Godot","MuJoCo native"],0,func(value):switch_renderer(value==1))
	explanation("Renderer","Two display backends share the MuJoCo camera, selection and simulation. Godot keeps authored materials and lighting.")
	overlay_check=check("Performance","Godot 性能叠加（独立于 F2 Info）",overlay_enabled,set_overlay)
	for key in metrics:
		var label: String={"fps":"渲染 FPS","cpu":"整机 CPU %","ram":"系统内存","gpu":"整卡 GPU %","vram":"整卡显存","timing":"CPU/GPU 耗时 ms"}[key]
		var metric: String=key
		var box := check("Performance",label,metrics[key],func(value):metrics[metric]=value;save_preferences();refresh_hud())
		var reason := performance_source.availability(key); box.disabled=not reason.is_empty();box.tooltip_text=reason;metric_checks[key]=box
		if box.disabled: metrics[key]=false;box.set_pressed_no_signal(false)
	explanation("Performance","CPU/RAM: whole system. GPU/VRAM: matched rendering GPU. Utilization % and frame cost ms are separate. Missing driver counters need no extra tools.")
	var steps := SpinBox.new(); steps.min_value=1; steps.max_value=1000; steps.value=1; steps.prefix="Steps "; extras_sections.Tools.box.add_child(steps)
	button("Tools","Godot: 精确步进 N 次",func():steps.apply();send({"action":"step","count":int(steps.value)}))
	button("Tools","Godot: 记录完整快照",func():send({"action":"capture_snapshot"}))
	button("Tools","Godot: 恢复完整快照",func():send({"action":"restore_snapshot"}))
	var path := LineEdit.new(); fields.output_edit=path; path.text=output_path; path.placeholder_text="user:// 输出目录"; extras_sections.Tools.box.add_child(path); path.text_changed.connect(func(value):output_path=value.strip_edges());path.text_submitted.connect(func(_value):save_preferences())
	button("Tools","显示 MuJoCo 左右面板",func():set_native_panels(true,true))

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

func bind_world(value: Node3D, preserved_camera: Dictionary = {}) -> void:
	var previous_camera: Dictionary=preserved_camera if not preserved_camera.is_empty() else frame.get("camera",{}).duplicate() if attached else {}
	retire_model_controls()
	if attached: cancel_gesture()
	for request in pending: PhysicsServer3D.call("scene_cancel_world_command",request)
	command_request=0;attached=false;display_preferences_pending.clear();preference_queue.clear()
	if is_instance_valid(runtime_world) and runtime_world != value and runtime_world.runtime_viewer==self: runtime_world.runtime_viewer=null
	runtime_world=value; source_viewport=value.get_viewport(); runtime_world.runtime_viewer=self
	update_viewport_rect()
	if reload_source_path.is_empty():
		reload_source_path=value.scene_file_path
		var scene := get_tree().current_scene
		if reload_source_path.is_empty() and is_instance_valid(scene) and scene.is_ancestor_of(value):
			reload_source_path=scene.scene_file_path; reload_world_path=scene.get_path_to(value)
	camera=source_viewport.get_camera_3d()
	if not camera:
		camera=Camera3D.new(); value.add_child(camera); camera.position=Vector3(3,2,4); camera.look_at(Vector3.ZERO); camera.make_current()
	authored_seed=capture_camera_seed()
	if not previous_camera.is_empty():
		authored_seed=seed_from_state(previous_camera)
		apply_camera(previous_camera)
	camera_to_restore=previous_camera
	camera.set_process_unhandled_input(false); camera.set_process_input(false); camera.set_process(false)
	known_revision=-1;seeded_revision=-1; presented_revision=-1; presented_frame_id=0; frame={}; catalog={}; details={}; pending.clear(); geometry_targets.clear();last_backend="";frames_retiring=false;frame_retire_request=0;retire_target.clear();attached=true;inspect_due=true
	clear_sensor_images()
	if not value.has_meta("viewer_diagnostics"):
		var diagnostics := preload("godot_scene.gd").new(); source_viewport.add_child(diagnostics); value.set_meta("viewer_diagnostics",diagnostics)
	feedback=""
	world_changed.emit(value)

func frame_options(backend := "godot") -> Dictionary:
	return {"backend":backend,"inspect":inspect_due,"sensors":windows.sensors.visible,"watch_field":watch_field,"watch_index":watch_index,"profiler":windows.profiler.visible}

func send(command: Dictionary) -> int:
	if not attached or not is_instance_valid(runtime_world) or frame.is_empty(): return 0
	var revision: int=frame.revision
	var frame_id: int=frame.frame_id
	if str(command.action) in ["select","move","perturb_begin"]:
		if frames_retiring or presented_frame_id==0 or presented_revision!=revision or presented_layout!=layout_generation: return 0
		frame_id=presented_frame_id
	sequence+=1
	var id: int=PhysicsServer3D.call("scene_viewer_request",runtime_world.space,revision,frame_id,sequence,command)
	if id>0: pending[id]=str(command.action)
	else: feedback="Viewer command queue is full"
	return id

func request_action(command: Dictionary) -> bool:
	if command_request!=0: last_error="Wait for the pending viewer action"; return false
	command_request=send(command)
	last_error="" if command_request!=0 else "Viewer is not ready"
	return command_request!=0

func _process(_delta: float) -> void:
	if not attached or not is_instance_valid(runtime_world): return
	update_viewport_rect()
	refresh_feedback()
	for id in pending.keys():
		var result: Dictionary=PhysicsServer3D.call("scene_viewer_result",id)
		if result.is_empty(): continue
		var action: String=pending[id]
		pending.erase(id)
		if id==frame_retire_request:
			frame_retire_request=0;frames_retiring=false;retire_target.clear()
		last_result=result
		if result.success and action in ["vis","rnd","group","visual","frame","label","tree_depth"] and frame.has("space"):
			display_preferences_pending={"space":int(frame.space),"revision":int(frame.revision),"after_frame":int(frame.frame_id)}
		if id==command_request: command_request=0; last_error=str(result.error)
		viewer_command_finished.emit(result)
		if not result.success: feedback=str(result.error)
		elif result.has("text"):
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD): DisplayServer.clipboard_set(str(result.text)); feedback="已复制到剪贴板"
			else: feedback="当前显示后端没有剪贴板；状态文本可从命令结果读取"
		elif result.has("path"): feedback="已输出："+str(result.path)
	if frames_retiring and frame_retire_request==0: submit_frame_retirement()
	var native_running: bool=is_instance_valid(runtime_world.native_view) and not runtime_world.native_view.stopped
	if not native_running and not frames_retiring:
		var packet: Dictionary=PhysicsServer3D.call("scene_viewer_frame",runtime_world.space,known_revision,frame_options())
		if not packet.has("error") and not packet.get("pending",false): accept_frame(packet)
		elif packet.has("error"): feedback=str(packet.error)
	var now := Time.get_ticks_msec()
	if now>=next_info:
		next_info=now+200; inspect_due=true; update_info(); refresh_hud()
	if now>=next_system:
		next_system=now+1000
		if overlay_enabled or controls.visible: system_metrics=performance_source.sample(metrics)
	if now-fps_at>=500:
		renderer_fps=fps_count*1000.0/maxi(1,now-fps_at); fps_count=0; fps_at=now; host_fps=Engine.get_frames_per_second()
	if now>=next_preference_save and (controls.visible or not display_preferences_pending.is_empty() and display_settings_ready()):
		next_preference_save=now+1000; save_preferences()
	if not preference_queue.is_empty() and pending.size()<32:
		for i in mini(8,preference_queue.size()): send(preference_queue.pop_front())

func accept_frame(packet: Dictionary) -> void:
	var needs_seed: bool=int(packet.revision)!=seeded_revision
	if not display_preferences_pending.is_empty() and (int(packet.space)!=int(display_preferences_pending.space) or int(packet.revision)!=int(display_preferences_pending.revision)):
		display_preferences_pending.clear()
	var model_changed: bool=(not frame.is_empty() and int(frame.revision)!=int(packet.revision)) or (seeded_revision>=0 and seeded_revision!=int(packet.revision))
	if model_changed:
		retire_model_controls()
		clear_sensor_images(); details={}; inspect_due=true
		camera_to_restore=frame.get("camera",{}).duplicate()
		if not camera_to_restore.is_empty():
			authored_seed=seed_from_state(camera_to_restore)
			apply_camera(camera_to_restore)
	frame=packet; known_revision=int(packet.revision)
	var backend := "native" if is_instance_valid(runtime_world.native_view) and not runtime_world.native_view.stopped else "godot"
	if packet.has("catalog"):
		catalog=packet.catalog; build_catalog(); cache_geometry()
		if needs_seed:
			seeded_revision=int(packet.revision)
			if is_instance_valid(camera): seed_authored_camera()
			restore_camera_mode()
			queue_preferences()
			if not Engine.has_meta("gmj_runtime_log_path"):
				var folder := output_directory()
				if not folder.is_empty(): Engine.set_meta("gmj_runtime_log_path",folder); send({"action":"logging","path":folder+"/MUJOCO_LOG.TXT"})
	if last_backend!=backend: last_backend=backend
	if packet.has("inspect"): details=packet.inspect; inspect_due=false
	if backend=="godot":
		apply_camera(packet.camera)
		if DisplayServer.get_name()=="headless":
			acknowledge_presented(int(frame.revision),int(frame.frame_id),applied_layout)
		apply_visibility()
		var diagnostics: Node3D=runtime_world.get_meta("viewer_diagnostics") if runtime_world.has_meta("viewer_diagnostics") else null
		if is_instance_valid(diagnostics): diagnostics.apply(packet,runtime_world)

func capture_camera_seed() -> Dictionary:
	var orthographic := camera.projection==Camera3D.PROJECTION_ORTHOGONAL
	var viewport_size := source_viewport.get_visible_rect().size
	var aspect := maxf(viewport_size.x,1)/maxf(viewport_size.y,1)
	var fov := camera.fov
	var extent := camera.size
	if camera.keep_aspect==Camera3D.KEEP_WIDTH:
		fov=rad_to_deg(2*atan(tan(deg_to_rad(fov)/2)/aspect)); extent/=aspect
	var command := {"action":"seed_camera","transform":camera.get_camera_transform(),"orthographic":orthographic,"fovy":extent if orthographic else fov,"near":camera.near,"far":camera.far}
	if camera.projection==Camera3D.PROJECTION_FRUSTUM: command.frustum_size=extent; command.offset=camera.frustum_offset
	return command
func seed_from_state(state: Dictionary) -> Dictionary:
	var command := {"action":"seed_camera","transform":state.transform,"orthographic":state.orthographic,"fovy":state.size if state.orthographic else state.fov,"near":state.near,"far":state.far}
	if state.offset.length_squared()>.00000001: command.frustum_size=state.size;command.offset=state.offset
	return command
func seed_authored_camera() -> void:
	if authored_seed.is_empty(): authored_seed=capture_camera_seed()
	send(authored_seed)

func unprefixed(name: String) -> String:
	if name.begins_with("import_"):
		var split := name.find("_",7)
		if split>=0: return name.substr(split+1)
	return name

func restore_camera_mode() -> void:
	var mode: int=camera_to_restore.get("type",0)
	var target: String=unprefixed(camera_to_restore.get("target",""))
	if mode==2:
		var matches: Array=[]
		for i in range(2,catalog.get("cameras",[]).size()):
			if unprefixed(catalog.cameras[i])==target: matches.append(i)
		if matches.size()==1: send({"action":"camera","id":matches[0]})
	elif mode==1:
		var matches: Array=catalog.get("bodies",[]).filter(func(body):return unprefixed(body.name)==target)
		if matches.size()==1: send({"action":"track_body","name":matches[0].name})
	camera_to_restore={}

func apply_camera(state: Dictionary) -> void:
	if not is_instance_valid(camera): return
	camera.global_transform=state.transform; camera.keep_aspect=Camera3D.KEEP_HEIGHT
	var full_size := source_viewport.get_visible_rect().size
	var central := render_rect_in_source()
	# The root's 3D image is cropped by the two opaque sidebars. Keep the
	# vertical extent and shift the optical axis to the central rectangle.
	# This is equivalent to rendering directly into that rectangle, including
	# asymmetric sidebars and off-axis cameras; it does not squeeze the image.
	var delta := central.get_center()-full_size*.5
	var offset: Vector2=state.offset-Vector2(delta.x,-delta.y)*float(state.size)/maxf(full_size.y,1)
	camera.h_offset=0;camera.v_offset=0
	if state.orthographic:
		camera.set_orthogonal(state.size,state.near,state.far)
		camera.h_offset=offset.x;camera.v_offset=offset.y
	elif offset.length_squared()>.00000001: camera.set_frustum(state.size,offset,state.near,state.far)
	else: camera.set_perspective(state.fov,state.near,state.far)
	camera.make_current(); applied_layout=layout_generation

func apply_visibility() -> void:
	var allowed := {}
	for id in frame.get("visible_geoms",PackedInt32Array()): allowed[id]=true
	for id in geometry_targets:
		for mesh in geometry_targets[id]:
			if is_instance_valid(mesh): mesh.visible=allowed.has(id)

func cache_geometry() -> void:
	geometry_targets.clear()
	var named := {}
	for node in runtime_world.find_children("*","Node3D",true,false):
		if "visuals" in node and "model_rid" in node:
			var prefix := "import_%d_" % node.model_rid.get_id()
			for key in node.visuals: named[prefix+str(key)]=node.visuals[key]
	for geom in catalog.get("geoms",[]):
		if named.has(geom.name): geometry_targets[geom.id]=[named[geom.name]]
		elif geom.get("object_id",0)>0:
			var owner_node: Object=instance_from_id(geom.object_id)
			if not is_instance_valid(owner_node) or not owner_node is Node: continue
			if "native_rids" in owner_node and "native_collisions" in owner_node:
				var index: int=owner_node.native_rids.find(geom.get("owner_rid",RID()))
				var visual: Node=owner_node.get_node_or_null("Visual")
				if index>=0 and index<owner_node.native_collisions.size() and visual:
					var path: String=owner_node.native_collisions[index].get("source_node","")
					var mesh: Node=visual.get_node_or_null(path)
					if mesh is MeshInstance3D: geometry_targets[geom.id]=[mesh]
			else: geometry_targets[geom.id]=owner_node.find_children("*","MeshInstance3D",true,false)

func acknowledge_presented(revision: int, frame_id: int, layout: int) -> bool:
	if frames_retiring or layout!=layout_generation or not attached or not is_instance_valid(runtime_world): return false
	if not PhysicsServer3D.call("scene_viewer_ack",runtime_world.space,revision,frame_id):
		presented_layout=-1;presented_frame_id=0;return false
	presented_revision=revision;presented_frame_id=frame_id;presented_layout=layout
	return true
func after_draw() -> void:
	if not attached or not is_instance_valid(runtime_world) or frame.is_empty(): return
	# Container minimum sizes can settle late in the frame. Such a transition
	# invalidates the just-drawn layout before it becomes eligible for picking.
	update_viewport_rect()
	if not runtime_world.native_view_active and last_backend=="godot" and applied_layout==layout_generation:
		acknowledge_presented(int(frame.revision),int(frame.frame_id),applied_layout);fps_count+=1

func native_presented(number: int, revision: int, frame_id: int, layout: int = -1) -> void:
	update_viewport_rect()
	if frames_retiring or layout!=layout_generation: return
	if number!=last_native_frame: last_native_frame=number;fps_count+=1
	acknowledge_presented(revision,frame_id,layout)

func set_controls_visible(value: bool) -> void:
	cancel_gesture()
	for popup in managed_popups.duplicate():
		if is_instance_valid(popup) and popup.visible: popup.hide()
	if value:
		var bounds := Vector2i(get_tree().root.size)
		var saved_size: Vector2i=config.get_value("window","size",Vector2i(560,700))
		controls.size=Vector2i(clampi(saved_size.x,360,maxi(360,bounds.x-24)),clampi(saved_size.y,240,maxi(240,bounds.y-48)))
		var saved_position: Vector2i=config.get_value("window","position",Vector2i(40,50))
		controls.position=Vector2i(clampi(saved_position.x,0,maxi(0,bounds.x-controls.size.x)),clampi(saved_position.y,32,maxi(32,bounds.y-controls.size.y)))
		controls.show(); controls.grab_focus()
	else: controls.hide(); save_preferences()
	inspect_due=true
func set_overlay(value: bool) -> void:
	overlay_enabled=value; overlay_check.set_pressed_no_signal(value); save_preferences(); refresh_hud()
func set_info(value: bool) -> void:
	info_enabled=value; windows.info.visible=value
	if fields.has("option:info"): fields["option:info"].set_pressed_no_signal(value)
	save_preferences();refresh_native_info()
func set_auxiliary(name: String, value: bool) -> void:
	if name=="info": set_info(value);return
	cancel_gesture(); var panel: Control=windows[name]; panel.visible=value
	if fields.has("option:"+name): fields["option:"+name].set_pressed_no_signal(value)
	if name=="profiler": send({"action":"profiler","enabled":value})
	inspect_due=true
func toggle_auxiliary(name: String) -> void:
	set_auxiliary(name,not windows[name].visible)
func set_native_panels(left: bool, right: bool) -> void:
	left_panel.visible=left; right_panel.visible=right; update_viewport_rect();save_preferences()
func refresh_help() -> void:
	if not help_label: return
	var actions := PackedStringArray();var shortcuts := PackedStringArray()
	for line in SimulateUI.HELP.split("\n",false):
		var split := line.find("  ")
		if split<0: continue
		actions.append(line.substr(0,split));shortcuts.append(line.substr(split).strip_edges())
	fields.help_actions.text="\n".join(actions);fields.help_shortcuts.text="\n".join(shortcuts)
	help_label.text="\n0–5 Geom groups · Shift+0–5 Site groups · Alt+letter sections.\n` Body Tree · F6 Frames · F7 Labels. Alt swaps left/right mouse.\nF2: MuJoCo Info. FPS / system metrics: Godot F11.\nGodot: authored materials/lighting. Native: MuJoCo visuals.\nRuntime edits do not change saved scene/MJCF.\n嵌入 GameView 全屏由编辑器管理；F8 停止保留。"
	for key in extension_help: help_label.text+="\n\n"+str(extension_help[key])
func register_extension(key: String, title: String, widget: Control, help: String) -> void:
	if extensions.has(key) and is_instance_valid(extensions[key]): extensions[key].queue_free()
	if widget.get_parent(): widget.get_parent().remove_child(widget)
	extras_sections.Examples.box.add_child(widget); extensions[key]=widget; extension_help[key]=title+"\n"+help; refresh_help()
func build_catalog() -> void:
	managed_popups=managed_popups.filter(func(popup):return is_instance_valid(popup))
	for title in ["Rendering","Visualization","Group enable"]:
		subsection_targets.erase(title)
		for child in sections[title].box.get_children(): child.queue_free()
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
					selected_image_sensor=-1 if id==0 else int(catalog.image_sensors[id-1].id);clear_sensor_images();update_sensors())

	for definition in catalog.get("groups",[]):
		subsection("Group enable",str(definition.name).capitalize()+" groups")
		var group_grid := paired_grid("Group enable")
		for i in 6:
			var group_name: String=definition.name; var index: int=i
			var widget := check("Group enable","%s %d" % [group_name.capitalize(),i],true,func(value):
				if not updating: send({"action":"group","name":group_name,"id":index,"value":value}),group_grid)
			widget.disabled=not definition.supported;widget.tooltip_text="Current supported model has no flex/skin" if widget.disabled else "";fields["group:%s:%d" % [group_name,i]]=widget
			if group_name in ["geom","site"]: widget.set_meta("mujoco_shortcut",("Shift+" if group_name=="site" else "")+str(i))
	var previous_group := ""
	for definition in catalog.get("visual",[]):
		var field_name: String=definition.name;var pieces := field_name.split(".",false)
		var group: String=SimulateUI.visual_section(field_name)
		if group!=previous_group:
			if previous_group=="Free Camera": button("Visualization","Align",func():send({"action":"align"}))
			subsection("Visualization",group,not group in ["Scale","RGBA"]);previous_group=group
		var label_text: String=SimulateUI.VISUAL_NAMES.get(field_name,pieces[-1].capitalize())
		if definition.integer and definition.values.size()==1:
			var options: Array=["No","Yes"] if field_name=="global.orthographic" else ["Box","Ellipsoid"] if field_name=="global.ellipsoidinertia" else ["Off","On"]
			var widget := radio_option("Visualization",label_text,options,int(definition.values[0]),func(value):send({"action":"visual","name":field_name,"values":[value]}))
			widget.set_meta("mujoco_disabled",not definition.get("supported",true));widget.tooltip_text=definition.get("reason","")
			for child in widget.get_children(): child.disabled=not definition.get("supported",true);child.tooltip_text=definition.get("reason","")
		else:
			var row := VBoxContainer.new();section_box("Visualization").add_child(row)
			var label := Label.new();label.text=label_text;row.add_child(label)
			var edit := LineEdit.new();edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(edit);native_item(edit,"Visualization",label_text,"EDIT")
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
	for control in [fields.key,fields.key_load,fields.key_save]: control.tooltip_text=catalog.get("keyframe_reason","Current compiled model has no keyframes.") if count==0 else "Session keyframes; no editor/design writeback."
	fields["file:save_xml"].disabled=not catalog.get("save_xml_supported",true);fields["file:save_xml"].tooltip_text="Committed XML source is unavailable." if fields["file:save_xml"].disabled else ""
	refresh_help()

func sync_numeric(section: String, rows: Array, action: String) -> void:
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
	if frame.is_empty(): status.text="MuJoCo · 等待可视化数据\n"+feedback; return
	status.text="Godot 附加功能\n"+runtime_world.rendering_status()+"\n"+feedback
	fields.backend_choice.select(1 if runtime_world.native_view_experimental else 0)
	updating=true
	if left_panel.visible or right_panel.visible:
		sync_numeric("Joint",details.get("joints",[]),"joint"); sync_numeric("Control",details.get("controls",[]),"control")
		var active_equalities := {}
		for data in details.get("equalities",[]):
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
		watch_label.text="%s[%d] = %s" % [watch_field,watch_index,str(details.get("watch_value",details.get("watch_error","等待数据")))]
		if details.has("physics"): update_physics_inspector(details.physics)
		update_logging()
	fields.fullscreen.set_pressed_no_signal(get_tree().root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN])
	fields.vsync.set_pressed_no_signal(DisplayServer.window_get_vsync_mode()!=DisplayServer.VSYNC_DISABLED)
	fields.run.select(0 if frame.paused else 1)
	fields.history.min_value=-maxi(0,int(frame.history_count)-1);fields.history.max_value=0;set_slider_value(fields.history,frame.history_offset)
	set_slider_value(fields.key,int(frame.get("key",key_index)));key_index=int(fields.key.value)
	set_slider_value(fields.threads,frame.get("num_threads",0))
	set_slider_value(fields.noise_std,frame.get("noise_std",0));set_slider_value(fields.noise_rate,frame.get("noise_rate",0))
	fields.pause_update.set_pressed_no_signal(frame.get("pause_update",false))
	refresh_native_info()
	run_label.text=("PAUSE"+(" (%d)" % frame.history_offset if int(frame.history_offset)<0 else "")) if frame.paused else ""
	run_label.position=render_rect.position+Vector2(maxf(8,(render_rect.size.x-run_label.get_combined_minimum_size().x)/2),6)
	speed_label.text="%.3f%%" % frame.speed_percent if absf(float(frame.speed_percent)-100)>.001 else ""
	speed_label.position=render_rect.position+Vector2(6,6)
	var settings: Dictionary=frame.get("settings",{})
	if is_instance_valid(fields.get("tree_depth")): set_slider_value(fields.tree_depth,settings.get("bvh_depth",0))
	if is_instance_valid(fields.get("camera_choice")):
		var mode: int=frame.camera.get("type",0)
		fields.camera_choice.select(2+int(frame.camera.fixed_id) if mode==2 else 1 if mode==1 else 0)
	for action in ["frame","label"]:
		if is_instance_valid(fields.get(action+"_choice")): fields[action+"_choice"].select(settings.get(action,0))
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
	if windows.profiler.visible:
		# Match the category filtering in simulate's PGS/CG/Newton profiler.
		# Every island then repeats this same ordered caption/color palette.
		var solver: int=details.get("physics",{}).get("solver",2)
		var counts: Array=["total","active","changed","evals","updates"].slice(0,3 if solver==0 else 4 if solver==1 else 5)
		var costs: Array=["improvement"] if solver==0 else ["improvement","gradient","lineslope"]
		if profiler_plots[0].captions!=counts: profiler_plots[0].captions=counts;profiler_plots[0].queue_redraw()
		if profiler_plots[1].captions!=costs: profiler_plots[1].captions=costs;profiler_plots[1].queue_redraw()
	if windows.profiler.visible and not profiler.is_empty() and float(profiler.get("time",-1))!=last_profiler_time:
		last_profiler_time=float(profiler.time)
		profiler_plots[0].set_series(profiler.get("counts",[])); profiler_plots[1].set_series(profiler.get("costs",[]))
		profiler_plots[2].title="CPU time (msec)" if profiler.get("timing_available",false) else "CPU timing unavailable"
		if profiler.get("timing_available",false): profiler_plots[2].append_sample(profiler.get("timing_ms",[]))
		profiler_plots[3].append_sample(profiler.get("sizes",[]))
	if windows.sensors.visible: update_sensors()

func build_physics_row(item: Array) -> void:
	var key: String=item[1]
	if SimulateUI.PHYSICS_ENUMS.has(key):
		var choice := select_option("Physics",item[0],SimulateUI.PHYSICS_ENUMS[key],0,func(_value):pass);choice.disabled=true;choice.tooltip_text="Physics design is read-only at runtime. Edit in Godot editor.";fields.physics_rows[key]=choice
	else:
		var row := VBoxContainer.new();section_box("Physics").add_child(row)
		var label := Label.new();label.text=item[0];row.add_child(label)
		var edit := LineEdit.new();edit.editable=false;edit.tooltip_text="Physics design is read-only at runtime. Edit in Godot editor.";row.add_child(edit);native_item(edit,"Physics",item[0],"EDIT");fields.physics_rows[key]=edit
func update_physics_inspector(values: Dictionary) -> void:
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
		if selected_image_sensor>=0 and sensor.id!=selected_image_sensor: continue
		if not sensor.has("rgb") or sensor_versions.get(sensor.id)==sensor.version: continue
		sensor_versions[sensor.id]=sensor.version
		var key := "sensor_image:%d" % sensor.id
		var texture: TextureRect=fields.get(key)
		if not is_instance_valid(texture):
			var label := Label.new();label.text=sensor.name;label.add_theme_font_size_override("font_size",12);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;sensor_images.add_child(label)
			texture=TextureRect.new(); texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; texture.custom_minimum_size=Vector2(80,60); sensor_images.add_child(texture); fields[key]=texture
		texture.texture=ImageTexture.create_from_image(Image.create_from_data(sensor.width,sensor.height,false,Image.FORMAT_RGB8,sensor.rgb))
	sensor_plot.title="Sensor data / cutoff" if not values.is_empty() else "No numeric data"
	sensor_plot.set_series([values]); sensor_plot.captions=names
	if not fields.has("sensor_note"):
		fields.sensor_note=Label.new();fields.sensor_note.add_theme_font_size_override("font_size",11);fields.sensor_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;fields.sensor_note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;sensor_images.add_child(fields.sensor_note)
	fields.sensor_note.text="无图像传感器数据\n需模型提供生产数据" if images==0 or sensor_versions.is_empty() else "图像版本标记已移除"

func refresh_hud() -> void:
	hud.visible=overlay_enabled
	if not overlay_enabled: return
	var lines := PackedStringArray()
	if metrics.fps:
		lines.append("FPS %.1f%s" % [renderer_fps," · Godot host %.1f" % host_fps if runtime_world.native_view_active else ""])
	for metric in ["cpu","gpu"]:
		if metrics[metric]: lines.append("System CPU %.1f%%" % system_metrics[metric] if metric=="cpu" and system_metrics.has(metric) else "GPU %.1f%%" % system_metrics[metric] if system_metrics.has(metric) else metric.to_upper()+" unavailable")
	for metric in ["ram","vram"]:
		if metrics[metric]: lines.append("%s %.2f / %.2f GiB" % ["System RAM" if metric=="ram" else "GPU VRAM",system_metrics.get(metric,0)/1073741824.0,system_metrics.get(metric+"_total",0)/1073741824.0] if system_metrics.has(metric) else metric.to_upper()+" unavailable")
	if metrics.timing:
		var profiler: Dictionary=frame.get("stats",{}).get("profiler",{})
		if profiler.get("timing_available",false): lines.append("Physics CPU %.3f ms" % profiler.get("timing_ms",[0])[0])
		if runtime_world.native_view_active:
			var native: Dictionary=runtime_world.native_view.latest
			if native.get("mujoco_render_gpu_ms",-1)>=0: lines.append("MuJoCo render GPU %.3f ms" % native.mujoco_render_gpu_ms)
			else: lines.append("MuJoCo GPU timing unavailable")
		else: lines.append("Godot GPU timing unavailable on the current display path")
	hud.text="\n".join(lines)
	hud.size=hud.get_combined_minimum_size()
	position_hud()
func position_hud() -> void:
	var reserved: float=render_rect.size.x*.25 if windows.profiler.visible else 0.0
	# Keep the Godot overlay below MuJoCo's PAUSE/speed row. Native FPS has
	# a wider host-rate suffix, and may otherwise collide when figures open.
	var y := status_row_end()
	if windows.help.visible and not windows.info.visible:
		if windows.sensors.visible: reserved+=render_rect.size.x*.25
		y=maxf(y,render_rect.size.y-hud.size.y-8)
	hud.position=render_rect.position+Vector2(maxf(8,render_rect.size.x-hud.size.x-reserved-8),y)
	refresh_feedback()

func status_row_end() -> float:
	var end := 42.0
	for label in [run_label,speed_label]:
		if is_instance_valid(label) and label.visible and not label.text.is_empty():
			end=maxf(end,label.position.y-render_rect.position.y+maxf(label.size.y,label.get_combined_minimum_size().y)+8)
	return end

func refresh_feedback() -> void:
	if not is_instance_valid(feedback_label): return
	feedback_label.text=feedback;feedback_label.visible=not feedback.is_empty() and Time.get_ticks_msec()<feedback_deadline
	var available: float=render_rect.size.x*(.75 if windows.profiler.visible else 1.0)
	feedback_label.size.x=maxf(1,available-16)
	var y := status_row_end()
	if is_instance_valid(hud) and hud.visible and not hud.text.is_empty():
		var note := Rect2(render_rect.position+Vector2(8,y),Vector2(feedback_label.size.x,maxf(feedback_label.size.y,feedback_label.get_combined_minimum_size().y)))
		var performance := Rect2(hud.position,hud.size.max(hud.get_combined_minimum_size()))
		if note.intersects(performance): y=performance.end.y-render_rect.position.y+8
	feedback_label.position=render_rect.position+Vector2(8,y)

func refresh_native_info() -> void:
	if not fields.has("info_label") or frame.is_empty(): return
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

func _input(event: InputEvent) -> void:
	global_input(event,get_viewport())
func global_input(event: InputEvent, viewport: Viewport) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if not event.pressed or viewport!=controls and (left_panel.get_global_rect().has_point(event.position) or right_panel.get_global_rect().has_point(event.position)): panel_hint(event)
	if event is InputEventMouseButton and dragging:
		if not event.pressed or viewport==controls or not render_rect.has_point(event.position): cancel_gesture()
	if event is InputEventKey and event.pressed and not event.echo:
		var global_key: bool=event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F11]
		var native_tab: bool=event.keycode==KEY_TAB and not extras_has_focus() and not text_has_focus()
		if not global_key and not native_tab: return
		if event.get_instance_id()==last_global_event: return
		last_global_event=event.get_instance_id()
		if key_input(event): viewport.set_input_as_handled()
func extras_has_focus() -> bool:
	if not is_instance_valid(controls) or not controls.visible: return false
	if controls.has_focus(): return true
	for popup in managed_popups:
		if is_instance_valid(popup) and popup.visible and popup.has_focus() and controls.is_ancestor_of(popup): return true
	return false
func text_has_focus() -> bool:
	for viewport in [get_viewport(),controls]+managed_popups:
		if not is_instance_valid(viewport): continue
		if viewport is Window and viewport!=get_tree().root and not viewport.visible: continue
		var focus: Control=viewport.gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return true
	return false
func _unhandled_key_input(event: InputEvent) -> void:
	if key_input(event): get_viewport().set_input_as_handled()
func key_input(event: InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo: return false
	if event.keycode in [KEY_F8,KEY_F9,KEY_F10,KEY_F12]: return false
	if event.keycode==KEY_TAB:
		if extras_has_focus() or text_has_focus(): return false
		set_native_panels(left_panel.visible,not right_panel.visible) if event.shift_pressed else set_native_panels(not left_panel.visible,right_panel.visible)
		return true
	if not event.keycode in [KEY_F1,KEY_F2,KEY_F3,KEY_F4,KEY_F5,KEY_F6,KEY_F7,KEY_F11] and text_has_focus(): return false
	if event.ctrl_pressed or event.meta_pressed:
		if Keys.CTRL.has(event.keycode): perform(Keys.CTRL[event.keycode],event.shift_pressed); return true
		return false
	if event.alt_pressed and Keys.SECTIONS.has(event.keycode):
		var section: Dictionary=sections[Keys.SECTIONS[event.keycode]]
		section.button.button_pressed=not section.button.button_pressed
		if section.panel.visible: section.panel.ensure_control_visible(section.button)
		inspect_due=true; return true
	for row in Keys.ACTIONS:
		if event.keycode==row[0]:
			if row[1] in ["slower","faster"] and event.shift_pressed: return false
			perform(row[1]); return true
	if event.keycode>=KEY_0 and event.keycode<=KEY_5:
		send({"action":"group","name":"site" if event.shift_pressed else "geom","id":event.keycode-KEY_0}); return true
	for action in ["vis","rnd"]:
		for flag in catalog.get(action,[]):
			if flag.supported and not str(flag.shortcut).is_empty() and event.keycode==str(flag.shortcut).unicode_at(0): send({"action":action,"id":flag.id}); return true
	return false
func perform(action: String, precise := false) -> void:
	match action:
		"controls": set_controls_visible(not controls.visible)
		"help","profiler","sensors": toggle_auxiliary(action)
		"info": set_info(not info_enabled)
		"fullscreen": fullscreen()
		"reload": reload_saved()
		"quit": get_tree().quit()
		"screenshot": screenshot()
		"print_model","print_data","save_xml","save_mjb": export_data(action)
		"free_camera": send({"action":"camera","id":0})
		"camera_previous","camera_next": send({"action":"cycle_camera","delta":-1 if action=="camera_previous" else 1})
		"slower","faster": send({"action":"speed","delta":1 if action=="slower" else -1})
		"copy_state": send({"action":"copy_state","precise":precise})
		_: send({"action":action})

func render_rect_in_source() -> Rect2:
	if not is_instance_valid(source_viewport) or outer_rect.size.x<=0 or outer_rect.size.y<=0: return Rect2()
	var scale := source_viewport.get_visible_rect().size/outer_rect.size
	return Rect2((render_rect.position-outer_rect.position)*scale,render_rect.size*scale)
func update_viewport_rect() -> void:
	if not is_instance_valid(scene_input) or not is_instance_valid(source_viewport): return
	var rect := get_viewport().get_visible_rect()
	if source_viewport is SubViewport and source_viewport.get_parent() is SubViewportContainer: rect=source_viewport.get_parent().get_global_rect()
	var wanted_width := 270.0*(ui_font+1)/2.0+12.0*ui_spacing
	var panel_count := int(left_panel.visible)+int(right_panel.visible)
	var requested_width := minf(wanted_width,maxf(60,(rect.size.x-120)/maxi(1,panel_count)))
	# Godot enforces each Control's computed minimum size. Reserve the actual
	# resulting panel widths, including long model labels and scrollbar styles.
	left_panel.size=Vector2(requested_width,rect.size.y);right_panel.size=Vector2(requested_width,rect.size.y)
	var left_width := left_panel.size.x if left_panel.visible else 0.0
	var right_width := right_panel.size.x if right_panel.visible else 0.0
	var central := Rect2(rect.position+Vector2(left_width,0),Vector2(maxf(1,rect.size.x-left_width-right_width),rect.size.y))
	var changed := render_rect!=central or outer_rect!=rect
	outer_rect=rect;render_rect=central
	left_panel.position=rect.position;right_panel.position=Vector2(rect.end.x-right_panel.size.x,rect.position.y)
	scene_input.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);scene_input.position=central.position;scene_input.size=central.size
	position_hud()
	windows.help.position=central.position+Vector2(8,8);windows.help.size=Vector2(maxf(1,central.size.x*(1.0-.25*int(windows.profiler.visible)-.25*int(windows.sensors.visible))-16),maxf(1,central.size.y-16))
	windows.profiler.position=central.position+Vector2(central.size.x*.75,0);windows.profiler.size=Vector2(central.size.x*.25,central.size.y)
	windows.sensors.position=central.position+Vector2(central.size.x*(.5 if windows.profiler.visible else .75),central.size.y*2.0/3);windows.sensors.size=Vector2(central.size.x*.25,central.size.y/3)
	if is_instance_valid(help_hint): help_hint.position=central.position+Vector2(8,30)
	for hints in shortcut_hints:
		hints.position=hints.panel.position;hints.size=hints.panel.size
		if hints.visible: hints.queue_redraw()
	scene_input.visible=not source_viewport is SubViewport or not source_viewport.get_parent() is CanvasItem or source_viewport.get_parent().is_visible_in_tree()
	if changed:
		cancel_gesture(true);layout_generation+=1;presented_layout=-1;presented_frame_id=0
		if frame.has("camera") and not runtime_world.native_view_active: apply_camera(frame.camera)
		refresh_native_info()

func scene_event(event: InputEvent) -> void:
	if frame.is_empty(): return
	var height := maxf(scene_input.size.y,1)
	var viewport_size := render_rect_in_source().size
	if event is InputEventMouseButton:
		var logical: int=event.button_index
		if event.alt_pressed:
			if logical==MOUSE_BUTTON_LEFT: logical=MOUSE_BUTTON_RIGHT
			elif logical==MOUSE_BUTTON_RIGHT: logical=MOUSE_BUTTON_LEFT
		if logical in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			send({"action":"move","mouse":5,"dx":0.,"dy":-.02 if logical==MOUSE_BUTTON_WHEEL_UP else .02,"perturb":false}); return
		if not logical in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]: return
		if not event.pressed: cancel_gesture(); return
		var focus: Control=get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus): focus.release_focus()
		dragging=true; dragging_perturb=false; logical_button=logical
		var now := Time.get_ticks_msec()
		var double_click: bool=logical==last_click_button and now-last_click<250
		last_click=now; last_click_button=logical
		if double_click:
			send({"action":"select","button":logical,"x":event.position.x/maxf(scene_input.size.x,1),"y":1-event.position.y/height,"aspect":maxf(viewport_size.x,1)/maxf(viewport_size.y,1),"control":event.ctrl_pressed}); return
		if event.ctrl_pressed and logical in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			dragging_perturb=true; send({"action":"perturb_begin","mode":1 if logical==MOUSE_BUTTON_RIGHT else 2})
	elif event is InputEventMouseMotion and dragging:
		var action := 5
		if logical_button==MOUSE_BUTTON_LEFT: action=2 if event.shift_pressed else 1
		elif logical_button==MOUSE_BUTTON_RIGHT: action=4 if event.shift_pressed else 3
		var relative: Vector2=event.relative*viewport_size/scene_input.size.max(Vector2.ONE)
		# simulate flips its OpenGL mouse delta back to downward-positive dy
		# before calling mjv_move*. Godot already uses that input convention.
		send({"action":"move","mouse":action,"dx":relative.x/maxf(viewport_size.y,1),"dy":relative.y/maxf(viewport_size.y,1),"perturb":dragging_perturb})
func begin_frame_retirement() -> void:
	if frames_retiring or not attached or not is_instance_valid(runtime_world) or frame.is_empty(): return
	retire_target={"world":runtime_world.get_instance_id(),"space":runtime_world.space,"revision":int(frame.revision),"frame":int(frame.frame_id)}
	frames_retiring=true;presented_layout=-1;presented_frame_id=0
	submit_frame_retirement()
func submit_frame_retirement() -> void:
	if not frames_retiring or frame_retire_request!=0 or retire_target.is_empty(): return
	if not is_instance_valid(runtime_world) or runtime_world.get_instance_id()!=int(retire_target.world):
		frames_retiring=false;retire_target.clear();return
	sequence+=1
	frame_retire_request=PhysicsServer3D.call("scene_viewer_request",retire_target.space,retire_target.revision,retire_target.frame,sequence,{"action":"cancel","release_frames":true})
	if frame_retire_request>0: pending[frame_retire_request]="cancel"
	# A saturated queue latches emergency cancellation in C++; retry later to
	# obtain a terminal result before publishing any frame for the new layout.
func release_display_frames() -> void:
	cancel_gesture(true)
	frame={};known_revision=-1;presented_revision=-1;presented_frame_id=0;presented_layout=-1

func cancel_gesture(release_frames := false) -> void:
	dragging=false;dragging_perturb=false
	if release_frames: begin_frame_retirement()
	elif attached and not frame.is_empty(): send({"action":"cancel"})
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_gesture()
		if is_instance_valid(help_hint): help_hint.hide()
		for hints in shortcut_hints: hints.hide()
func panel_hint(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		help_hint.visible=event.pressed
		for hints in shortcut_hints: hints.visible=event.pressed and hints.panel.visible;hints.queue_redraw()

func display_settings_ready() -> bool:
	if display_preferences_pending.is_empty(): return true
	return frame.has("settings") and int(frame.get("space",-1))==int(display_preferences_pending.space) and int(frame.get("revision",-1))==int(display_preferences_pending.revision) and int(frame.get("frame_id",0))>int(display_preferences_pending.after_frame)
func save_preferences() -> void:
	if config_path.is_empty(): return
	config.set_value("godot_ui","performance_overlay",overlay_enabled);config.set_value("ui","output",output_path)
	if config.has_section_key("ui","overlay"): config.erase_section_key("ui","overlay")
	if config.has_section_key("metrics","simulation"): config.erase_section_key("metrics","simulation")
	config.set_value("simulate_ui","left",left_panel.visible);config.set_value("simulate_ui","right",right_panel.visible)
	config.set_value("simulate_ui","info",info_enabled);config.set_value("simulate_ui","spacing",ui_spacing);config.set_value("simulate_ui","color",ui_color);config.set_value("simulate_ui","font",ui_font)
	for key in metrics: config.set_value("metrics",key,metrics[key])
	if is_instance_valid(controls): config.set_value("window","position",controls.position); config.set_value("window","size",controls.size)
	# Native rendering can deliver a setting's command result before the next
	# frozen scene. Wait for newer settings from this space/revision before saving.
	var settings_ready := display_settings_ready()
	if frame.has("settings") and settings_ready: config.set_value("viewer","settings",frame.settings)
	if config.save(config_path)==OK and settings_ready: display_preferences_pending.clear()
func queue_preferences() -> void:
	preference_queue.clear()
	var settings: Dictionary=config.get_value("viewer","settings",{})
	for action in ["vis","rnd"]:
		for flag in catalog.get(action,[]):
			if flag.supported and int(flag.id)<settings.get(action,[]).size(): preference_queue.append({"action":action,"id":flag.id,"value":settings[action][flag.id]})
	for group_name in settings.get("groups",{}):
		for i in mini(6,settings.groups[group_name].size()): preference_queue.append({"action":"group","name":group_name,"id":i,"value":settings.groups[group_name][i]})
	for action in ["frame","label"]:
		if settings.has(action): preference_queue.append({"action":action,"value":settings[action]})
	if settings.has("bvh_depth"): preference_queue.append({"action":"tree_depth","value":settings.bvh_depth})
	for field in settings.get("visual",[]):
		if field.name in ["global.fovy","global.orthographic","global.azimuth","global.elevation","stat.center","stat.extent","map.znear","map.zfar"]: continue
		var available: Array=catalog.get("visual",[]).filter(func(candidate):return candidate.name==field.name and candidate.get("supported",true))
		if not available.is_empty(): preference_queue.append({"action":"visual","name":field.name,"values":field.values})
func output_directory() -> String:
	var folder := output_path.path_join(Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_msec()))
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if error!=OK: feedback="输出目录不可写："+folder; return ""
	return folder
func export_data(action: String) -> void:
	var folder := output_directory()
	if not folder.is_empty(): send({"action":action,"path":folder.path_join({"print_model":"MJMODEL.TXT","print_data":"MJDATA.TXT","save_xml":"mjmodel.xml","save_mjb":"mjmodel.mjb"}[action])})
func screenshot() -> void:
	var folder := output_directory()
	if folder.is_empty(): return
	await RenderingServer.frame_post_draw
	var image := get_tree().root.get_texture().get_image()
	var path := folder.path_join("screenshot.png")
	feedback="截图："+path if image.save_png(path)==OK else "截图写入失败："+path
func is_embedded_game() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(value):return value=="--wid" or value.begins_with("--wid=")).is_empty()
func set_fullscreen(value: bool) -> void:
	if is_embedded_game():
		feedback="嵌入式 GameView 的尺寸由 Godot 编辑器管理；独立运行支持 F5 全屏。"
	else: get_tree().root.mode=Window.MODE_FULLSCREEN if value else Window.MODE_WINDOWED
	if fields.has("fullscreen"): fields.fullscreen.set_pressed_no_signal(get_tree().root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN])
func fullscreen() -> void:
	set_fullscreen(not get_tree().root.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN])
func switch_renderer(native: bool) -> void:
	cancel_gesture();known_revision=-1;presented_frame_id=0;presented_layout=-1
	runtime_world.native_view_experimental=native
	if native:
		if not runtime_world.start_native_view(): feedback=runtime_world.native_view_error
	else: runtime_world.stop_native_view()

func reload_saved() -> void:
	if rebuilding: feedback="重载正在进行"; return
	cancel_gesture(); rebuilding=true
	if is_instance_valid(environment_host):
		if not environment_host.request_rebuild_environment(true): feedback=environment_host.last_error; rebuilding=false
		return
	var path := reload_source_path
	if path.is_empty(): feedback="当前世界没有已保存的场景来源"; rebuilding=false; return
	var saved: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not saved: feedback="无法读取已保存的场景："+path; rebuilding=false; return
	var host := preload("../model/environment_host.gd").new(); host.name="ReloadedMuJoCoEnvironment"; host.environment_scene=saved; host.install_runtime_viewer=false
	host.environment_world_path=reload_world_path
	host.rebuild_finished.connect(func(success,error):
		if not success: feedback="重载失败，保留原世界："+error; host.queue_free(); rebuilding=false; return
		var old: Node3D=runtime_world
		var previous_camera: Dictionary=frame.get("camera",{}).duplicate()
		var was_paused: bool=old.info().paused
		old.stop_native_view(); old.set_paused(true)
		host.world.set_paused(was_paused)
		environment_host=host; bind_world(host.world,previous_camera)
		if not owns_root_disable: saved_root_disable=get_tree().root.disable_3d; owns_root_disable=true
		get_tree().root.disable_3d=true
		host.world.activate_runtime_viewer(self)
		host.rebuild_finished.connect(host_rebuilt)
		if get_tree().current_scene==old: get_tree().current_scene=host
		elif is_instance_valid(get_tree().current_scene):
			get_tree().current_scene.tree_exiting.connect(func():
				if is_instance_valid(host): host.queue_free(),CONNECT_ONE_SHOT)
		old.queue_free(); rebuilding=false; feedback="已重载最后保存的设计",CONNECT_ONE_SHOT)
	get_tree().root.add_child(host); host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
func host_rebuilt(success: bool, error: String) -> void:
	rebuilding=false
	if success:
		if runtime_world!=environment_host.world: bind_world(environment_host.world)
		environment_host.world.activate_runtime_viewer(self); feedback="已重载最后保存的设计"
	else: feedback="重载失败，保留原世界："+error
func _exit_tree() -> void:
	if get_tree().node_added.is_connected(owned_window_added): get_tree().node_added.disconnect(owned_window_added)
	save_preferences(); cancel_gesture()
	if owns_root_disable: get_tree().root.disable_3d=saved_root_disable
	for request in pending: PhysicsServer3D.call("scene_cancel_world_command",request)
	if RenderingServer.frame_post_draw.is_connected(after_draw): RenderingServer.frame_post_draw.disconnect(after_draw)
	if is_instance_valid(runtime_world) and runtime_world.has_meta("viewer_diagnostics"):
		var diagnostics: Node=runtime_world.get_meta("viewer_diagnostics"); if is_instance_valid(diagnostics): diagnostics.queue_free()
