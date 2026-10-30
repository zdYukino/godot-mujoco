extends Control
## Show each native control's shortcut in place while the UI right button is held.
var panel: Control
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;clip_contents=true;visible=false
func _draw() -> void:
	if not is_instance_valid(panel): return
	var font := ThemeDB.fallback_font
	for control in panel.find_children("*","Control",true,false):
		if not control.is_visible_in_tree() or not control.has_meta("mujoco_shortcut"): continue
		var shortcut: String=control.get_meta("mujoco_shortcut")
		if shortcut.is_empty(): continue
		var rect: Rect2=control.get_global_rect();var width := font.get_string_size(shortcut,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+6
		var position := rect.position-global_position+Vector2(maxf(0,rect.size.x-width),0)
		draw_rect(Rect2(position,Vector2(width,15)),Color(.2,.15,.06,.95))
		draw_string(font,position+Vector2(3,12),shortcut,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color(1,.85,.5))
