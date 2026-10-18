@tool
extends "res://mouse_probe.gd"
# 不预先导入或构造模型；由真实鼠标操作 Import/Open。
func run(p: EditorPlugin) -> void:
 plugin=p
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--probe-dir="):folder=arg.trim_prefix("--probe-dir=")
 DirAccess.make_dir_recursive_absolute(folder)
 EditorInterface.set_main_screen_editor("MuJoCo")
 plugin.get_tree().process_frame.connect(tick)
