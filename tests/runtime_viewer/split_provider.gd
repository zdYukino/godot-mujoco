extends Node
## Test provider: help must never allocate a widget; tools close over this World.
var help_reads := 0
var widget_builds := 0
var presses := 0
func get_viewer_help() -> Dictionary:
	help_reads+=1
	return {"key":"split_provider","title":"Independent provider","text":"Help from world "+str(get_parent().get_instance_id())}
func register_extras(component: Node) -> String:
	widget_builds+=1
	var button := Button.new()
	button.text="Pause this provider's World"
	button.set_meta("provider_world",get_parent().get_instance_id())
	button.pressed.connect(func():
		presses+=1
		get_parent().set_paused(true))
	component.add_extension("split_provider","Independent provider",button)
	return "split_provider"
