class_name PerfTelemetry
extends Node
## Opt-in local profiling. The autoload removes itself when no request exists.
signal completed(status: String)
const REQUEST := "user://benchmark_request.json"
const PHASES := ["dense_driving", "free_camera", "night", "rain", "terminus"]
const MAX_SAMPLES := 20000
var auto_start := true
var enabled := false
var config: Dictionary = {}
var metadata: Dictionary = {}
var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var context: Dictionary = {}
var phase := "loading"
var warmup_left := 0
var warmup_excluded := 0
var started_us := 0
var last_us := 0
var status := "not_started"
var export_error := ""

static func number(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

static func validate_request(c: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var allowed := ["schema_version","run_id","request_id","network","phase_seconds","warmup_frames","seed","phases","budgets","power_mode","gpu_timing","max_samples","view_distance"]
	for key in c:
		if not key in allowed: errors.append("unknown field: " + str(key))
	if c.get("schema_version") != 1: errors.append("schema_version must be 1")
	for key in ["run_id","request_id"]:
		var v := str(c.get(key,""))
		if not v.is_valid_identifier() or v.length()>80: errors.append("invalid " + key)
	var network := str(c.get("network",""))
	if not (network.begins_with("res://data/free/") or network.begins_with("res://data/networks/")) or not network.ends_with(".json") or ".." in network: errors.append("network must be embedded data")
	for rule in [["phase_seconds",8,.1,120],["warmup_frames",10,0,600],["max_samples",MAX_SAMPLES,1,MAX_SAMPLES],["view_distance",400,100,1200]]:
		var v: Variant = c.get(rule[0],rule[1])
		if not number(v) or float(v)<float(rule[2]) or float(v)>float(rule[3]): errors.append("invalid " + str(rule[0]))
	for key in ["warmup_frames","max_samples","seed"]:
		var v: Variant = c.get(key,7 if key=="seed" else (10 if key=="warmup_frames" else MAX_SAMPLES))
		if not number(v) or float(v)!=floorf(float(v)): errors.append("integer required: " + key)
	if not c.get("gpu_timing",false) is bool: errors.append("gpu_timing must be boolean")
	var phases: Variant = c.get("phases",PHASES)
	if not phases is Array or phases.is_empty(): errors.append("phases must be nonempty")
	else:
		var seen := {}
		for p in phases:
			if not p in PHASES or seen.has(p): errors.append("unknown/duplicate phase")
			seen[p] = true
	var budgets: Variant = c.get("budgets",{})
	if not budgets is Dictionary: errors.append("budgets must be an object")
	else:
		for key in budgets:
			if not key in ["frametime_p95_ms","static_memory_bytes","draw_calls"] or not number(budgets[key]) or float(budgets[key])<=0: errors.append("invalid budget")
	return errors

func _ready() -> void:
	set_process(false)
	if not auto_start: return
	var path := REQUEST
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--perf-request="): path = arg.trim_prefix("--perf-request=")
	if not FileAccess.file_exists(path): queue_free();return
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not c is Dictionary or not validate_request(c).is_empty():
		push_error("Invalid benchmark request; no collection or save mutation.");get_tree().quit(2);return
	if not FileAccess.file_exists(str(c.network)):
		push_error("Benchmark network does not exist.");get_tree().quit(2);return
	Engine.set_meta("tramsim_benchmark",true)
	if not begin(c): push_error(export_error);get_tree().quit(2);return
	var doc: Dictionary = CityDataStore.document(str(c.network))
	Engine.set_meta("tramsim_benchmark_city",str(doc.get("city","")))
	metadata.network_sha256 = FileAccess.get_sha256(str(c.network))
	if path==REQUEST: DirAccess.remove_absolute(REQUEST)
	var driver := preload("res://src/diagnostics/performance_scenario.gd").new()
	driver.probe = self;add_child(driver)

func begin(c: Dictionary, source: String = "runtime_monitors") -> bool:
	if not validate_request(c).is_empty(): return false
	config = c.duplicate(true)
	if FileAccess.file_exists("user://benchmarks/"+str(c.run_id)+".json"):
		export_error = "run_id already exists; use a new run_id";return false
	enabled = true;status = "running";started_us = Time.get_ticks_usec();last_us = started_us
	metadata = {"sample_source":source,"os":OS.get_name(),"os_version":OS.get_version(),"model":OS.get_model_name(),
		"processor":OS.get_processor_name(),"godot":Engine.get_version_info().string,"display_driver":DisplayServer.get_name(),
		"rendering_method":RenderingServer.get_current_rendering_method(),"physical_device_verified":false,
		"physical_verification":"Requires external ADB emulator/hardware evidence; Android OS alone is not proof.",
		"gpu_unavailable_reason":"disabled" if not bool(c.get("gpu_timing",false)) else "unsupported_or_no_nonzero_gpu_timestamp",
		"memory_scope":"Godot static allocations, NOT Android RSS; zero/unsupported maps to null",
		"power_mode":c.get("power_mode","not_reported"),"thermal":null,"energy":null,
		"instrumentation_note":"Setup and source fingerprinting are included in loading; compare the same protocol."}
	if FileAccess.file_exists("res://data/build_info.json"):
		metadata.build = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json"))
	else:metadata.build = {"version":ProjectSettings.get_setting("application/config/version"),"source_sha":null,"reason":"unstamped_local_build"}
	if bool(c.get("gpu_timing",false)) and DisplayServer.get_name()!="headless":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	mark_phase("loading");set_process(true);return true

func mark_phase(name_: String, state: String = "started", reason: String = "") -> void:
	if state=="started":
		phase = name_;warmup_left = 0 if phase=="loading" else int(config.get("warmup_frames",10))
	events.append({"phase":name_,"status":state,"reason":reason,"seconds":(Time.get_ticks_usec()-started_us)/1000000.0})

func _process(_dt: float) -> void:
	if not enabled:return
	var now := Time.get_ticks_usec()
	var frame_ms := (now-last_us)/1000.0;last_us = now
	var gpu: Variant = null
	if bool(config.get("gpu_timing",false)) and DisplayServer.get_name()!="headless":
		var value := RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		if value>0:gpu = value
	record_frame(frame_ms,{"cpu_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000,
		"gpu_render_ms":gpu,"static_memory_bytes":OS.get_static_memory_usage() if OS.get_static_memory_usage()>0 else null,
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)})

func record_frame(frame_ms: float, values: Dictionary) -> void:
	if not enabled or not is_finite(frame_ms) or frame_ms<=0:return
	if warmup_left>0:warmup_left-=1;warmup_excluded+=1;return
	if samples.size()>=int(config.get("max_samples",MAX_SAMPLES)):finish("sample_limit");return
	var row := {"frame_ms":frame_ms,"phase":phase,"seconds":(Time.get_ticks_usec()-started_us)/1000000.0,"context":context.duplicate(true)}
	for key in ["cpu_process_ms","gpu_render_ms","static_memory_bytes","draw_calls","objects","nodes","resources"]:
		var v: Variant = values.get(key)
		row[key] = float(v) if number(v) and float(v)>=0 else null
		if key in ["gpu_render_ms","static_memory_bytes"] and row[key]==0:row[key]=null
	samples.append(row)

static func percentile(values: Array, fraction: float) -> Variant:
	if values.is_empty():return null
	var ordered := values.duplicate();ordered.sort()
	var index := clampf(fraction,0,1)*(ordered.size()-1)
	return lerpf(float(ordered[floori(index)]),float(ordered[ceili(index)]),index-floorf(index))

func summary() -> Dictionary:
	var groups := {};var result := {}
	for event in events:
		if event.status=="started" and not groups.has(event.phase):groups[event.phase]=[]
	for row in samples:
		if not groups.has(row.phase):groups[row.phase]=[]
		groups[row.phase].append(row)
	for name_ in groups:
		var rows: Array = groups[name_]
		var ms: Array = rows.map(func(r):return r.frame_ms)
		var fps: Array = ms.map(func(v):return 1000.0/float(v))
		var item := {"sampled_frames":rows.size(),"frametime_ms":{},"fps":{},"maxima":{}}
		for quantile in [["p50",.5],["p95",.95],["p99",.99]]:
			item.frametime_ms[quantile[0]]=percentile(ms,quantile[1]);item.fps[quantile[0]]=percentile(fps,quantile[1])
		for metric in ["static_memory_bytes","draw_calls","objects","nodes","resources"]:
			item.maxima[metric]=percentile(rows.map(func(r):return r[metric]).filter(func(v):return v!=null),1.0)
		for metric in ["gpu_render_ms","cpu_process_ms"]:
			item[metric+"_p95"]=percentile(rows.map(func(r):return r[metric]).filter(func(v):return v!=null),.95)
		var budgets := {}
		for metric in config.get("budgets",{}):
			var measured: Variant = item.frametime_ms.p95 if metric=="frametime_p95_ms" else item.maxima.get(metric)
			budgets[metric]={"target":config.budgets[metric],"measured":measured,"within_budget":null if measured==null else float(measured)<=float(config.budgets[metric])}
		item.budgets=budgets;result[name_]=item
	return result

func report() -> Dictionary:
	return {"schema_version":1,"kind":"performance","run_id":config.get("run_id"),"request_id":config.get("request_id"),"status":status,
		"configuration":config,"metadata":metadata,"measurements":summary(),"events":events,"warmup_frames_excluded":warmup_excluded,
		"limitations":["Headless data is not gameplay FPS; physical hardware requires ADB evidence.","Unavailable GPU, energy, thermal and RSS are not fabricated.","Fixed 1/60 simulation; rendering and asynchronous streaming are not bit-identical."]}

func finish(state: String = "completed") -> bool:
	enabled=false;set_process(false);status=state
	var directory := "user://benchmarks"
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return false
	var base := directory+"/"+str(config.get("run_id","invalid"))
	var csv := FileAccess.open(base+".csv.tmp",FileAccess.WRITE)
	if csv==null:return false
	var columns := ["seconds","phase","frame_ms","cpu_process_ms","gpu_render_ms","static_memory_bytes","draw_calls","objects","nodes","resources"]
	csv.store_csv_line(PackedStringArray(columns))
	for row in samples:
		var cells := PackedStringArray()
		for key in columns:cells.append("" if row.get(key)==null else str(row[key]))
		csv.store_csv_line(cells)
	csv.flush();csv.close()
	if DirAccess.rename_absolute(base+".csv.tmp",base+".csv")!=OK:return false
	var output := FileAccess.open(base+".json.tmp",FileAccess.WRITE)
	if output==null:return false
	output.store_string(JSON.stringify(report(),"\t"));output.flush();output.close()
	if DirAccess.rename_absolute(base+".json.tmp",base+".json")!=OK:return false
	print("PERF_REPORT|",base+".json|",state,"|",samples.size());completed.emit(state);return true

func _notification(what: int) -> void:
	if enabled and what==NOTIFICATION_APPLICATION_PAUSED:finish("interrupted_background")
