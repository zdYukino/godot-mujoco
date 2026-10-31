@tool
extends HBoxContainer
## mjITEM_RADIO adaptation: equal-width mutually exclusive buttons.
signal item_selected(index: int)
var buttons: Array[Button] = []
func _ready() -> void:
	# Authored scenes serialize buttons; bind their signals without recreating them.
	if not buttons.is_empty(): return
	for child in get_children():
		if child is Button:
			var id := buttons.size();buttons.append(child);child.pressed.connect(func():item_selected.emit(id))
func setup(options: Array, selected: int) -> void:
	var group := ButtonGroup.new()
	for index in options.size():
		var button := Button.new();button.text=options[index];button.toggle_mode=true;button.theme_type_variation="MuJoCoRadio";button.button_group=group;button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;add_child(button)
		var id: int=index;button.pressed.connect(func():item_selected.emit(id));buttons.append(button)
	select(selected)
func select(index: int) -> void:
	for id in buttons.size(): buttons[id].set_pressed_no_signal(id==index)
