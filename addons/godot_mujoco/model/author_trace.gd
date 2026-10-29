@tool
extends RefCounted
static var prefix := OS.get_environment("GMJ_AUTHOR_TRACE")
static var events: Array=[]
static var dropped := 0
static func enabled() -> bool:return not prefix.is_empty()
static func event(kind: String, values: Dictionary) -> void:
	if prefix.is_empty():return
	if events.size()>=2048:
		dropped+=1
		return
	events.append({"us":Time.get_ticks_usec(),"pid":OS.get_process_id(),"thread":OS.get_thread_caller_id(),"editor":Engine.is_editor_hint(),"event":kind,"values":values.duplicate(true)})
static func flush() -> void:
	if prefix.is_empty():return
	var batch=events.duplicate(true);events.clear()
	var path=prefix+"-"+str(OS.get_process_id())+".json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"dropped":dropped,"events":batch},"  "))
