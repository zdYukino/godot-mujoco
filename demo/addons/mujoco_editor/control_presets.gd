@tool
extends RefCounted
## Document presets, not simulation checkpoints or automatic runtime broadcasts.
static func signature(document:RefCounted)->String:
 var entities:Array=document.inspect().entities.duplicate(true)
 for entity in entities:
  for key in ["qpos","control","kp","kv"]:entity.properties.erase(key)
 return JSON.stringify(entities).sha256_text()
static func capture(document:RefCounted)->Dictionary:
 var drives={}
 for entity in document.inspect().entities:
  if entity.kind!="actuator":continue
  if entity.name.is_empty() or drives.has(entity.name):return {"error":"Presets require unique named actuators"}
  var p=entity.properties;var values={"control":p.control}
  if p.type=="position-compatible":values.kp=p.kp
  if p.type!="general/non-PD":values.kv=p.kv
  drives[entity.name]=values
 return {"format":1,"kind":"godot-mujoco-control-preset","mapping":signature(document),"drives":drives}
static func candidate(document:RefCounted,preset:Variant)->Dictionary:
 if not document.inspect().paused:return {"error":"Pause the editor model before loading a preset"}
 if not preset is Dictionary or preset.size()!=4 or preset.get("format")!=1 or preset.get("kind")!="godot-mujoco-control-preset" or not preset.get("drives") is Dictionary:
  return {"error":"Invalid control preset schema"}
 if preset.get("mapping")!=signature(document):return {"error":"Model/joint/actuator mapping or design is incompatible"}
 var captured=capture(document)
 if captured.has("error"):return captured
 var expected=captured.drives
 if preset.drives.size()!=expected.size():return {"error":"Actuator set mismatch"}
 for name in expected:
  if not preset.drives.has(name) or not preset.drives[name] is Dictionary:return {"error":"Missing actuator: "+name}
  var values:Dictionary=preset.drives[name]
  if values.size()!=expected[name].size():return {"error":"Unsupported or missing gain fields: "+name}
  for key in expected[name]:
   if not values.has(key) or typeof(values[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(values[key]):return {"error":"Invalid numeric field: "+name+"/"+key}
 var copy:RefCounted=ClassDB.instantiate("MjEditorDocument")
 if not copy.restore(document.snapshot()):return {"error":copy.get_error()}
 copy.set_paused(true)
 for name in expected:
  var values:Dictionary=preset.drives[name].duplicate();var control=values.control;values.erase("control")
  if not values.is_empty() and not copy.edit({"op":"set","kind":"actuator","name":name,"values":values}):return {"error":copy.get_error()}
  if not copy.edit({"op":"control","name":name,"value":control}):return {"error":copy.get_error()}
 return {"error":"","snapshot":copy.snapshot()}
static func save_file(document:RefCounted,path:String)->String:
 if path.is_empty():return "Choose a preset file"
 var captured=capture(document)
 if captured.has("error"):return captured.error
 var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if not file:return "Cannot write preset temporary file"
 file.store_string(JSON.stringify(captured,"\t"));file.flush()
 var error=file.get_error();file.close()
 if error!=OK:return "Failed to write preset"
 if DirAccess.rename_absolute(path+".tmp",path)!=OK:return "Cannot replace preset file"
 return ""
static func read_file(path:String)->Dictionary:
 var file=FileAccess.open(path,FileAccess.READ)
 if not file:return {"error":"Cannot open preset"}
 if file.get_length()>1048576:return {"error":"Preset exceeds 1 MiB"}
 var json=JSON.new()
 if json.parse(file.get_as_text())!=OK:return {"error":"Invalid preset JSON"}
 return {"error":"","value":json.data}
