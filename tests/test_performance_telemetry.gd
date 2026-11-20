extends SceneTree
var fails := 0
var checks := 0
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:fails+=1;printerr("ECHEC: ",text)
	else:print("ok: ",text)
func request(name_: String) -> Dictionary:
	return {"schema_version":1,"run_id":name_,"request_id":"fixture_request_01","network":"res://data/free/angers.json","warmup_frames":0,"phases":["dense_driving"],"budgets":{"frametime_p95_ms":35}}
func clean(name_: String) -> void:
	for suffix in [".json",".csv",".json.tmp",".csv.tmp"]:DirAccess.remove_absolute("user://benchmarks/"+name_+suffix)
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var name_ := "p0_telemetry_fixture"
	clean(name_)
	var before := FileAccess.get_sha256(SaveGame.DEFAULT_PATH) if FileAccess.file_exists(SaveGame.DEFAULT_PATH) else "missing"
	var controller: Node = load("res://src/ui/main.gd").new()
	Engine.set_meta("tramsim_benchmark",true)
	check(not controller.call("_save_profile"),"all menu/result save entry points reject profiling writes")
	controller.call("_persist")
	Engine.remove_meta("tramsim_benchmark");controller.queue_free()
	var after := FileAccess.get_sha256(SaveGame.DEFAULT_PATH) if FileAccess.file_exists(SaveGame.DEFAULT_PATH) else "missing"
	check(before==after,"real player save remains untouched by profiling save guard")
	var c := request(name_)
	check(PerfTelemetry.validate_request(c).is_empty(),"valid request accepted")
	var bad := c.duplicate();bad.run_id="../escape"
	check(not PerfTelemetry.validate_request(bad).is_empty(),"path traversal rejected")
	bad=c.duplicate();bad.network="https://example.org/map.json"
	check(not PerfTelemetry.validate_request(bad).is_empty(),"no runtime network source")
	bad=c.duplicate();bad.phase_seconds=NAN
	check(not PerfTelemetry.validate_request(bad).is_empty(),"invalid durations rejected")
	bad=c.duplicate();bad.phases=["night","night"]
	check(not PerfTelemetry.validate_request(bad).is_empty(),"duplicate phases rejected")
	bad=c.duplicate();bad.execute="external command"
	check(not PerfTelemetry.validate_request(bad).is_empty(),"unknown execution field rejected")
	var p := PerfTelemetry.new();p.auto_start=false;root.add_child(p)
	check(not p.enabled,"no collection by default")
	check(p.begin(c,"synthetic_fixture"),"fixture collection enabled explicitly")
	p.set_process(false);p.mark_phase("dense_driving")
	for ms in [10.0,20.0,30.0,40.0]:p.record_frame(ms,{"cpu_process_ms":1,"draw_calls":15,"gpu_render_ms":null,"static_memory_bytes":0})
	var summary: Dictionary=p.summary().dense_driving
	check(absf(summary.frametime_ms.p50-25)<.0001,"frame p50 uses actual samples")
	check(absf(summary.frametime_ms.p95-38.5)<.0001,"frame p95 interpolation correct")
	check(absf(summary.fps.p95-92.5)<.0001,"FPS percentile is not inverse frame percentile")
	check(summary.gpu_render_ms_p95==null and summary.maxima.static_memory_bytes==null,"unavailable counters stay null")
	check(summary.budgets.frametime_p95_ms.within_budget==false,"configured budget evaluated without claiming a phone measurement")
	p.record_frame(INF,{});p.record_frame(-1,{})
	check(p.samples.size()==4,"nonfinite/invalid samples ignored")
	check(p.metadata.sample_source=="synthetic_fixture" and not p.metadata.physical_device_verified,"fixture and physical-device status honest")
	p.mark_phase("rain","skipped","not implemented")
	check(p.phase=="dense_driving","skipped weather creates no measured rain samples")
	check(p.finish("completed_with_skips"),"real JSON and CSV exported")
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("user://benchmarks/"+name_+".json"))
	check(report.measurements.dense_driving.sampled_frames==4 and report.status=="completed_with_skips","report roundtrip")
	var f:=FileAccess.open("user://benchmarks/"+name_+".csv",FileAccess.READ);f.get_csv_line()
	var row:=f.get_csv_line();f.close()
	check(row[4]=="","CSV unavailable GPU field is empty")
	check(not p.begin(c,"synthetic_fixture"),"existing baseline never overwritten")
	p.queue_free();clean(name_)
	var warm:=PerfTelemetry.new();warm.auto_start=false;root.add_child(warm)
	c=request("p0_warmup_fixture");clean(c.run_id);c.warmup_frames=2;c.max_samples=2
	warm.begin(c,"synthetic_fixture");warm.set_process(false);warm.mark_phase("night")
	for i in 5:warm.record_frame(16,{})
	check(warm.warmup_excluded==2 and warm.samples.size()==2,"warmup excluded and memory bounded")
	check(warm.status=="sample_limit" and not warm.enabled,"sample limit is explicit, not silent truncation")
	warm.queue_free();clean(c.run_id)
	await process_frame
	print("CHECKS|",checks,"|TOTAL_ECHECS|",fails);quit(1 if fails else 0)
