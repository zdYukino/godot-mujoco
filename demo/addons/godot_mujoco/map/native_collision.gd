@tool
extends RefCounted
## Map-only MJCF adapter. Inline assets keep packages independent of source paths.
const VERSION := "3.16.0"
const MODES := ["plane", "ellipsoid", "mesh", "sdf"]
const PRIMITIVES := ["box","sphere","capsule","cylinder"]

static func uses_native(spec: Dictionary) -> bool:
	return spec.get("kind") in MODES or (spec.get("kind") in PRIMITIVES and spec.get("native_contact",false))
const Collision = preload("collision.gd")

static func record(requested: String, actual: String, reason: String = "", adapter: String = "") -> Dictionary:
	return {"schema":1,"engine_version":VERSION,"requested_mode":requested,"actual_mode":actual,"status":"configured_unverified" if reason.is_empty() else "disabled","reason":reason,"adapter":adapter if not adapter.is_empty() else ("map_mjcf" if requested in MODES else "native_shape")}

static func vector(v: Vector3) -> String:
	return "%.12f %.12f %.12f" % [v.x,-v.z,v.y]

static func options(settings: Dictionary) -> Dictionary:
	var attributes := " timestep='0.002'"
	var flags := ""
	var normalized := settings.duplicate(true)
	for key in settings:
		var value: Variant = settings[key]
		if key in ["solver","cone","jacobian"]:
			var allowed: Array = {"solver":["Newton","CG","PGS"],"cone":["pyramidal","elliptic"],"jacobian":["auto","dense","sparse"]}[key]
			if value not in allowed: return {"error":"无效世界设置: " + key}
			attributes += " %s='%s'" % [key,value]
		elif key in ["nativeccd","multiccd","midphase","filterparent","warmstart","island","override"]:
			if not value is bool: return {"error":"世界 flag 必须为 bool: " + key}
			flags += " %s='%s'" % [key,"enable" if value else "disable"]
		elif key in ["o_friction","o_solref","o_solimp"]:
			if not value is Array or value.size()!={"o_friction":5,"o_solref":2,"o_solimp":5}[key]: return {"error":"世界接触覆盖维数错误: "+key}
			var words := PackedStringArray()
			for v in value:
				if typeof(v) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(v): return {"error":"世界接触覆盖必须有限"}
				if key=="o_friction" and v<0: return {"error":"覆盖摩擦必须非负"}
				words.append(String.num_scientific(v))
			if key!="o_friction":
				var checked := contact_attributes({"contact":{key.trim_prefix("o_"):value}})
				if not checked.error.is_empty(): return checked
			attributes += " %s='%s'" % [key," ".join(words)]
		elif key=="o_margin":
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value) or value<0: return {"error":"覆盖 margin 必须非负有限"}
			attributes += " o_margin='%s'" % String.num_scientific(value)
		elif key in ["iterations","ccd_iterations","sdf_iterations","sdf_initpoints","noslip_iterations","ls_iterations"]:
			var minimum := 0
			if not Collision.integer_in_range(value,minimum,1000): return {"error":"世界迭代参数需整值 %d..1000: " % minimum + key}
			normalized[key] = int(value)
			attributes += " %s='%d'" % [key,int(value)]
		elif key in ["tolerance","ccd_tolerance","noslip_tolerance","ls_tolerance","impratio"]:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value) or value < 0 or (key=="impratio" and value==0) or value > 100: return {"error":"无效世界数值: " + key}
			attributes += " %s='%s'" % [key,String.num_scientific(value)]
		else: return {"error":"未接入世界设置: " + str(key)}
	return {"error":"","xml":"<option%s><flag%s/></option>" % [attributes,flags],"settings":normalized}

