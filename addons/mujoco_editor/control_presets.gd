@tool
extends RefCounted
## Document presets, not simulation checkpoints or automatic runtime broadcasts.
static func signature(document:RefCounted)->String:
 return document.control_signature()
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
 if not preset is Dictionary:return {"error":"Invalid preset schema"}
 return document.preset_candidate(preset)
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
