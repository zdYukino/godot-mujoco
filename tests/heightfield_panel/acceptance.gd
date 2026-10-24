@tool
extends RefCounted
const Terrain=preload("res://addons/godot_mujoco/model/static_heightfield.gd")
const Grid=preload("res://addons/godot_mujoco/model/heightfield_data.gd")
class FakeDebugger extends EditorDebuggerPlugin:
	signal changed
	var instances={"test":{"id":"test","path":"/Terrain","revision":1,"pending":false}}
	var outcomes={}
	var sent:Dictionary={}
	func send(_key:String,operation:String,payload:Dictionary) -> bool:
		sent={"operation":operation,"payload":payload.duplicate(true)}
		return true
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
	var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(first))
	history.undo() # Native scene history, not the panel's undo callback.
	for i in 2:await plugin.get_tree().process_frame
	check(first.design.heights==PackedFloat32Array([0,0,0,0]) and panel.draft.heights==first.design.heights and not panel.dirty,"native undo synchronizes selected panel")
	check(panel.apply_scene(),"apply after native undo uses refreshed fields")
	panel.save_scene()
	var undo_saved=ResourceLoader.load("res://TerrainScene.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(undo_saved.get_node("First").design.heights==PackedFloat32Array([0,0,0,0]),"save after native undo matches panel and scene");undo_saved.free()
	history.redo()
	for i in 2:await plugin.get_tree().process_frame
	check(panel.draft.heights==first.design.heights and panel.draft.heights==PackedFloat32Array([0,1,2,3]),"native redo synchronizes selected panel")
	panel.undo_scene()
	check(first.design.heights==PackedFloat32Array([0,0,0,0]),"undo restores scene design")
	# Inspector uses property setters; direct in-place resource edits may emit no changed signal.
	first.design.set("heights",PackedFloat32Array([2,2,2,2]))
	for i in 2:await plugin.get_tree().process_frame
	check(panel.draft.heights==first.design.heights and not panel.dirty,"Inspector resource edit refreshes clean draft")
	first.set("collision_layer",8)
	for i in 2:await plugin.get_tree().process_frame
	check(int(panel.layer.value)==8,"Inspector mask edit refreshes fields")
	panel.heights.text="7 7 7 7";panel.heights.text_changed.emit()
	first.design.heights[0]=3
	check(not panel.apply_scene(),"external change checked synchronously before Apply")
	check(panel.external_conflict and panel.heights.text=="7 7 7 7" and first.design.heights[0]==3,"dirty conflict retains text and external design")
	panel.save_scene();check(panel.external_conflict and panel.dirty,"conflicted draft blocks panel save")
	check(panel.rebase_draft() and panel.heights.text=="7 7 7 7","explicit rebase preserves user text")
	check(panel.apply_scene() and first.design.heights==PackedFloat32Array([7,7,7,7]),"explicit rebase permits deliberate overwrite")
	history.undo()
	for i in 2:await plugin.get_tree().process_frame
	check(panel.draft.heights[0]==3 and first.design.heights[0]==3,"undo rebased edit restores external design")
	panel.heights.text="8 8 8 8";panel.heights.text_changed.emit()
	var replacement=Grid.new();replacement.width=3;replacement.depth=2;replacement.heights=PackedFloat32Array([1,2,3,4,5,6]);first.set("design",replacement)
	for i in 2:await plugin.get_tree().process_frame
	check(panel.external_conflict and not panel.rebase_draft() and panel.heights.text=="8 8 8 8","replacement dimensions preserve conflicting draft")
	panel.discard();check(panel.draft.width==3 and panel.draft.heights.size()==6 and not panel.external_conflict,"Discard adopts replaced resource")
	first.design.heights[0]=NAN
	for i in 2:await plugin.get_tree().process_frame
	panel.heights.text="1 2 3 4 5 6";panel.heights.text_changed.emit()
	check(panel.apply_scene() and first.design.heights[0]==1,"invalid Inspector value can be repaired without false conflict")
	first.set("design",Grid.new());first.collision_layer=1
	for i in 2:await plugin.get_tree().process_frame
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
	panel.debugger.instances["0:busy"]={"path":"/busy","id":"busy","revision":3,"pending":true,"error":"","session":0}
	panel.refresh_live();panel.selected_key="0:busy"
	check(not panel.apply_live(),"pending runtime target rejects repeat Apply")
	panel.debugger._capture("mujoco_heightfield:finished",[{"id":"busy","success":true,"revision":4,"request":1,"error":""}],0)
	panel.debugger.instances["0:busy"].pending=false;panel.refresh_live()
	check(panel.status.text.contains("completed") and panel.status.text.contains("4"),"completion outcome shown separately from acceptance")
	panel.debugger.session_stopped(0);panel.refresh_live()
	check(panel.selected_key.is_empty() and not panel.remove_live(),"stopped runtime target cannot receive remove")
	panel.debugger.instances={"0:a":{"path":"/worldA/Terrain","id":"a","revision":2,"pending":false,"error":"","session":0},"1:b":{"path":"/worldB/Terrain","id":"b","revision":1,"pending":true,"error":"","session":1}}
	panel.debugger.outcomes={"0:a":{"success":true,"revision":2,"error":""}}
	panel.refresh_live();choose_live(panel,"0:a")
	check(panel._runtime_status()=="completed revision=2","select A immediately loads A completion")
	choose_live(panel,"1:b");check(panel._runtime_status()=="pending" and not panel.status.text.contains("completed"),"select B pending never shows A result")
	panel.debugger._capture("mujoco_heightfield:finished",[{"id":"a","success":false,"revision":2,"request":8,"error":"A rejected"}],0)
	check(panel._runtime_status()=="pending" and not panel.status.text.contains("A rejected"),"unselected A failure does not contaminate B")
	choose_live(panel,"0:a");check(panel._runtime_status()=="failed: A rejected","switch back reads failure without another debugger event")
	panel.debugger.instances["1:b"].pending=false;choose_live(panel,"1:b")
	check(panel._runtime_status()=="idle" and not panel.status.text.contains("A rejected"),"target without result clears previous feedback")
	panel.debugger._capture("mujoco_heightfield:finished",[{"id":"b","success":true,"revision":9,"request":9,"error":""}],1)
	choose_live(panel,"0:a");check(panel._runtime_status()=="failed: A rejected","B success remains isolated from A failure")
	panel.debugger.instances["0:a"].pending=true;panel._show_status();check(panel._runtime_status()=="pending","new pending takes precedence over prior outcome")
	panel.debugger.session_stopped(0);panel.debugger.session_stopped(1)
	check(panel.selected_key.is_empty() and panel._runtime_status()=="未选择" and not panel.status.text.contains("completed"),"session stop clears scoped completion display")
	for i in 2:await plugin.get_tree().process_frame
	check(panel.get_combined_minimum_size().x<=800 and not panel.live.fit_to_longest_item,"wrapping panel minimum fits normal narrow editor")
	# Inspector changes must be part of the editor baseline and the actual debugger payload.
	panel.discard();panel.select_target(first)
	first.physics_material_override=PhysicsMaterial.new();first.physics_material_override.friction=.23
	for i in 2:await plugin.get_tree().process_frame
	check(is_equal_approx(panel.friction.value,.23) and not panel.dirty,"Inspector material refreshes clean draft")
	first.physics_material_override.friction=.67
	var real_debugger=panel.debugger
	real_debugger.changed.disconnect(panel.refresh_live)
	var fake=FakeDebugger.new();panel.debugger=fake;fake.changed.connect(panel.refresh_live);panel.selected_key="test"
	check(panel.apply_live(),"Inspector material sends runtime Apply")
	check(is_equal_approx(fake.sent.payload.snapshot.friction,.67) and fake.sent.payload.snapshot.bounce==0,"fake debugger receives editor friction and bounce, not runtime fallback")
	var payload_file=FileAccess.open("res://panel-material-snapshot.bin",FileAccess.WRITE);payload_file.store_var(fake.sent.payload.snapshot);payload_file.close()
	panel.friction.value=.42;panel.rough.button_pressed=true
	check(panel.dirty and panel.preview_text() and is_equal_approx(first.physics_material_override.friction,.67),"material draft preview leaves scene unchanged")
	first.physics_material_override.friction=.31
	check(not panel.apply_live() and panel.external_conflict and is_equal_approx(panel.friction.value,.42),"Inspector material conflict blocks runtime Apply and retains draft")
	panel.save_scene();check(panel.external_conflict and panel.dirty,"material conflict blocks save")
	check(panel.rebase_draft() and panel.apply_scene(),"explicit rebase commits retained material draft")
	check(is_equal_approx(first.physics_material_override.friction,.42) and first.physics_material_override.rough,"scene material action commits friction and rough")
	history.undo();panel._sync_external()
	check(is_equal_approx(first.physics_material_override.friction,.31) and not first.physics_material_override.rough and is_equal_approx(panel.friction.value,.31),"material Undo restores external baseline and panel")
	history.redo();panel._sync_external()
	check(is_equal_approx(panel.friction.value,.42) and panel.rough.button_pressed,"material Redo refreshes panel")
	check(panel.apply_live() and is_equal_approx(fake.sent.payload.snapshot.friction,-.42),"rough material uses signed runtime friction")
	panel.save_scene()
	var material_saved=ResourceLoader.load("res://TerrainScene.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(is_equal_approx(material_saved.get_node("First").physics_material_override.friction,.42) and material_saved.get_node("First").physics_material_override.rough,"panel material save and reopen");material_saved.free()
	panel.friction.value=.9;panel.discard()
	check(is_equal_approx(panel.friction.value,.42) and not panel.dirty,"material Discard restores saved design")
	first.physics_material_override.bounce=.2;panel._sync_external()
	check(not panel.apply_live() and "Bounce" in panel.error,"unsupported Inspector bounce cannot send successful payload")
	first.physics_material_override.bounce=0;panel.discard()
	fake.changed.disconnect(panel.refresh_live);panel.debugger=real_debugger;real_debugger.changed.connect(panel.refresh_live);panel.selected_key="";panel.refresh_live()
	# Same scene history as an Inspector resource edit, with two owners of one material.
	var shared_material=PhysicsMaterial.new();shared_material.friction=.23
	first.physics_material_override=shared_material;second.physics_material_override=shared_material;panel.discard()
	var manager=plugin.get_undo_redo()
	manager.create_action("Inspector shared terrain friction",UndoRedo.MERGE_DISABLE,first)
	manager.add_do_property(shared_material,"friction",.31);manager.add_undo_property(shared_material,"friction",.23);manager.commit_action()
	panel._sync_external()
	check(is_equal_approx(first.physics_material_override.friction,.31) and second.physics_material_override==shared_material,"Inspector edit updates shared material")
	panel.friction.value=.67
	check(panel.apply_scene() and first.physics_material_override!=shared_material and second.physics_material_override==shared_material and is_equal_approx(shared_material.friction,.31),"panel material Apply isolates selected terrain only")
	history.undo();panel._sync_external()
	check(first.physics_material_override==shared_material and second.physics_material_override==shared_material,"panel Undo restores exact shared resource identity")
	history.undo();panel._sync_external()
	check(first.physics_material_override==shared_material and is_equal_approx(first.physics_material_override.friction,.23) and is_equal_approx(second.physics_material_override.friction,.23),"earlier Inspector Undo reaches both terrain references")
	history.redo();panel._sync_external()
	check(first.physics_material_override==shared_material and is_equal_approx(first.physics_material_override.friction,.31),"Inspector Redo preserves shared identity")
	history.redo();panel._sync_external()
	check(first.physics_material_override!=shared_material and is_equal_approx(first.physics_material_override.friction,.67) and second.physics_material_override==shared_material,"panel Redo restores isolated material")
	history.undo();panel._sync_external();panel.save_scene()
	var shared_saved=ResourceLoader.load("res://TerrainScene.tscn","",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	check(shared_saved.get_node("First").physics_material_override==shared_saved.get_node("Second").physics_material_override,"save after Undo preserves material sharing");shared_saved.free()
	panel.heights.text="1 1 1 1";panel.heights.text_changed.emit()
	check(panel.apply_scene() and first.physics_material_override==shared_material and second.physics_material_override==shared_material,"grid-only Apply preserves shared material identity")
	history.undo();panel._sync_external()
	check(first.physics_material_override==shared_material,"grid-only Undo preserves shared material identity")
	var report={"passed":passed,"failed":failed}
	var path:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):path=arg.trim_prefix("--report=")
	if not path.is_empty():var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report))
	print("TERRAIN_PANEL_RESULT ",JSON.stringify(report));plugin.get_tree().quit(0 if failed==0 else 1)

func choose_live(panel:Control,key:String) -> void:
	for index in panel.live.item_count:
		if panel.live.get_item_metadata(index)==key: panel.live.select(index);panel._live_selected(index);return
	check(false,"live target present: "+key)
