@tool
extends RefCounted
const Terrain=preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Grid=preload("res://addons/godot_mujoco/model/heightfield_data.gd")
var passed:=0
var failed:=0
func check(ok:bool,label:String):
	if ok:passed+=1;print("PASS ",label)
	else:failed+=1;printerr("FAIL ",label)
func run(plugin:EditorPlugin):
	var root:=Node3D.new();root.name="TerrainScene"
	for label in ["First","Second"]:
		var node:=Terrain.new();node.name=label;node.design=Grid.new();root.add_child(node);node.owner=root
	var scene:=PackedScene.new();scene.pack(root);ResourceSaver.save(scene,"res://TerrainScene.tscn");root.free()
	EditorInterface.get_resource_filesystem().scan()
	for i in 8:await plugin.get_tree().process_frame
	EditorInterface.open_scene_from_path("res://TerrainScene.tscn")
	for i in 8:await plugin.get_tree().process_frame
	root=EditorInterface.get_edited_scene_root()
	var first=root.get_node("First");var second=root.get_node("Second")
	var panel=plugin.heightfield_panel
	check(panel.select_target(first),"select scene terrain")
	panel.heights.text="0 1\n2 3";panel.heights.text_changed.emit()
	check(panel.dirty and panel.preview_text(),"dirty draft previews")
	check(first.design.heights==PackedFloat32Array([0,0,0,0]),"preview leaves authored data untouched")
	check(not panel.select_target(second) and panel.target==first,"selection switch retains draft target")
	check(panel.apply_scene(),"apply scene design")
	check(first.design.heights==PackedFloat32Array([0,1,2,3]) and not panel.dirty,"apply updates selected design")
	check(second.design.heights==PackedFloat32Array([0,0,0,0]),"second terrain isolated")
	check(panel.apply_scene(),"repeated apply is no-op")
	panel.undo_scene()
	check(first.design.heights==PackedFloat32Array([0,0,0,0]),"undo restores scene design")
	panel.heights.text="0 nan 0 0";panel.heights.text_changed.emit()
	check(not panel.apply_scene() and not panel.error.is_empty(),"invalid text rejected")
	panel.discard();check(not panel.dirty and panel.draft.heights==PackedFloat32Array([0,0,0,0]),"discard resets draft")
	panel.heights.text="1 2";panel.heights.text_changed.emit();check(not panel.preview_text(),"sample count rejected")
	panel.discard();check(panel.select_target(second),"selection proceeds after discard")
	panel.heights.text="4 3 2 1";panel.heights.text_changed.emit();panel.apply_scene();panel.save_scene()
	var reopened=load("res://TerrainScene.tscn").instantiate()
	check(reopened.get_node("Second").design.heights==PackedFloat32Array([4,3,2,1]),"save reopen authored grid");reopened.free()
	panel.select_target(null);panel.width.value=3;panel.depth.value=4;panel.create_terrain()
	check(root.get_child_count()==3,"create terrain through plugin action")
	var created=root.get_child(2)
	check(created.design.width==3 and created.design.depth==4 and created.design.heights.size()==12,"create selected fixed resolution")
	panel.discard();panel.select_target(created);panel.undo_scene()
	check(root.get_child_count()==2,"creation undo")
	panel.discard();panel.select_target(first)
	panel.debugger.instances["test:busy"]={"path":"/busy","id":"busy","revision":3,"pending":true,"error":"","session":0}
	panel.refresh_live();panel.selected_key="test:busy"
	check(not panel.apply_live(),"pending runtime target rejects repeat Apply")
	panel.debugger.instances.clear();panel.refresh_live()
	check(panel.selected_key.is_empty() and not panel.remove_live(),"stopped runtime target cannot receive remove")
	var report={"passed":passed,"failed":failed}
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):path=arg.trim_prefix("--report=")
	if not path.is_empty():var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report))
	print("TERRAIN_PANEL_RESULT ",JSON.stringify(report));plugin.get_tree().quit(0 if failed==0 else 1)
