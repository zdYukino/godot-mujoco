extends SceneTree
# Shared orchestration only. Geometry expectations stay in each risk-specific test.
var passed:=0
var failed:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failed+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(n: int) -> void:
	for i in n:await physics_frame;await process_frame
