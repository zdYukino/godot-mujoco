extends Window
## Embedded windows have their own viewport input dispatch.
var viewer: Node
func _input(event: InputEvent) -> void:
	if is_instance_valid(viewer): viewer.global_input(event, self)
func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(viewer) and viewer.key_input(event): set_input_as_handled()