static func build(mesh: MeshInstance3D, root: Node3D, spec: Dictionary, settings: Dictionary = {}) -> Dictionary:
	var kind: String = spec.get("kind","sdf")
	if kind not in MODES and kind not in PRIMITIVES: return {"error":"未接入 MJCF 地图表示"}
	var pose := Collision.pose_of(mesh,root)
	if not pose.is_finite() or pose.basis.determinant() <= 0: return {"error":"拒绝镜像/非有限变换"}
	var scale_value := pose.basis.get_scale()
	var rotation := pose.basis.orthonormalized()
	if not pose.basis.is_equal_approx(rotation.scaled_local(scale_value)): return {"error":"拒绝剪切"}
	var opt := options(settings)
	if not opt.error.is_empty(): return opt
	var parameters := contact_attributes(spec)
	if not parameters.error.is_empty(): return parameters
	var material: String = parameters.xml
	var bounds := mesh.mesh.get_aabb()
	var asset := ""
	var geom := ""
	if kind in ["mesh","sdf"]:
		var faces := mesh.mesh.get_faces()
		if faces.size()<12 or faces.size()>60000: return {"error":"网格需 4..20000 三角形；超限请显式简化或分块"}
		var vertices := PackedStringArray(); var indices := PackedStringArray(); var edges := {}; var lookup := {}; var points: Array[Vector3] = []; var triangles: Array=[]
		for i in range(0,faces.size(),3):
			var triangle: Array[int] = []
			for j in 3:
				var point: Vector3 = faces[i+j]*scale_value
				if not point.is_finite(): return {"error":"非有限网格顶点"}
				if not lookup.has(point): lookup[point]=points.size(); points.append(point); vertices.append(vector(point))
				triangle.append(lookup[point])
			if (points[triangle[1]]-points[triangle[0]]).cross(points[triangle[2]]-points[triangle[0]]).length_squared()<1e-16: return {"error":"退化三角形"}
			triangles.append(triangle)
			# Godot uses clockwise front faces; MuJoCo uses counterclockwise.
			indices.append("%d %d %d" % [triangle[0],triangle[2],triangle[1]])
			for j in 3:
				var a := triangle[j]; var b := triangle[(j+1)%3]; var key := "%d/%d" % [mini(a,b),maxi(a,b)]
				var edge: Vector2i = edges.get(key,Vector2i.ZERO); edges[key]=edge+Vector2i(1,1 if a<b else -1)
		if kind=="sdf":
			for edge in edges.values():
				if edge.x < 2 or edge.x % 2 != 0 or edge.y != 0: return {"error":"SDF 要求闭合且一致绕序的三角面集合；可显式选择凸包或基础体"}
			var quality: String=preload("sdf_quality.gd").validate(points,triangles)
			if not quality.is_empty(): return {"error":quality}
		var depth: Variant=spec.get("octree_maxdepth",0)
		if kind=="sdf" and spec.has("octree_maxdepth") and not Collision.integer_in_range(depth,3,8): return {"error":"SDF octree_maxdepth 需整值 3..8；拒绝无界分辨率"}
		var octree: String="" # mjsMesh field: not an XML attribute in 3.16.0.
		asset = "<asset><mesh name='collision_mesh' vertex='%s' face='%s'%s/></asset>" % [" ".join(vertices)," ".join(indices),octree]
		geom = "<geom name='collision' type='%s' mesh='collision_mesh'%s/>" % [kind,material]
	else:
		var half := bounds.size*scale_value/2
		if kind!="plane" and (half.x<=0 or half.y<=0 or half.z<=0): return {"error":"椭球需要三个正半轴"}
		var size_text := "%.12f %.12f %.12f" % [half.x,half.z,half.y] if kind=="ellipsoid" else "0 0 .1"
		if kind=="box": size_text="%.12f %.12f %.12f" % [half.x,half.z,half.y]
		if kind=="sphere":
			if not is_equal_approx(half.x,half.y) or not is_equal_approx(half.x,half.z): return {"error":"球需等轴"}
			size_text="%.12f" % half.x
		if kind in ["capsule","cylinder"]:
			if not is_equal_approx(half.x,half.z) or (kind=="capsule" and half.y<half.x): return {"error":"圆柱/胶囊尺寸无效"}
			size_text="%.12f %.12f" % [half.x,half.y-half.x if kind=="capsule" else half.y]
		geom = "<geom name='collision' type='%s' pos='%s' size='%s'%s/>" % [kind,vector(bounds.get_center()*scale_value),size_text,material]
	var xml := "<mujoco><compiler angle='radian'/>%s%s<worldbody><body name='map_collision'>%s</body></worldbody></mujoco>" % [opt.xml,asset,geom]
	var doc := MjEditorDocument.new()
	if doc.inspect().version!=VERSION: return {"error":"需要精确 MuJoCo " + VERSION}
	var snapshot := {"format":1,"xml":xml,"state":{},"source":""}
	if kind=="sdf" and spec.has("octree_maxdepth"): snapshot["mesh_options"]={"collision_mesh":{"octree_maxdepth":int(spec.octree_maxdepth)}}; snapshot.format=2
	if not doc.restore(snapshot): return {"error":doc.get_error()}
	if kind=="sdf" and (doc.inspect().octree_cells>500000 or doc.inspect().model_buffer_bytes>67108864): return {"error":"SDF 编译结果超过产品预算：500000 八叉树单元/64 MiB 模型 buffer；请分块或显式选择替代"}
	return {"error":"","snapshot":snapshot,"pose":Transform3D(rotation,pose.origin),"geometry":doc.geometry(),"document":doc,"contract":record(kind,kind,"","map_mjcf"),"source_hash":JSON.stringify(snapshot,"",true,true).sha256_text() if snapshot.has("mesh_options") else xml.sha256_text()}

