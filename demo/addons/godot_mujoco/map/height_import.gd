@tool
extends RefCounted
## Explicit single-valued height contract. Native grid is one metre; no silent resampling.
const Grid = preload("../model/heightfield_data.gd")
static func read(path: String, contract: Dictionary) -> Dictionary:
	for field in ["width","depth","spacing_x","spacing_z","unit","row_order","encoding"]:
		if not contract.has(field): return {"error":"高度契约缺少 " + field}
	if contract.row_order != "increasing_z" or contract.spacing_x != 1.0 or contract.spacing_z != 1.0:
		return {"error":"当前原生 HeightField 契约：按行 +Z、X 优先、1 m 间距；其他间距须外部显式重采样"}
	if not contract.unit in ["m","cm","mm"]: return {"error":"高度单位必须显式选择"}
	if not contract.width is int or not contract.depth is int or contract.width < 2 or contract.depth < 2 or contract.width > 256 or contract.depth > 256:
		return {"error":"宽深必须为 2..256 整数"}
	if not FileAccess.file_exists(path): return {"error":"缺少高度输入: " + path}
	var samples := PackedFloat32Array()
	match contract.encoding:
		"float32_le":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() != contract.width * contract.depth * 4: return {"error":"RAW 字节数不等于 width*depth*4"}
			for offset in range(0,bytes.size(),4): samples.append(bytes.decode_float(offset))
		"json_metres":
			var values: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not values is Array: return {"error":"高度 JSON 必须是行优先数值数组"}
			for value in values:
				if typeof(value) not in [TYPE_FLOAT,TYPE_INT]: return {"error":"高度样本必须是数值"}
				samples.append(value)
		"png_u8":
			if not contract.has("height_scale") or not contract.has("height_offset"): return {"error":"PNG 必须显式给出 height_scale/height_offset（源单位）"}
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() < 26 or bytes.decode_u32(0) != 0x474e5089 or bytes[24] != 8 or bytes[25] != 0:
				return {"error":"只接受原始 8-bit 灰度 PNG；16-bit/RGB 不允许隐式降精度"}
			var image := Image.load_from_file(path)
			if not image or image.get_width() != contract.width or image.get_height() != contract.depth: return {"error":"PNG 行列与契约不匹配"}
			for z in contract.depth:
				for x in contract.width: samples.append(image.get_pixel(x,z).r*contract.height_scale+contract.height_offset)
		_: return {"error":"不支持的高度编码；支持 float32_le/json_metres/png_u8"}
	var factor: float = {"m":1.0,"cm":.01,"mm":.001}[contract.unit]
	for i in samples.size(): samples[i] *= factor
	var grid := Grid.new(); grid.width = contract.width; grid.depth = contract.depth; grid.heights = samples
	var error := grid.validate()
	if not error.is_empty(): return {"error":error}
	return {"error":"", "grid":grid, "source_hash":FileAccess.get_sha256(path),"contract":contract.duplicate(true)}
