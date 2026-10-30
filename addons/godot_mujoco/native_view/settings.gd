@tool
extends RefCounted
## Project choice for the next game process; editing stays in the Godot viewport.
const MODE := "rendering/mujoco_native_view/renderer"
const INHERIT := -1
const GODOT := 0
const MUJOCO := 1

static func register_project_settings() -> void:
	if not ProjectSettings.has_setting(MODE): ProjectSettings.set_setting(MODE, INHERIT)
	ProjectSettings.set_initial_value(MODE, INHERIT)
	ProjectSettings.add_property_info({"name":MODE,"type":TYPE_INT,"hint":PROPERTY_HINT_ENUM,"hint_string":"Scene default:-1,Godot:0,MuJoCo native:1"})
	ProjectSettings.set_as_basic(MODE, true)

static func mode() -> int:
	var value: int = int(ProjectSettings.get_setting(MODE, INHERIT))
	return value if value in [INHERIT, GODOT, MUJOCO] else GODOT

static func requested(scene_default := false) -> bool:
	return scene_default if mode() == INHERIT else mode() == MUJOCO

static func unavailable_reason() -> String:
	if OS.get_name() != "Linux" or not OS.has_feature("x86_64"):
		return "原生渲染目前支持 Linux x86_64。"
	if DisplayServer.get_name() != "X11": return "原生渲染需要 X11 图形会话。"
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		return "原生渲染需要项目使用 Compatibility / OpenGL。"
	if ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false):
		return "原生渲染需要关闭物理独立线程。"
	if not ClassDB.class_exists("MjSharedNativeViewBridge") or not PhysicsServer3D.has_method("scene_native_view_snapshot"):
		return "原生渲染库尚未加载：按 README 构建后重新打开编辑器，并选择 MuJoCo 物理引擎。"
	return ""

static func save_mode(value: int) -> Error:
	if value not in [GODOT, MUJOCO]: return ERR_INVALID_PARAMETER
	if value == MUJOCO and not unavailable_reason().is_empty(): return ERR_UNAVAILABLE
	var previous := mode()
	ProjectSettings.set_setting(MODE, value)
	var error := ProjectSettings.save()
	if error != OK: ProjectSettings.set_setting(MODE, previous)
	return error
