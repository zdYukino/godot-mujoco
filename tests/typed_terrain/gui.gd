extends "res://addons/godot_mujoco/model/runtime_world.gd"
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var terrain=$Terrain
	match event.keycode:
		KEY_U: terrain.design.heights[0]+=0.2
		KEY_A: terrain.request_apply()
		KEY_D: terrain.request_remove()
		KEY_P: request_pause(not info().paused)
func _process(_delta: float) -> void:
	super._process(_delta)
	$Status.text="Heightfield: U changes design corner; A applies/adds; D removes; P pauses\nrevision=%s pending=%s dirty=%s error=%s" % [$Terrain.revision,$Terrain.pending_request,$Terrain.dirty(),$Terrain.last_error]
