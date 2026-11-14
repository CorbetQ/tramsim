extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if ok: print("ok: ", message)
	else: failures += 1; printerr("ECHEC: ", message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var meta: Dictionary = CityDataStore.document("res://data/scenes/angers.json")
	var city := CityScene.new(); root.add_child(city)
	check(city.open("angers", meta.origin), "geographic scene opens")
	city.radius = 200.0; city.enable_async_lod(); city.update(Vector3.ZERO, 1)
	check(city._lod_task >= 0, "worker running before removal")
	city.queue_free()
	await process_frame; await process_frame
	check(not is_instance_valid(city), "scene removed without synchronously joining a worker")
	var deadline := Time.get_ticks_msec() + 60000
	while CityScene.retired_lod_jobs > 0 and Time.get_ticks_msec() < deadline: await process_frame
	check(CityScene.retired_lod_jobs == 0, "orphaned tile, task and builder reclaimed")
	print("TOTAL_ECHECS|", failures); quit(1 if failures else 0)