static func contact_attributes(spec: Dictionary) -> Dictionary:
	var material := ""
	for field in ["layer","mask"]:
		var value: Variant = spec.get(field,1)
		if not Collision.integer_in_range(value,0,2147483647): return {"error":"MJCF 过滤位需 0..2147483647；拒绝截断最高位"}
	material += " contype='%d' conaffinity='%d'" % [spec.get("layer",1),spec.get("mask",1)]
	var friction: Variant = spec.get("friction",1.0)
	if typeof(friction) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(friction) or friction < 0: return {"error":"摩擦必须非负有限"}
	if not spec.get("contact",{}) is Dictionary: return {"error":"接触属性必须为 Dictionary"}
	var contact: Dictionary = spec.get("contact",{}).duplicate(true)
	for key in ["condim","priority"]:
		if not contact.has(key): continue
		var minimum := -2147483648 if key=="priority" else 0
		if not Collision.integer_in_range(contact[key],minimum,2147483647): return {"error":"接触整数需有限整值 %d..2147483647: " % minimum+key}
		contact[key]=int(contact[key])
	for key in contact:
		if key not in ["friction","condim","solref","solimp","priority","solmix","margin","gap"]: return {"error":"未接入接触属性: " + str(key)}
	material += " friction='%.12f .005 .0001'" % friction if not contact.has("friction") else ""
	for key in contact:
		var values: Array = contact[key] if contact[key] is Array else [contact[key]]
		var count: int = {"friction":3,"solref":2,"solimp":5}.get(key,1)
		if values.size()!=count: return {"error":"接触参数维数错误: " + key}
		var text_values := PackedStringArray()
		for value in values:
			if typeof(value) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value): return {"error":"接触参数必须有限: " + key}
			text_values.append(String.num_scientific(value))
		if key=="condim" and values[0] not in [1,3,4,6]: return {"error":"condim 仅 1/3/4/6"}
		if key in ["priority","condim"] and float(values[0])!=int(values[0]): return {"error":"接触整数无效"}
		if key=="solref" and not ((values[0]>0 and values[1]>0) or (values[0]<=0 and values[1]<=0)): return {"error":"solref 需同号的标准或直接格式"}
		if key=="solimp" and (values[0]<.0001 or values[0]>.9999 or values[1]<.0001 or values[1]>.9999 or values[2]<=0 or values[3]<=0 or values[3]>=1 or values[4]<1): return {"error":"solimp 超出有效范围；拒绝静默钳位"}
		if key in ["friction","solmix","margin","gap"]:
			for value in values:
				if value<0: return {"error":"接触参数必须非负: " + key}
		material += " %s='%s'" % [key,str(int(values[0])) if key in ["priority","condim"] else " ".join(text_values)]
	return {"error":"","xml":material,"contact":contact}

static func build_height(design: Dictionary, settings: Dictionary) -> Dictionary:
	var error: String = design.grid.validate()
	if not error.is_empty(): return {"error":error}
	var pose: Transform3D=design.pose
	if not pose.is_finite() or not pose.basis.is_equal_approx(pose.basis.orthonormalized()) or pose.basis.determinant()<0: return {"error":"原生高度场需刚性变换"}
	var spec := {"kind":"hfield","friction":design.material.friction,"layer":design.get("layer",1),"mask":design.get("mask",1),"contact":design.get("native_contact",{})}
	var contact := contact_attributes(spec); var opt := options(settings)
	if not contact.error.is_empty(): return contact
	if not opt.error.is_empty(): return opt
	var values := PackedStringArray(); var low: float=design.grid.heights[0]; var high := low
	for h in design.grid.heights: values.append("%.12f" % h); low=minf(low,h); high=maxf(high,h)
	var asset := "<asset><hfield name='collision_mesh' nrow='%d' ncol='%d' size='%.12f %.12f %.12f 1' elevation='%s'/></asset>" % [design.grid.depth,design.grid.width,(design.grid.width-1)*.5,(design.grid.depth-1)*.5,maxf(high-low,.000001)," ".join(values)]
	var xml := "<mujoco><compiler angle='radian'/>%s%s<worldbody><body name='map_collision'><geom name='collision' type='hfield' hfield='collision_mesh' pos='0 0 %.12f'%s/></body></worldbody></mujoco>" % [opt.xml,asset,low,contact.xml]
	var doc := MjEditorDocument.new(); var snapshot := {"format":1,"xml":xml,"state":{},"source":""}
	if not doc.restore(snapshot): return {"error":doc.get_error()}
	return {"error":"","snapshot":snapshot,"pose":pose,"document":doc,"contract":record("hfield","hfield","","map_mjcf"),"source_hash":xml.sha256_text()}

