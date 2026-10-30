extends Control
var title := ""
var series: Array = []
var captions: Array = []
var history: Array = []
var bars := false
const COLORS := [Color("60c8f0"),Color("edbf66"),Color("ea7c8c"),Color("96cc7a"),Color("ba9ce2"),Color("f0a06c")]
func _init() -> void:
	custom_minimum_size = Vector2(340, 170)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
func set_series(values: Array) -> void:
	series=values; queue_redraw()
func append_sample(values: Array) -> void:
	history.append(values.duplicate())
	if history.size()>201: history.pop_front()
	series=[]
	for i in values.size():
		var line := PackedFloat64Array()
		for row in history: line.append(float(row[i]))
		series.append(line)
	queue_redraw()

func _curve_color(index: int) -> Color:
	# Solver curves are appended island-by-island. Repeat the active category
	# palette rather than changing a category's color in the next island.
	var period := maxi(1,captions.size()) if not captions.is_empty() else COLORS.size()
	return COLORS[(index%period)%COLORS.size()]

func _legend_lines(font: Font, text: String, font_size: int, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for character in text:
		var candidate := line+character
		if not line.is_empty() and font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>width:
			lines.append(line);line=character
		else: line=candidate
	if not line.is_empty(): lines.append(line)
	return lines

func _legend_layout(font: Font, font_size: int, width: float) -> Dictionary:
	var entries: Array=[]
	var line_height := font.get_height(font_size)+2
	var cursor := Vector2.ZERO
	var row_height := 0.0
	for index in captions.size():
		var lines := _legend_lines(font,str(captions[index]),font_size,maxf(1,width-14))
		var text_width := 0.0
		for line in lines: text_width=maxf(text_width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x)
		var item_width := minf(width,text_width+14)
		if cursor.x>0 and cursor.x+item_width>width:
			cursor=Vector2(0,cursor.y+row_height);row_height=0
		entries.append({"lines":lines,"position":cursor,"color":_curve_color(0 if bars and series.size()==1 else index)})
		row_height=maxf(row_height,line_height*lines.size())
		cursor.x+=item_width+6
	return {"entries":entries,"height":cursor.y+row_height,"line_height":line_height}

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(.1,0,0,.5) if title in ["Counts","Dimensions"] else Color(0,0,.2,.5))
	var font := ThemeDB.fallback_font
	draw_string(font,Vector2(10,20),title,HORIZONTAL_ALIGNMENT_LEFT,size.x-10,11 if size.x<240 else 14,Color.WHITE)
	var legend_font := 9 if size.x<132 else 10 if size.x<240 else 11
	var legend := _legend_layout(font,legend_font,maxf(1,size.x-16))
	while legend_font>7 and float(legend.height)>size.y-56:
		legend_font-=1;legend=_legend_layout(font,legend_font,maxf(1,size.x-16))
	var legend_top := size.y-float(legend.height)-4
	var margin := 28.0 if size.x<240 else 40.0
	var rect := Rect2(margin,30,maxf(1,size.x-margin-10),maxf(1,legend_top-38))
	var low := 0.0; var high := 0.0
	for line in series:
		for value in line:
			if is_finite(value): low=minf(low,value); high=maxf(high,value)
	if bars: high=maxf(1,maxf(absf(low),absf(high)));low=-high
	if high<=low: high=low+1
	for i in 5:
		var y := rect.position.y+rect.size.y*i/4
		draw_line(Vector2(rect.position.x,y),Vector2(rect.end.x,y),Color(.2,.24,.3),1)
	draw_string(font,Vector2(2,rect.position.y+8),"%.2f" % high,HORIZONTAL_ALIGNMENT_LEFT,margin-2,9,Color.GRAY)
	draw_string(font,Vector2(2,rect.end.y),"%.2f" % low,HORIZONTAL_ALIGNMENT_LEFT,margin-2,9,Color.GRAY)
	for i in series.size():
		var line = series[i]; var points := PackedVector2Array()
		for j in line.size():
			if is_finite(line[j]): points.append(Vector2(rect.position.x+rect.size.x*j/maxi(1,line.size()-1),rect.end.y-rect.size.y*(line[j]-low)/(high-low)))
		if bars:
			var zero := rect.end.y-rect.size.y*clampf(-low/(high-low),0,1)
			for point in points: draw_line(Vector2(point.x,zero),point,_curve_color(i),2,true)
		elif points.size()>1: draw_polyline(points,_curve_color(i),1.5,true)
		elif points.size()==1: draw_circle(points[0],2,_curve_color(i))
	for entry in legend.entries:
		var position: Vector2=Vector2(8,legend_top)+entry.position
		var color: Color=entry.color
		draw_line(position+Vector2(0,float(legend.line_height)*.5),position+Vector2(8,float(legend.line_height)*.5),color,2)
		for index in entry.lines.size():
			var baseline := position+Vector2(14,index*float(legend.line_height)+font.get_ascent(legend_font))
			draw_string(font,baseline,entry.lines[index],HORIZONTAL_ALIGNMENT_LEFT,maxf(1,size.x-baseline.x-8),legend_font,color)
