@tool
extends RefCounted

# Godot controls only; groups do not own or modify any document state.
static func group(parent: Node, title: String, expanded := true) -> VBoxContainer:
	var toggle := Button.new()
	toggle.text = title
	toggle.toggle_mode = true
	toggle.button_pressed = expanded
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(toggle)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.visible = expanded
	parent.add_child(content)
	toggle.toggled.connect(content.set_visible)
	return content

static func fit(node: Node) -> void:
	if node is Label:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if node is LineEdit:
		node.custom_minimum_size.x = clampf(node.custom_minimum_size.x, 120, 240)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if node is Button and not node is OptionButton:
		# Wrapped buttons otherwise advertise only their margins to HFlowContainer,
		# collapsing text into a one-character-wide column.
		node.custom_minimum_size.x = clampf(node.get_minimum_size().x, 100, 240)
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if node is OptionButton:
		node.fit_to_longest_item = false
		node.clip_text = true
		node.custom_minimum_size.x = clampf(node.custom_minimum_size.x, 140, 240)
	if node is TextEdit: node.custom_minimum_size.x = 0
	for child in node.get_children(): fit(child)