static func combine(entries: Array[Dictionary], relations: Dictionary, settings: Dictionary) -> Dictionary:
	var names := {}; var modes := {}; var assets := ""; var bodies := ""; var contacts := ""; var mesh_options := {}
	for i in entries.size():
		var entry: Dictionary=entries[i]; var text: String=entry.snapshot.xml
		var stem := "_"+str(i); names[entry.source_node]=stem; modes[entry.source_node]=entry.contract.actual_mode
		for mesh_name in entry.snapshot.get("mesh_options",{}): mesh_options[str(mesh_name)+stem]=entry.snapshot.mesh_options[mesh_name].duplicate(true)
		text=text.replace("collision_mesh","collision_mesh"+stem).replace("name='collision'","name='collision"+stem+"'")
		assets += text.get_slice("<asset>",1).get_slice("</asset>",0) if text.contains("<asset>") else ""
		var pose: Transform3D=entry.pose; var q:=pose.basis.get_rotation_quaternion()
		var body: String=text.get_slice("<worldbody>",1).get_slice("</worldbody>",0)
		body=body.replace("<body name='map_collision'>","<body name='map_collision%s' pos='%s' quat='%.12f %.12f %.12f %.12f'>" % [stem,vector(pose.origin),q.w,q.x,-q.z,q.y]); bodies+=body
	for kind in relations:
		if kind not in ["pairs","excludes"] or not relations[kind] is Array: return {"error":"关系仅接受 pairs/excludes 数组"}
		for item in relations[kind]:
			if not item is Dictionary or not item.get("first") is String or not item.get("second") is String or not names.has(item.get("first")) or not names.has(item.get("second")) or item.first==item.second: return {"error":"关系需两个不同的、显式原生接触地图节点路径"}
			if kind=="pairs" and modes[item.first] in ["plane","hfield"] and modes[item.second] in ["plane","hfield"]:
				return {"error":"MuJoCo 3.16 不支持 %s–%s pair：无碰撞分发函数；请保留原关系或选择受支持表示" % [modes[item.first],modes[item.second]]}
			var tag: String="pair" if kind=="pairs" else "exclude"
			var attr: String="geom" if kind=="pairs" else "body"
			var prefix: String="collision" if kind=="pairs" else "map_collision"
			var attributes: String=" %s1='%s%s' %s2='%s%s'" % [attr,prefix,names[item.first],attr,prefix,names[item.second]]
			for key in item:
				if key in ["first","second"]: continue
				if kind!="pairs" or key not in ["friction","condim","solref","solimp","margin","gap"]: return {"error":"关系属性未支持: "+str(key)}
				var values: Array=item[key] if item[key] is Array else [item[key]]
				var count: int={"friction":5,"solref":2,"solimp":5}.get(key,1)
				if values.size()!=count: return {"error":"pair 参数维数错误"}
				var words:=PackedStringArray()
				for value in values:
					if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(value): return {"error":"pair 参数必须有限数值"}
					if key in ["friction","margin","gap"] and value<0: return {"error":"pair 参数必须非负"}
					words.append(String.num_scientific(value))
				if key=="condim":
					if not Collision.integer_in_range(item[key],1,6) or int(item[key]) not in [1,3,4,6]: return {"error":"pair condim 仅整值 1/3/4/6"}
					words=PackedStringArray([str(int(values[0]))])
				if key in ["solref","solimp"]:
					var checked:=contact_attributes({"contact":{key:values}})
					if not checked.error.is_empty(): return checked
				attributes+=" %s='%s'" % [key," ".join(words)]
			contacts+="<%s%s/>" % [tag,attributes]
	var opt:=options(settings)
	if not opt.error.is_empty(): return opt
	var xml:="<mujoco><compiler angle='radian'/>%s<asset>%s</asset><worldbody>%s</worldbody><contact>%s</contact></mujoco>" % [opt.xml,assets,bodies,contacts]
	var snapshot:={"format":1,"xml":xml,"state":{},"source":""}; var doc:=MjEditorDocument.new()
	if not mesh_options.is_empty(): snapshot["mesh_options"]=mesh_options; snapshot.format=2
	if not doc.restore(snapshot): return {"error":doc.get_error()}
	return {"error":"","entry":{"snapshot":snapshot,"pose":Transform3D.IDENTITY,"contract":{"schema":1,"actual_mode":"native_collection","status":"configured_unverified"},"source_hash":JSON.stringify(snapshot,"",true,true).sha256_text() if snapshot.has("mesh_options") else xml.sha256_text(),"source_node":"collection"}}
