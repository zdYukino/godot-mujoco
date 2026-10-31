@tool
class_name MjExtrasUI
extends "ui_base.gd"
## Editable Godot-only tools. No camera region, native panels or simulation owner.
const SimulateUI = preload("simulate_ui.gd")
@export var use_default_presenters := true
@export var automatic_overlay_layout := true
var runtime_world: Node3D
var frame: Dictionary = {}
var fields := {}
var extras_sections := {}
var metric_checks := {}
var extensions := {}
var controls: Window
var hud: Label
var status: Label
var feedback_label: Label
var overlay_check: CheckBox
var managed_popups: Array[Window] = []
var authored_theme: Theme
var native_theme: Theme
var ui_spacing := 0
var ui_color := 0
var ui_font := 1
var overlay_enabled := true
var metrics := {"fps":true,"cpu":false,"ram":false,"gpu":false,"vram":false,"timing":false}
var system_metrics := {}
var renderer_fps := 0.0
var renderer_fps_available := true
var renderer_fps_reason := ""
var host_fps := 0.0
var render_rect := Rect2()
var outer_rect := Rect2()
var overlay_exclusions: Array[Rect2]=[]
var _last_hud_layout: Array=[]
var feedback_deadline := 0
var feedback := "":
	set(value):
		feedback=value;feedback_deadline=Time.get_ticks_msec()+8000
		refresh_feedback()
var _ready_bindings := false
var _previewing := false

func _ready() -> void:
	hydrate_bindings()
	resized.connect(_layout_updated)

func hydrate_bindings() -> void:
	if _ready_bindings:return
	_ready_bindings=true
	var nodes: Array[Node]=[self]
	while not nodes.is_empty():
		var node: Node=nodes.pop_back()
		nodes.append_array(node.get_children())
		if node is BaseButton:node.set_meta("viewer_authored_disabled",node.disabled)
		if node is Range or node is LineEdit:node.set_meta("viewer_authored_editable",node.editable)
		if node.has_meta("viewer_role"):set(str(node.get_meta("viewer_role")),node)
		if node.has_meta("viewer_field"):fields[str(node.get_meta("viewer_field"))]=node
		if node is Control and node.has_meta("viewer_bind_action"):_wire_authored_action(node)
		if node.has_meta("viewer_metric"):metric_checks[str(node.get_meta("viewer_metric"))]=node
		if node.has_meta("viewer_section"):
			var binding: Dictionary=node.get_meta("viewer_section")
			if not extras_sections.has(binding.name):extras_sections[binding.name]={}
			extras_sections[binding.name][binding.role]=node
	var ordered := {}
	for title in ["Renderer","Performance","Tools","Examples"]:
		if extras_sections.has(title):ordered[title]=extras_sections[title]
	extras_sections=ordered
	for row in extras_sections.values():
		row.panel=controls
		row.button.toggled.connect(func(value):
			row.box.visible=value;row.triangle.text="▼" if value else "◀";save_preferences())
	if use_default_presenters:_wire_standard_controls()

func validate_scene() -> String:
	if not is_instance_valid(controls) and not is_instance_valid(hud):return "Extras UI must provide a controls Window or a performance hud Label."
	for module in [controls,hud]:
		if is_instance_valid(module) and not is_ancestor_of(module):return "Extras modules must belong to this UI scene."
	return ""

func provides_action(action_id: StringName) -> bool:
	if action_id==&"controls":return is_instance_valid(controls)
	if action_id in [&"performance",&"metric"]:return is_instance_valid(hud)
	return true

func configure(component: Node, custom_theme: Theme, preview := false) -> void:
	_previewing=preview
	hydrate_bindings();controller=component
	authored_theme=custom_theme if custom_theme!=null else theme
	if authored_theme:theme=authored_theme
	if is_instance_valid(controls):
		controls.visible=false
		controls.viewer=null if preview else component
		if authored_theme:controls.theme=authored_theme
		if not preview:
			controls.force_native=false;get_viewport().gui_embed_subwindows=true
			controls.close_requested.connect(func():_emit("controls",{"value":false}))
	if preview:show_preview()

