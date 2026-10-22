@tool
extends RefCounted
## Document presets, not simulation checkpoints or automatic runtime broadcasts.
static func signature(document:RefCounted)->String:
 # inspect() is a UI projection: it omits joint axis/anchor and other model fields.
 # Canonical XML from an isolated copy retains those fields. Normalize only the
 # editable PD gains, so changing gains does not make an otherwise identical
 # model incompatible. Controls and simulation state are not part of XML.
 var copy:RefCounted=ClassDB.instantiate("MjEditorDocument")
 if not copy.restore(document.snapshot()):return ""
 copy.set_paused(true)
 for entity in copy.inspect().entities:
  if entity.kind!="actuator":continue
  var p=entity.properties
  if p.transmission_type!=0:return "" # mjTRN_JOINT only, no tendon/site targets.
  var gains={}
  if p.type=="position-compatible":gains.kp=1.0
  if p.type!="general/non-PD":gains.kv=0.0
  if not gains.is_empty() and not copy.edit({"op":"set","kind":"actuator","name":entity.name,"values":gains}):return ""
 return String(copy.snapshot().xml).sha256_text()
static func capture(document:RefCounted)->Dictionary:
 var drives={}
 for entity in document.inspect().entities:
  if entity.kind!="actuator":continue
  if entity.name.is_empty() or drives.has(entity.name):return {"error":"Presets require unique named actuators"}
  var p=entity.properties
  if p.transmission_type!=0:return {"error":"Control presets support joint transmissions only; tendon/site/other targets are unsupported"}
  var values={"control":p.control}
  if p.type=="position-compatible":values.kp=p.kp
  if p.type!="general/non-PD":values.kv=p.kv
  drives[entity.name]=values
 var mapping=signature(document)
 if mapping.is_empty():return {"error":"Cannot establish a complete model compatibility signature"}
 return {"format":2,"kind":"godot-mujoco-control-preset","mapping":mapping,"drives":drives}
static func candidate(document:RefCounted,preset:Variant)->Dictionary:
 if not document.inspect().paused:return {"error":"Pause the editor model before loading a preset"}
 if not preset is Dictionary or preset.size()!=4 or preset.get("format")!=2 or preset.get("kind")!="godot-mujoco-control-preset" or not preset.get("drives") is Dictionary:
  return {"error":"Invalid control preset schema"}
 var captured=capture(document)
 if captured.has("error"):return captured
 if preset.get("mapping")!=captured.mapping:return {"error":"Model/joint/actuator mapping or design is incompatible"}
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
