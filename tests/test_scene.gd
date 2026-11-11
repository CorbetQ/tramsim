extends SceneTree
func _run(main: Node, free: bool) -> bool:
	main.free_mode = free
	main.net_path = "res://tests/fixtures/schema_test.json"
	main.vehicle = VehicleLibrary.citadis_302_hybride()
	main._start()
	for i in 30: await process_frame
	var ok: bool = main.session != null and main.view != null and main.view.tram != null
	print("scène (libre=%s): %s | %s" % [free, ok, main.hud.text])
	return ok
func _init() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var a = await _run(main, false)
	var b = await _run(main, true)
	main._build_menu()
	await process_frame
	quit(0 if a and b else 1)
