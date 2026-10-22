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
 # Changes omitted by inspect() must still invalidate the complete signature.
 var source=FileAccess.get_file_as_string("res://fixture.xml")
 for attribute in ['axis="1 0 0"','pos=".1 0 0"']:
  file=FileAccess.open("res://changed.xml",FileAccess.WRITE);file.store_string(source.replace('name="hinge" range=', 'name="hinge" '+attribute+' range='));file.close()
  var changed=ClassDB.instantiate("MjEditorDocument");check(changed.import_file("res://changed.xml"),"import changed joint "+attribute)
  var changed_before=changed.snapshot()
  check(not Presets.candidate(changed,original).error.is_empty() and changed.snapshot()==changed_before,"axis/anchor change atomically rejects old preset "+attribute)
 # Explicitly reject both non-joint targets, even with identical drive names/types/gear.
 for target in ["t1","t2"]:
  var tendon_source=source.replace('</worldbody>','</worldbody><tendon><fixed name="t1"><joint joint="hinge" coef="1"/></fixed><fixed name="t2"><joint joint="other" coef="1"/></fixed></tendon>').replace('name="drive" joint="hinge"','name="drive" tendon="'+target+'"')
  file=FileAccess.open("res://tendon.xml",FileAccess.WRITE);file.store_string(tendon_source);file.close()
  var tendon=ClassDB.instantiate("MjEditorDocument");check(tendon.import_file("res://tendon.xml"),"import tendon target "+target)
  var tendon_before=tendon.snapshot()
  check(Presets.capture(tendon).has("error") and not Presets.candidate(tendon,original).error.is_empty() and tendon.snapshot()==tendon_before,"non-joint target rejected without mutation "+target)
 check(doc.snapshot()==stable,"signature computation does not mutate source document")
 # Mixed position/velocity drives retain their distinct valid gain domains.
 var velocity_source=source.replace('<position name="drive" joint="hinge" kp="20"','<velocity name="drive" joint="hinge" kv="4"')
 file=FileAccess.open("res://velocity.xml",FileAccess.WRITE);file.store_string(velocity_source);file.close()
 check(doc.import_file("res://velocity.xml") and drive(doc,"drive").type=="velocity-compatible","import standard joint velocity drive")
 doc.set_paused(true);doc.edit({"op":"control","name":"drive","value":.3})
 var velocity_before=doc.snapshot();var velocity_signature=Presets.signature(doc)
 check(not velocity_signature.is_empty() and doc.snapshot()==velocity_before,"velocity signature nonempty without source mutation")
 check(panel.save_control_preset("res://velocity-preset.json"),"save velocity preset via editor")
 var velocity_preset=Presets.read_file("res://velocity-preset.json").value
 check(velocity_preset.drives.drive.kv==4 and not velocity_preset.drives.drive.has("kp"),"velocity preset records kv without fictitious kp")
 doc.edit({"op":"set","kind":"actuator","name":"drive","values":{"kv":7}});doc.edit({"op":"control","name":"drive","value":-.2})
 check(Presets.signature(doc)==velocity_signature,"changed velocity kv remains compatible")
 check(panel.load_control_preset("res://velocity-preset.json") and drive(doc,"drive").kv==4 and drive(doc,"drive").control==.3,"velocity editor load restores gain and target")
 var invalid_velocity=velocity_preset.duplicate(true);invalid_velocity.drives.drive.kv=0
 velocity_before=doc.snapshot()
 check(not Presets.candidate(doc,invalid_velocity).error.is_empty() and doc.snapshot()==velocity_before,"zero velocity gain rejects without partial overwrite")
 file=FileAccess.open("res://velocity-other.xml",FileAccess.WRITE);file.store_string(velocity_source.replace('kv="4"','kv="9"'));file.close()
 var other_velocity=ClassDB.instantiate("MjEditorDocument");check(other_velocity.import_file("res://velocity-other.xml"),"import independently authored different velocity kv")
 var other_snapshot=other_velocity.snapshot()
 var velocity_candidate=Presets.candidate(other_velocity,velocity_preset)
 check(velocity_candidate.error.is_empty() and other_velocity.snapshot()==other_snapshot and other_velocity.restore(velocity_candidate.snapshot) and drive(other_velocity,"drive").kv==4 and drive(other_velocity,"drive").control==.3,"different original kv loads atomically into compatible model")
 var report={"passed":passed,"failed":failed}
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--report="):var f=FileAccess.open(arg.trim_prefix("--report="),FileAccess.WRITE);f.store_string(JSON.stringify(report))
 print("PRESET_RESULT ",JSON.stringify(report));plugin.get_tree().quit(0 if failed==0 else 1)
