extends SceneTree
# Deliberately unresponsive native-worker stand-in: only an OS process kill can stop it.
func _initialize() -> void:
	while true: OS.delay_msec(100)
