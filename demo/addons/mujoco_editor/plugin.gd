@tool
extends EditorPlugin
const State = preload("editor_state.gd")
const EditorPanel = preload("panel.gd")
var live_debugger: EditorDebuggerPlugin
var panel: Control
var state: RefCounted
const META := "mujoco_editor_document"

func _enter_tree() -> void:
	if not ClassDB.class_exists("MjEditorDocument"):
		push_error("MuJoCo editor requires the rebuilt Linux godot_mujoco GDExtension. Build and restart the editor.")
		return
	live_debugger = preload("live_debugger.gd").new()
	add_debugger_plugin(live_debugger)
	var base := EditorInterface.get_base_control()
	state = base.get_meta(META) if base.has_meta(META) else State.new()
	base.set_meta(META, state)
	state.activate()
	panel = EditorPanel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.plugin = self
	panel.state = state
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.hide()
	if "--mj-editor-test" in OS.get_cmdline_user_args() and not base.has_meta("mj_test_started"):
		base.set_meta("mj_test_started", true)
		call_deferred("_run_acceptance")

func _exit_tree() -> void:
	if live_debugger:
		live_debugger.shutdown()
		remove_debugger_plugin(live_debugger)
		live_debugger = null
	if panel:
		panel.shutdown()
		panel.free()
		panel = null
	if state:
		state.deactivate()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "MuJoCo"

func _make_visible(value: bool) -> void:
	if panel:
		panel.visible = value
		if not value and state.document:
			state.document.set_paused(true)

func _save_external_data() -> void:
	if panel:
		panel.save_recovery()

func _get_unsaved_status(_for_scene: String) -> String:
	return "MuJoCo document has unsaved edits. Use Save document; recovery is retained under user://." if state and (state.dirty or (panel and panel.pending)) else ""

func _run_acceptance() -> void:
	var script = load("res://acceptance.gd")
	if script:
		var runner = script.new()
		EditorInterface.get_base_control().set_meta("mj_test_runner", runner)
		runner.run(self)