func _wire_standard_controls() -> void:
	if fields.has("backend_choice"):
		tag_action(fields.backend_choice,"renderer")
		fields.backend_choice.item_selected.connect(func(value):_emit("renderer",{"native":value==1}))
	if is_instance_valid(overlay_check):
		tag_action(overlay_check,"performance")
		overlay_check.toggled.connect(func(value):_emit("performance",{"value":value}))
	for key in metric_checks:
		var metric: String=key
		tag_action(metric_checks[key],"metric",{"name":metric})
		metric_checks[key].toggled.connect(func(value):_emit("metric",{"name":metric,"value":value}))
	for node in find_children("*","Control",true,false):
		if node is SpinBox and node.prefix=="Steps ":fields.step_count=node
		if node is Button:
			var action_id: String={"Godot: 精确步进 N 次":"step","Godot: 记录完整快照":"capture_snapshot","Godot: 恢复完整快照":"restore_snapshot"}.get(node.text,"")
			if not action_id.is_empty():
				tag_action(node,action_id)
				if action_id=="step":
					fields.step_button=node
					node.pressed.connect(func():fields.step_count.apply();_emit("step",{"count":int(fields.step_count.value)}))
				else:node.pressed.connect(func():_emit(action_id))

func apply_snapshot(snapshot: Dictionary) -> void:
	frame=snapshot.get("frame",{})
	renderer_fps_available=snapshot.get("renderer_fps_available",true);renderer_fps_reason=snapshot.get("renderer_fps_reason","")
	renderer_fps=snapshot.get("renderer_fps",0.0);host_fps=snapshot.get("host_fps",0.0)
	if is_instance_valid(status):
		status.text="预览数据" if Engine.is_editor_hint() else "Godot 附加功能\n"+(runtime_world.rendering_status() if is_instance_valid(runtime_world) else "未绑定")+"\n"+feedback
	if fields.has("backend_choice"):
		fields.backend_choice.select(1 if is_instance_valid(runtime_world) and runtime_world.native_view_experimental else 0)
	refresh_hud();refresh_feedback()

func apply_ui_theme() -> void:
	if authored_theme:return
	native_theme=SimulateUI.make_theme(ui_color,ui_spacing,ui_font);theme=native_theme
	if is_instance_valid(controls):controls.theme=native_theme
	layout_changed.emit()

func _layout_updated() -> void:
	if render_rect.size.x<=0 or render_rect.size.y<=0:render_rect=Rect2(Vector2.ZERO,size)
	position_hud();refresh_feedback()

func add_extension(key: String, title: String, widget: Control) -> void:
	if not extras_sections.has("Examples"):return
	if extensions.get(key)!=widget:remove_extension(key)
	if widget.get_parent():widget.get_parent().remove_child(widget)
	widget.set_meta("extras_title",title)
	extras_sections.Examples.box.add_child(widget);extensions[key]=widget

func remove_extension(key: String) -> void:
	var widget: Control=extensions.get(key)
	if is_instance_valid(widget):
		# Retire callbacks immediately, before the queued free and replacement bind.
		widget.set_block_signals(true)
		for node in widget.find_children("*","Node",true,false):
			node.set_block_signals(true)
			if node is Control:node.release_focus();node.mouse_filter=Control.MOUSE_FILTER_IGNORE
			if node is Window:node.hide()
		if widget.get_parent():widget.get_parent().remove_child(widget)
		widget.queue_free()
	extensions.erase(key)

func show_preview() -> void:
	if is_instance_valid(status):status.text="预览数据 · 系统指标未采样"
	var marker := Label.new();marker.name="PreviewData";marker.text="Godot 附加功能 · 预览数据 · F5 后绑定真实仿真";marker.position=Vector2(16,10);marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(marker,false,Node.INTERNAL_MODE_BACK)
	if is_instance_valid(controls):
		var preview := PanelContainer.new();preview.name="GodotExtrasPreview";preview.position=Vector2(16,70);preview.custom_minimum_size=Vector2(420,560);preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var stack := VBoxContainer.new();preview.add_child(stack)
		for child in controls.get_children():
			if child is Control:
				var content: Control=child.duplicate();stack.add_child(content);content.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
				content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.size_flags_vertical=Control.SIZE_EXPAND_FILL
				if content is ScrollContainer:content.custom_minimum_size=content.custom_minimum_size.max(Vector2(380,480))
				for descendant in content.find_children("*","Node",true,false):descendant.owner=null
				content.owner=null
		add_child(preview,false,Node.INTERNAL_MODE_BACK)
	if is_instance_valid(status):status.text="预览数据 · 系统指标未采样"
	for node in find_children("*","Control",true,false):node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(hud):hud.text="FPS — · 预览数据";position_hud()

func set_controls_visible(value: bool) -> void:
	cancel_gesture()
	for popup in managed_popups.duplicate():
		if is_instance_valid(popup): popup.hide()
	if not is_instance_valid(controls): return
	if value:
		var bounds := get_window().size
		controls.size=Vector2i(clampi(controls.size.x,360,maxi(360,bounds.x-24)),clampi(controls.size.y,240,maxi(240,bounds.y-48)))
		controls.position=Vector2i(clampi(controls.position.x,0,maxi(0,bounds.x-controls.size.x)),clampi(controls.position.y,32,maxi(32,bounds.y-controls.size.y)))
		controls.show();controls.grab_focus()
	else:controls.hide()
	save_preferences()

