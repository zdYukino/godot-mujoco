extends "res://addons/godot_mujoco/model/runtime_world.gd"
func _unhandled_key_input(event):
 if event is InputEventKey and event.pressed and not event.echo:
  if event.keycode==KEY_P:request_pause(not info().paused)
  if event.keycode==KEY_S:step_simulation(100)
func _process(delta):
 super._process(delta)
 var text="P pause/resume; S step100. Apply good.json / bad-last.json from editor runtime preset button.\n"
 for node in [$First,$Second]:
  var value=node.state()
  text+="%s revision=%s pending=%s controls=%s gains=%s result=%s\n" % [node.name,value.get("property_revision",-1),node.edit_request,value.get("controls",{}),value.get("actuator_parameters",{}),node.last_preset_result.get("status","")]
 $Status.text=text
