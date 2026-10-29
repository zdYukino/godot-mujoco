@tool
extends EditorProperty
const Collision = preload("res://addons/godot_mujoco/model/collision_settings.gd")
var key := ""
var options: OptionButton
var number: SpinBox
var unlimited: CheckBox
var warning: Label
var info: Label
var jump: Button
var updating := false

func _init(field: String) -> void:
	key = field.trim_prefix("mjcf/collision_")
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	match key:
		"mode", "sdf_depth":
			options = OptionButton.new(); options.fit_to_longest_item = false
			options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(options); add_focusable(options)
			if key == "mode":
				for value in ["hull","sdf","native"]:
					options.add_item({"hull":"凸包","sdf":"SDF","native":"原生几何"}[value])
					options.set_item_metadata(options.item_count-1,value)
			else:
				options.add_item("引擎默认（6）",0)
				for depth in range(3,9): options.add_item(str(depth),depth)
				warning = Label.new(); warning.text = "!"
				warning.tooltip_text = Collision.DEPTH_WARNING
				warning.add_theme_color_override("font_color",Color("ffc65c"))
				warning.mouse_filter = Control.MOUSE_FILTER_STOP
				row.add_child(warning)
			options.item_selected.connect(func(index):
				if not updating: emit_changed(get_edited_property(),options.get_item_metadata(index) if key == "mode" else options.get_item_id(index)))
		"maxhullvert":
			unlimited = CheckBox.new(); unlimited.text = "不限"
			row.add_child(unlimited); add_focusable(unlimited)
			number = SpinBox.new(); number.min_value = 4; number.max_value = 100000; number.allow_greater = true
			number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(number); add_focusable(number.get_line_edit())
			row.tooltip_text = "标准 MJCF maxhullvert；简化凸包可能改变自动计算的质量和惯量。"
			unlimited.toggled.connect(func(checked):
				if not updating: emit_changed(get_edited_property(),-1 if checked else int(number.value)))
			number.value_changed.connect(func(value):
				if not updating: emit_changed(get_edited_property(),int(value)))
		_:
			info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.custom_minimum_size.x = 70
			row.add_child(info)
			if key == "world":
				jump = Button.new(); jump.text = "→"; jump.tooltip_text = "跳转到所属 World 的碰撞设置"
				row.add_child(jump)
				jump.pressed.connect(func():
					var target: Node = get_edited_object().author_model().find_world()
					if target:
						EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(target)
						EditorInterface.inspect_object(target))

func _update_property() -> void:
	var target := get_edited_object()
	if not target: return
	updating = true
	var value: Variant = target.get(get_edited_property())
	match key:
		"mode":
			for index in options.item_count:
				if options.get_item_metadata(index) == value: options.select(index)
			options.set_item_disabled(2,value != "native")
			options.disabled = value == "native" or is_read_only()
		"sdf_depth":
			options.select(options.get_item_index(int(value)))
			warning.visible = int(value) != 0
		"maxhullvert":
			unlimited.set_pressed_no_signal(int(value) == -1)
			number.editable = int(value) != -1
			if int(value) >= 4: number.set_value_no_signal(int(value))
		_:
			info.text = str(value)
			info.tooltip_text = info.text
			if jump: jump.disabled = target.author_model().find_world() == null
	updating = false
