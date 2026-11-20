extends SceneTree
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	await process_frame;await process_frame
	var ok := get_root().get_node_or_null("PerformanceProbe")==null and not Engine.has_meta("tramsim_benchmark")
	print("PERF_DISABLED|",ok)
	quit(0 if ok else 1)
