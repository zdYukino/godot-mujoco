@tool
extends Window
## Embedded windows have their own viewport input dispatch.
var viewer: Node
func _ready() -> void:
	if Engine.is_editor_hint():
		set_process_input(false);set_process_unhandled_key_input(false)
func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint() and is_instance_valid(viewer):viewer.global_input(event,self)
func _unhandled_key_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint() and is_instance_valid(viewer) and viewer.key_input(event):set_input_as_handled()
