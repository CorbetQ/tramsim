extends SceneTree
## Close while geography is still being prepared, with both preload and detail work active.
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	var meta: Dictionary = CityDataStore.document("res://data/scenes/angers.json")
	var view := LineView.new(); main.add_child(view); main.view = view
	var city := CityScene.new(); view.add_child(city); view.city = city
	if not city.open("angers", meta.origin): printerr("ECHEC: open"); quit(1); return
	city.radius = 200.0; city.enable_async_lod(); city.update(Vector3.ZERO, 1)
	if auto_accept_quit: printerr("ECHEC: uncontrolled automatic shutdown"); quit(1); return
	await main._quit_safely()
	if CityScene.retired_lod_jobs != 0 or not HomeBackground._orphans.is_empty(): printerr("ECHEC: unfinished jobs"); quit(1); return
	print("ok: window close drains preload and detail workers before quitting")
	print("TOTAL_ECHECS|0")
