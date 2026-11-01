@tool
class_name MjCompileService
extends Node
## Compilation runs in a killable Godot worker process with no scene loaded.
## Worker output consists only of serialized values and an MJB, never objects.
signal completed(result: Dictionary)
signal status_changed(status: String)
const WorkerPath := "res://addons/godot_mujoco/model/compile_worker.gd"
var timeout_seconds := 120.0
var active: Dictionary = {}
var queued: Dictionary = {}
var process_id := -1
var started_ms := 0
var serial := 0
var session_id := ""
var worker_script := WorkerPath

func _ready() -> void:
	timeout_seconds = float(ProjectSettings.get_setting("mujoco/authoring/compile_timeout_seconds", timeout_seconds))
	session_id = Crypto.new().generate_random_bytes(12).hex_encode()
	process_mode = Node.PROCESS_MODE_ALWAYS

func submit(request: Dictionary) -> int:
	serial += 1
	queued = request.duplicate(true)
	queued.job_id = serial
	if not active.is_empty(): _terminate("superseded", false)
	_start()
	return serial

func cancel() -> void:
	queued.clear()
	_terminate("cancelled", true)

func busy() -> bool:
	return not active.is_empty() or not queued.is_empty()

func _start() -> void:
	if queued.is_empty() or not active.is_empty(): return
	if session_id.is_empty(): session_id = Crypto.new().generate_random_bytes(12).hex_encode()
	active = queued
	queued = {}
	var directory := "user://mujoco_compile/" + session_id + "/" + str(active.job_id)
	DirAccess.make_dir_recursive_absolute(directory)
	active.directory = ProjectSettings.globalize_path(directory)
	var input := FileAccess.open(directory.path_join("request.bin"), FileAccess.WRITE)
	if not input:
		_finish({"success":false, "error":"Cannot create compiler request"})
		return
	input.store_var(active)
	input.close()
	started_ms = Time.get_ticks_msec()
	process_id = OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--log-file", active.directory.path_join("worker.log"), "--script", worker_script, "--", active.directory]))
	if process_id < 0:
		_finish({"success":false, "error":"Cannot start isolated MuJoCo compiler"})
		return
	status_changed.emit("正在后台验证保存的预览（必要时编译）" if active.get("op") == "verify_or_compile" else "正在后台编译")

func _process(_delta: float) -> void:
	if active.is_empty(): return
	if Time.get_ticks_msec() - started_ms > timeout_seconds * 1000.0:
		_terminate("编译超时（%.0f 秒）；可继续编辑或恢复已提交设计" % timeout_seconds, true)
		return
	var result_path: String = active.directory.path_join("result.bin")
	if FileAccess.file_exists(result_path):
		if process_id > 0 and OS.is_process_running(process_id): return
		var file := FileAccess.open(result_path, FileAccess.READ)
		var value: Variant = file.get_var(false) if file else null
		var exit_code := OS.get_process_exit_code(process_id)
		if exit_code not in [-1, 0]: _finish({"success":false, "error":"Compiler exited with code " + str(exit_code)})
		elif value is Dictionary: _finish(value)
		else: _finish({"success":false, "error":"Invalid compiler result"})
	elif process_id > 0 and not OS.is_process_running(process_id):
		_finish({"success":false, "error":"Compiler process exited without a result"})

func _finish(result: Dictionary) -> void:
	var token := active.duplicate(true)
	# The result is atomically published at the very end of the worker task.
	if process_id > 0 and OS.is_process_running(process_id): OS.kill(process_id)
	process_id = -1
	active = {}
	result.job_id = token.get("job_id", 0)
	result.generation = token.get("generation", "")
	result.revision = token.get("revision", 0)
	result.directory = token.get("directory", "")
	status_changed.emit("编译完成" if result.get("success", false) else str(result.get("error", "编译失败")))
	completed.emit(result)
	_start()

func _terminate(reason: String, notify_result: bool) -> void:
	if active.is_empty(): return
	if process_id > 0 and OS.is_process_running(process_id): OS.kill(process_id)
	process_id = -1
	if notify_result: _finish({"success":false, "error":reason, "cancelled":true})
	else:
		active = {}
		process_id = -1

func _exit_tree() -> void:
	queued.clear()
	_terminate("Compiler service closed", false)
