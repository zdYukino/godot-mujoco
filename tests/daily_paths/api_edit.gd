extends SceneTree
const Builder=preload("res://addons/godot_mujoco/model/package_builder.gd")
var checks=[]
var report=""
func check(ok: bool, name_: String) -> void:
 checks.append({"name":name_,"passed":ok})
 if not ok:printerr("FAIL ",name_)
func property(doc: RefCounted, kind: String, name_: String, key: String) -> Variant:
 for e in doc.inspect().entities:
  if e.kind==kind and e.name==name_:return e.properties.get(key)
 return null
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var mode="edit"
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--mode="):mode=arg.trim_prefix("--mode=")
  if arg.begins_with("--report="):report=arg.trim_prefix("--report=")
 var original=FileAccess.get_file_as_string("res://original-resource.txt").strip_edges()
 var path=original if mode=="edit" else FileAccess.get_file_as_string("res://edited-resource.txt").strip_edges()
 var resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 check(resource!=null,"load existing design resource")
 if not resource:finish();return
 var opened: Dictionary=resource.open_document()
 check(opened.error.is_empty(),"validate package and open native document")
 if not opened.error.is_empty():finish();return
 var doc: RefCounted=opened.document
 if mode=="edit":
  check(is_equal_approx(float(property(doc,"joint","hinge","damping")),.2),"load GUI-authored damping")
  var file_hash=FileAccess.get_sha256("res://daily.gmj.json");var bundle_hash=FileAccess.get_sha256(original);var before=doc.snapshot()
  check(not doc.edit({"op":"set","kind":"body","name":"arm","values":{"mass":-1}}),"invalid mass rejected")
  check(doc.snapshot()==before and FileAccess.get_sha256("res://daily.gmj.json")==file_hash and FileAccess.get_sha256(original)==bundle_hash,"rejection preserves document and original file bytes")
  check(doc.edit({"op":"set","kind":"joint","name":"hinge","values":{"damping":.35}}),"API edits damping")
  check(doc.edit({"op":"add","shape":"box","name":"api_box"}),"API adds body and geometry")
  var packed: Dictionary=Builder.pack(doc,"res://daily_models","edited",resource.provenance,original.get_base_dir())
  check(packed.error.is_empty(),"publish edited immutable resource revision")
  if not packed.error.is_empty():finish();return
  var f=FileAccess.open("res://edited-resource.txt",FileAccess.WRITE);f.store_string(packed.path);f.close()
  f=FileAccess.open("res://daily.gmj.json.tmp",FileAccess.WRITE);f.store_string(JSON.stringify(doc.snapshot(),"\t",true,true));f.close()
  check(DirAccess.rename_absolute("res://daily.gmj.json.tmp","res://daily.gmj.json")==OK,"atomically save edited design document")
  var saved_hash=FileAccess.get_sha256("res://daily.gmj.json");var saved_bundle=FileAccess.get_sha256(packed.path)
  before=doc.snapshot()
  check(not doc.edit({"op":"set","kind":"body","name":"api_box","values":{"mass":-1}}) and doc.snapshot()==before,"post-save invalid edit rolls back")
  var rejected: Dictionary=Builder.pack(doc,"res://../invalid","rejected")
  check(not rejected.error.is_empty(),"invalid publication path rejected")
  check(FileAccess.get_sha256("res://daily.gmj.json")==saved_hash and FileAccess.get_sha256(packed.path)==saved_bundle and FileAccess.get_sha256(original)==bundle_hash,"failed edit/publication preserve saved and original file bytes")
 else:
  check(is_equal_approx(float(property(doc,"joint","hinge","damping")),.35),"independent process reopens edited resource value")
  check(property(doc,"body","api_box","mass")!=null and property(doc,"geom","api_box_geom","type")!=null,"independent process reopens added body and geometry")
  var saved: RefCounted=ClassDB.instantiate("MjEditorDocument")
  check(saved.restore(JSON.parse_string(FileAccess.get_file_as_string("res://daily.gmj.json"))),"independent process reopens edited JSON document")
  check(is_equal_approx(float(property(saved,"joint","hinge","damping")),.35) and property(saved,"body","api_box","mass")!=null,"JSON and resource agree on edited value and structure")
 finish()
func finish() -> void:
 var failed=0
 for c in checks:
  if not c.passed:failed+=1
 var result={"checks":checks,"passed":checks.size()-failed,"failed":failed}
 var f=FileAccess.open(report,FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print("DAILY_API_RESULT ",JSON.stringify(result));quit(0 if failed==0 else 1)
