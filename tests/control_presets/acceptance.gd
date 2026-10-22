@tool
extends RefCounted
const Presets=preload("res://addons/mujoco_editor/control_presets.gd")
var passed:=0
var failed:=0
func check(ok:bool,label:String):
 if ok:passed+=1;print("PASS ",label)
 else:failed+=1;printerr("FAIL ",label)
func drive(doc:RefCounted,name:String)->Dictionary:
 for e in doc.inspect().entities:
  if e.kind=="actuator" and e.name==name:return e.properties
 return {}
func run(plugin:EditorPlugin):
 var file=FileAccess.open("res://fixture.xml",FileAccess.WRITE)
 file.store_string('<mujoco><compiler angle="radian"/><worldbody><body name="a"><joint name="hinge" range="-1 1"/><geom type="box" size=".1 .1 .3"/></body><body name="b" pos="2 0 0"><joint name="other" range="-1 1"/><geom type="sphere" size=".1"/></body></worldbody><actuator><position name="drive" joint="hinge" kp="20" ctrllimited="true" ctrlrange="-.7 .7"/><position name="second" joint="other" kp="30"/></actuator></mujoco>');file.close()
 var panel=plugin.panel;var doc=plugin.state.document
 check(doc.import_file("res://fixture.xml"),"import two-drive model")
 doc.set_paused(true)
 check(doc.edit({"op":"control","name":"drive","value":.5}) and doc.edit({"op":"control","name":"second","value":-.4}),"set two targets")
 check(panel.save_control_preset("res://preset.json"),"save preset through editor entry")
 var original=Presets.read_file("res://preset.json").value
 check(original.drives.drive.control==.5 and original.drives.second.kp==30,"saved values and gains")
 var independent:RefCounted=ClassDB.instantiate("MjEditorDocument");independent.restore(doc.snapshot());var other_before=independent.snapshot()
 doc.edit({"op":"control","name":"drive","value":0});doc.edit({"op":"set","kind":"actuator","name":"drive","values":{"kp":50,"kv":2}})
 var before=doc.snapshot()
 check(panel.load_control_preset("res://preset.json"),"load compatible preset atomically")
 check(drive(doc,"drive").control==.5 and drive(doc,"drive").kp==20 and drive(doc,"drive").kv==0,"restore target and PD")
 check(independent.snapshot()==other_before,"other document instance untouched")
 var history=plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(plugin.state))
 history.undo();check(doc.snapshot()==before,"single undo restores all previous values")
 history.redo();check(drive(doc,"drive").control==.5 and drive(doc,"drive").kp==20,"redo restores preset")
 var stable=doc.snapshot()
 var invalid=original.duplicate(true);invalid.drives.drive.control=.2;invalid.drives.second.kp=-3
 check(not Presets.candidate(doc,invalid).error.is_empty() and doc.snapshot()==stable,"late invalid gain leaves original entirely unchanged")
 invalid=original.duplicate(true);invalid.drives.drive.control=NAN
 check(not Presets.candidate(doc,invalid).error.is_empty(),"nonfinite rejected")
 invalid=original.duplicate(true);invalid.drives.drive.control=2
 check(not Presets.candidate(doc,invalid).error.is_empty() and doc.snapshot()==stable,"out of range target rejected atomically")
 invalid=original.duplicate(true);invalid.drives.erase("second")
 check(not Presets.candidate(doc,invalid).error.is_empty(),"missing actuator rejected")
 invalid=original.duplicate(true);invalid.mapping="other-model"
 check(not Presets.candidate(doc,invalid).error.is_empty(),"incompatible mapping rejected")
 independent.edit({"op":"set","kind":"joint","name":"hinge","values":{"range":[-2,2]}})
 check(not Presets.candidate(independent,original).error.is_empty(),"different joint limits reject actual model")
 file=FileAccess.open("res://invalid.json",FileAccess.WRITE);file.store_string('{invalid');file.close()
 check(not panel.load_control_preset("res://invalid.json") and doc.snapshot()==stable,"invalid file no partial overwrite")
 doc.set_paused(false);check(not panel.load_control_preset("res://preset.json"),"running editor rejects preset");doc.set_paused(true)
 panel.pending=true;check(not panel.load_control_preset("res://preset.json"),"pending fields protected");panel.pending=false
 check(panel.load_control_preset("res://preset.json") and panel.load_control_preset("res://preset.json"),"repeat load deterministic")
 var reopened:RefCounted=ClassDB.instantiate("MjEditorDocument");reopened.import_file("res://fixture.xml")
 var result=Presets.candidate(reopened,Presets.read_file("res://preset.json").value)
 check(result.error.is_empty() and reopened.restore(result.snapshot) and drive(reopened,"drive").control==.5,"file reload into compatible fresh document")
 var unnamed=ClassDB.instantiate("MjEditorDocument")
 file=FileAccess.open("res://unnamed.xml",FileAccess.WRITE);file.store_string(FileAccess.get_file_as_string("res://fixture.xml").replace('name="drive" ' ,''));file.close();unnamed.import_file("res://unnamed.xml")
 check(Presets.save_file(unnamed,"res://unnamed-preset.json").is_empty() and Presets.read_file("res://unnamed-preset.json").value.drives.size()==2,"importer generated actuator names preserve every preset field")
 var report={"passed":passed,"failed":failed}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="):var f=FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE);f.store_string(JSON.stringify(report))
 print("PRESET_RESULT ",JSON.stringify(report));plugin.get_tree().quit(0 if failed==0 else 1)