func set_overlay(value: bool) -> void:
	overlay_enabled=value
	if is_instance_valid(overlay_check):overlay_check.set_pressed_no_signal(value)
	if is_instance_valid(hud):refresh_hud()
	save_preferences()

func refresh_hud() -> void:
	if not is_instance_valid(hud):return
	hud.visible=overlay_enabled
	if not overlay_enabled: return
	var lines := PackedStringArray()
	hud.tooltip_text=renderer_fps_reason
	if metrics.fps and not renderer_fps_available:
		lines.append("Godot host FPS %.1f · target FPS unavailable" % host_fps)
	elif metrics.fps:
		lines.append("FPS %.1f%s" % [renderer_fps," · Godot host %.1f" % host_fps if is_instance_valid(runtime_world) and runtime_world.native_view_active else ""])
	for metric in ["cpu","gpu"]:
		if metrics[metric]: lines.append("System CPU %.1f%%" % system_metrics[metric] if metric=="cpu" and system_metrics.has(metric) else "GPU %.1f%%" % system_metrics[metric] if system_metrics.has(metric) else metric.to_upper()+" unavailable")
	for metric in ["ram","vram"]:
		if metrics[metric]: lines.append("%s %.2f / %.2f GiB" % ["System RAM" if metric=="ram" else "GPU VRAM",system_metrics.get(metric,0)/1073741824.0,system_metrics.get(metric+"_total",0)/1073741824.0] if system_metrics.has(metric) else metric.to_upper()+" unavailable")
	if metrics.timing:
		var stats: Dictionary=frame.get("stats",{})
		if stats.get("timing_available",false):lines.append("Physics CPU %.3f ms" % stats.get("cpu_ms",0))
		else:lines.append("Physics CPU timing unavailable")
		if is_instance_valid(runtime_world) and runtime_world.native_view_active:
			var native: Dictionary=runtime_world.native_view.latest
			if native.get("mujoco_render_gpu_ms",-1)>=0: lines.append("MuJoCo render GPU %.3f ms" % native.mujoco_render_gpu_ms)
			else: lines.append("MuJoCo GPU timing unavailable")
		else: lines.append("Godot GPU timing unavailable on the current display path")
	hud.text="\n".join(lines)
	hud.size=hud.get_combined_minimum_size()
	position_hud()

func position_hud() -> void:
	if not automatic_overlay_layout or not is_instance_valid(hud):return
	if _previewing:hud.position=Vector2(16,36);return
	if render_rect.size.x<=16 or render_rect.size.y<=16:return
	var extent := hud.size.max(hud.get_combined_minimum_size())
	var layout: Array=[render_rect,extent,overlay_exclusions]
	if layout==_last_hud_layout:return
	_last_hud_layout=layout.duplicate(true)
	# Use the shared source-space occupancy values, transformed by the Extras
	# controller into this UI. No dependency on an installed original panel.
	var bounds := render_rect.grow(-8)
	var preferred := render_rect.position+Vector2(maxf(8,render_rect.size.x-extent.x-8),42)
	var xs: Array[float]=[preferred.x,bounds.position.x,bounds.end.x-extent.x]
	var ys: Array[float]=[preferred.y,bounds.position.y,bounds.end.y-extent.y]
	for rect in overlay_exclusions:
		xs.append(rect.position.x-extent.x-8);xs.append(rect.end.x+8)
		ys.append(rect.position.y-extent.y-8);ys.append(rect.end.y+8)
	var best := preferred
	var distance := INF
	for x in xs:
		for y in ys:
			var candidate := Rect2(Vector2(x,y),extent)
			if not bounds.encloses(candidate):continue
			if overlay_exclusions.any(func(rect):return rect.grow(4).intersects(candidate)):continue
			var score := candidate.position.distance_squared_to(preferred)
			if score<distance:best=candidate.position;distance=score
	hud.position=best
	refresh_feedback()

func refresh_feedback() -> void:
	if not is_instance_valid(feedback_label):return
	feedback_label.text=feedback
	feedback_label.visible=not feedback.is_empty() and Time.get_ticks_msec()<feedback_deadline
	if not automatic_overlay_layout:return
	feedback_label.size.x=maxf(1,render_rect.size.x-16)
	var y := 42.0
	if is_instance_valid(hud) and hud.visible and not hud.text.is_empty():y+=maxf(hud.size.y,hud.get_combined_minimum_size().y)+8
	feedback_label.position=render_rect.position+Vector2(8,y)
