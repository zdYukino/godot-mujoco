extends RefCounted
## Optional whole-system metrics. Values unavailable from the OS stay unavailable.
var previous_cpu_total := 0.0
var previous_cpu_idle := 0.0
var gpu_device := ""
var gpu_reason := "GPU telemetry unavailable on this platform"
var samples := {}
var last_sample := 0

static func read_text(path: String) -> String:
	# procfs reports length zero, sysfs often reports 4096 for a short value.
	# Read to EOF rather than trusting the virtual file length.
	var file := FileAccess.open(path,FileAccess.READ)
	if not file: return ""
	var lines := PackedStringArray()
	while not file.eof_reached(): lines.append(file.get_line())
	return "\n".join(lines)

func _init() -> void:
	if OS.get_name() != "Linux": return
	var candidates: Array[String] = []
	for name in DirAccess.get_directories_at("/sys/class/drm"):
		if not name.begins_with("card") or name.contains("-"): continue
		var device := "/sys/class/drm/" + name + "/device"
		if FileAccess.file_exists(device + "/gpu_busy_percent"): candidates.append(device)
	if candidates.size() == 1:
		var vendor := read_text(candidates[0]+"/vendor").strip_edges()
		var adapter := RenderingServer.get_video_adapter_vendor().to_lower()
		if vendor == "0x1002" and (adapter.contains("amd") or adapter.contains("ati")):
			gpu_device = candidates[0]; gpu_reason = ""
	elif candidates.size() > 1:
		gpu_reason = "Multiple GPUs: cannot safely match renderer to telemetry device"

func sample(wanted: Dictionary) -> Dictionary:
	var now := Time.get_ticks_msec()
	if now-last_sample>2000 or not wanted.get("cpu",false): previous_cpu_total=0; previous_cpu_idle=0; samples.erase("cpu")
	last_sample=now
	if wanted.get("cpu", false) and OS.get_name() == "Linux":
		var first := read_text("/proc/stat").get_slice("\n", 0).split(" ", false)
		if first.size() > 5:
			var total := 0.0
			for i in range(1, mini(first.size(),9)): total += float(first[i])
			var idle := float(first[4]) + float(first[5])
			if previous_cpu_total > 0 and total > previous_cpu_total:
				samples.cpu = clampf(100.0*(1.0-(idle-previous_cpu_idle)/(total-previous_cpu_total)), 0, 100)
			previous_cpu_total=total; previous_cpu_idle=idle
	if wanted.get("ram", false):
		if OS.get_name() == "Linux":
			var mem := {}
			for line in read_text("/proc/meminfo").split("\n", false):
				var pair := line.split(":", true, 1)
				if pair.size() == 2: mem[pair[0]] = float(pair[1].strip_edges().get_slice(" ", 0))*1024
			if mem.has("MemAvailable") and mem.has("MemTotal"):
				samples.ram = mem.MemTotal-mem.MemAvailable; samples.ram_total = mem.MemTotal
		else:
			var mem := OS.get_memory_info()
			if mem.get("available", -1) >= 0: samples.ram = mem.physical-mem.available; samples.ram_total=mem.physical
	if not gpu_device.is_empty():
		if wanted.get("gpu", false):
			var busy := read_text(gpu_device+"/gpu_busy_percent").strip_edges()
			if busy.is_valid_float(): samples.gpu=float(busy)
			else: samples.erase("gpu")
		if wanted.get("vram", false) and FileAccess.file_exists(gpu_device+"/mem_info_vram_used"):
			var used := read_text(gpu_device+"/mem_info_vram_used").strip_edges()
			var total := read_text(gpu_device+"/mem_info_vram_total").strip_edges()
			if used.is_valid_float() and total.is_valid_float(): samples.vram=float(used); samples.vram_total=float(total)
			else: samples.erase("vram"); samples.erase("vram_total")
	return samples

func availability(metric: String) -> String:
	if metric in ["gpu", "vram"]:
		if not gpu_reason.is_empty(): return gpu_reason
		if metric=="vram" and not FileAccess.file_exists(gpu_device+"/mem_info_vram_used"): return "The matched GPU driver does not expose VRAM counters"
	if metric == "cpu" and OS.get_name() != "Linux": return "System CPU sampling is currently supported on Linux"
	return ""
