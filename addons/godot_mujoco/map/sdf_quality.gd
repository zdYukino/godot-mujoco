@tool
extends RefCounted
## Conservative bounded admission, not a universal mesh repair algorithm.
static func validate(points: Array[Vector3], triangles: Array) -> String:
	if triangles.size()>2000: return "SDF 质量检查预算为 2000 三角形；请显式简化/分块（引擎本身没有此限制）"
	var edges := {}; var neighbors := []; var bounds: Array[AABB]=[]
	for i in triangles.size():
		neighbors.append([])
		var t: Array=triangles[i]; var box:=AABB(points[t[0]],Vector3.ZERO)
		for j in 3:
			box=box.expand(points[t[j]])
			var a: int=t[j]; var b: int=t[(j+1)%3]; var key:="%d/%d" % [mini(a,b),maxi(a,b)]
			if not edges.has(key): edges[key]=[]
			edges[key].append(i)
		bounds.append(box)
	for uses in edges.values():
		if uses.size()==2: neighbors[uses[0]].append(uses[1]); neighbors[uses[1]].append(uses[0])
	var components := {}; var checked := {}
	for start in triangles.size():
		if checked.has(start): continue
		var queue: Array=[start]; var box: AABB=bounds[start]; var volume:=0.0
		while not queue.is_empty():
			var i: int=queue.pop_back()
			if checked.has(i): continue
			checked[i]=true; components[i]=start; box=box.merge(bounds[i])
			var t: Array=triangles[i]; volume+=points[t[0]].dot(points[t[1]].cross(points[t[2]]))/6
			queue.append_array(neighbors[i])
		if minf(box.size.x,minf(box.size.y,box.size.z))<.02: return "SDF 默认候选拒绝小于 2 cm 的部件 AABB 厚度；请改用显式基础体或经专项验证的资产"
		if maxf(box.size.x,maxf(box.size.y,box.size.z))>100: return "SDF 部件跨度超出 100 m 产品预算；请分块"
		if volume>=-1e-10: return "SDF 部件绕序/有向体积无效；拒绝反向或自折叠闭合面"
	var budget:=0
	for i in triangles.size():
		for j in range(i+1,triangles.size()):
			if components[i]!=components[j] or not bounds[i].grow(1e-8).intersects(bounds[j].grow(1e-8)): continue
			var a: Array=triangles[i]; var b: Array=triangles[j]
			if a.any(func(v):return v in b): continue
			budget+=1
			if budget>200000: return "SDF 自交检查超预算；请分块"
			for edge in 3:
				if Geometry3D.segment_intersects_triangle(points[a[edge]],points[a[(edge+1)%3]],points[b[0]],points[b[1]],points[b[2]])!=null or Geometry3D.segment_intersects_triangle(points[b[edge]],points[b[(edge+1)%3]],points[a[0]],points[a[1]],points[a[2]])!=null: return "SDF 部件检测到非相邻三角面自交；不修补或静默回退"
	return ""
