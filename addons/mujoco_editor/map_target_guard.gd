@tool
extends RefCounted

# Store a digest of detached values, never references to mutable Resources.
# Include authored descendants and storage properties (metadata, geometry,
# material, collision, terrain and runtime exports), excluding generated editor
# visuals without owners. IDs also detect same-valued resource/node replacement.
static func fingerprint(root: Node) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(node_state(root,{})))
	return context.finish()

static func node_state(node: Node, seen: Dictionary) -> Dictionary:
	var children := []
	for child in node.get_children():
		if node is MjStaticHeightField and child==node._visual: continue
		if child.owner: children.append(node_state(child,seen))
	return {"id":node.get_instance_id(),"owner":node.owner.get_instance_id() if node.owner else 0,"properties":properties(node,seen),"children":children}

static func properties(object: Object, seen: Dictionary) -> Dictionary:
	var result := {}
	for property in object.get_property_list():
		if property.name in ["resource_path","resource_scene_unique_id"]: continue
		if property.usage & PROPERTY_USAGE_STORAGE:
			result[property.name]=value_state(object.get(property.name),seen)
	return result

static func value_state(value: Variant, seen: Dictionary) -> Variant:
	if value is Resource:
		var id: int=value.get_instance_id()
		if seen.has(id): return {"reference":id}
		seen[id]=true
		return {"resource":id,"properties":properties(value,seen)}
	if value is Object: return {"object":value.get_instance_id() if is_instance_valid(value) else 0}
	if value is Dictionary:
		var result := {}
		for key in value: result[key]=value_state(value[key],seen)
		return result
	if value is Array:
		var result := []
		for item in value: result.append(value_state(item,seen))
		return result
	return value
