@tool
extends Control
## Shared action wiring only; each concrete presenter owns its own UI and data.
signal action_requested(action_id: StringName, arguments: Dictionary)
signal layout_changed
var controller: Node

func _emit(action_id: StringName, arguments: Dictionary = {}) -> void:
	if Engine.is_editor_hint(): return
	action_requested.emit(action_id,arguments)

func cancel_gesture(_release := false) -> void:
	if is_instance_valid(controller): controller.cancel_interaction()

func save_preferences() -> void:
	if is_instance_valid(controller): controller.save_view_preferences()

func manage_popup(popup: Window) -> void:
	if is_instance_valid(controller) and not Engine.is_editor_hint(): controller.manage_popup(popup)

func is_embedded_game() -> bool:
	return not Array(OS.get_cmdline_args()).filter(func(value):return value=="--wid" or value.begins_with("--wid=")).is_empty()

func tag_action(widget: Control, action_id: StringName, arguments: Dictionary = {}) -> void:
	widget.set_meta("viewer_action",action_id);widget.set_meta("viewer_arguments",arguments)
	if not widget is BaseButton and not widget is Range:
		for child in widget.get_children():
			if child is BaseButton:child.set_meta("viewer_action",action_id);child.set_meta("viewer_arguments",arguments)

func get_action_control(action_id: StringName) -> Control:
	for node in find_children("*","Control",true,false):
		if node.get_meta("viewer_action","")==action_id: return node
	return null

func _wire_authored_action(widget: Control) -> void:
	var action_id: StringName=widget.get_meta("viewer_bind_action")
	var arguments: Dictionary=widget.get_meta("viewer_bind_arguments",{})
	var parameter := str(widget.get_meta("viewer_bind_parameter","value"))
	tag_action(widget,action_id,arguments)
	if widget is CheckBox:
		widget.toggled.connect(func(value):var args := arguments.duplicate();args[parameter]=value;_emit(action_id,args))
	elif widget is OptionButton:widget.item_selected.connect(func(value):var args := arguments.duplicate();args[parameter]=value;_emit(action_id,args))
	elif widget is BaseButton:widget.pressed.connect(func():_emit(action_id,arguments))
	elif widget is Range:widget.value_changed.connect(func(value):var args := arguments.duplicate();args[parameter]=value;_emit(action_id,args))
	elif widget is LineEdit:widget.text_submitted.connect(func(value):var args := arguments.duplicate();args[parameter]=value;_emit(action_id,args))

func _wire_button(widget: BaseButton, action_id: StringName, args: Dictionary = {}) -> void:
	tag_action(widget,action_id,args);widget.pressed.connect(func():_emit(action_id,args))
